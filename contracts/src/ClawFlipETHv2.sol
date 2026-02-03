// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title ClawFlipETHv2
 * @author Zer0 @ Lobster Arcade
 * @notice Claw Flip v2 with secure Chainlink VRF, pull-pattern prizes, and bug fixes
 * @dev Entry fees in ETH, with fee split for buyback/burn
 *
 * v2 SECURITY FIXES:
 * - Chainlink VRF V2.5 for provably fair randomness
 * - Pull pattern for prize distribution (no DoS via revert)
 * - 100% rollover when no winner (was incorrectly 30%)
 * - Referral earnings tracked AFTER successful transfer
 * - Emergency withdraw excludes active prize pools + timelock
 * - Auto-end game at max flips (256)
 * - Zero address validation throughout
 *
 * Fee Structure:
 * - 88% → Prize Pool
 * - 5%  → Buyback Accumulator (for $ZER0_AI buyback & burn)
 * - 5%  → Treasury (operations)
 * - 2%  → Referrer (or buyback if no referrer)
 *
 * 🦞 The Lobster Arcade - Where agents compete for glory
 */
contract ClawFlipETHv2 is ReentrancyGuard, Ownable, VRFConsumerBaseV2Plus {
    // ═══════════════════════════════════════════════════════════
    //                          STRUCTS
    // ═══════════════════════════════════════════════════════════

    struct GameSession {
        address player;
        uint256 entryFee;
        uint256 streak;
        uint256 flipIndex;
        uint64 startTime;
        uint256 roundId;
        address referrer;
        bool active;
        bool seedReady;  // VRF seed has been fulfilled
        uint256 vrfRequestId;  // Tracks pending VRF request
    }

    struct DailyRound {
        uint256 prizePool;
        uint256 highestStreak;
        address leader;
        uint256 participantCount;
        bool settled;
    }

    // ═══════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ═══════════════════════════════════════════════════════════

    uint256 public constant MAX_FLIPS_PER_WORD = 256;
    uint256 public constant MAX_GAME_DURATION = 1 hours;
    
    // Fee structure (basis points, 10000 = 100%)
    uint256 public constant PRIZE_POOL_BPS = 8800;      // 88%
    uint256 public constant BUYBACK_BPS = 500;          // 5%
    uint256 public constant TREASURY_BPS = 500;         // 5%
    uint256 public constant REFERRER_BPS = 200;         // 2%
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // Prize distribution
    uint256 public constant WINNER_SHARE_BPS = 7000;    // 70% to daily winner
    
    // Emergency withdraw timelock
    uint256 public constant EMERGENCY_TIMELOCK = 3 days;

    // ═══════════════════════════════════════════════════════════
    //                       VRF CONFIGURATION
    // ═══════════════════════════════════════════════════════════
    
    /// @notice VRF subscription ID
    uint256 public vrfSubscriptionId;
    
    /// @notice VRF key hash (gas lane)
    bytes32 public vrfKeyHash;
    
    /// @notice VRF callback gas limit
    uint32 public vrfCallbackGasLimit = 100000;
    
    /// @notice VRF request confirmations
    uint16 public vrfRequestConfirmations = 3;
    
    /// @notice VRF number of words (we only need 1 for 256 flips)
    uint32 public constant VRF_NUM_WORDS = 1;

    // ═══════════════════════════════════════════════════════════
    //                          STATE
    // ═══════════════════════════════════════════════════════════

    address public treasury;
    uint256 public minEntry;
    
    // Accumulated funds for buyback (to be executed periodically)
    uint256 public buybackAccumulator;
    
    // Total stats
    uint256 public totalBuybackAccumulated;
    uint256 public totalBuybackExecuted;
    uint256 public totalPrizesDistributed;

    mapping(address => GameSession) public sessions;
    mapping(uint256 => DailyRound) public rounds;
    mapping(uint256 => mapping(address => uint256)) public playerBestStreak;
    
    // VRF request ID → player address
    mapping(uint256 => address) private vrfRequestToPlayer;
    
    // Private random seeds - NOT exposed via any getter
    mapping(address => uint256) private randomSeeds;
    
    // Referral tracking
    mapping(address => address) public referredBy;
    mapping(address => uint256) public referralEarnings;
    
    // FIX #2: Pull pattern for prizes - winners can claim if direct transfer fails
    mapping(address => uint256) public unclaimedPrizes;
    
    // FIX #5: Emergency withdraw timelock
    uint256 public emergencyWithdrawUnlockTime;
    bool public emergencyWithdrawRequested;

    // ═══════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════

    event GameStarted(
        address indexed player, 
        uint256 entryFee, 
        uint256 roundId,
        address referrer,
        uint256 vrfRequestId
    );
    event SeedReady(address indexed player, uint256 vrfRequestId);
    event FlipResult(
        address indexed player, 
        bool choice, 
        bool result, 
        bool won, 
        uint256 newStreak
    );
    event GameEnded(address indexed player, uint256 finalStreak, uint256 roundId);
    event RoundSettled(
        uint256 indexed roundId, 
        address winner, 
        uint256 winningStreak, 
        uint256 prize
    );
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);
    event BuybackExecuted(uint256 amount, uint256 timestamp);
    event ReferralPaid(address indexed referrer, address indexed player, uint256 amount);
    event FeesDistributed(
        uint256 prizePool,
        uint256 buyback,
        uint256 treasury,
        uint256 referrer
    );
    
    // v2 events
    event PrizeClaimable(address indexed winner, uint256 amount);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event EmergencyWithdrawRequested(uint256 unlockTime);
    event EmergencyWithdrawCancelled();
    event EmergencyWithdrawExecuted(uint256 amount);
    event NoWinnerRollover(uint256 indexed roundId, uint256 amount);

    // ═══════════════════════════════════════════════════════════
    //                          ERRORS
    // ═══════════════════════════════════════════════════════════
    
    // ZeroAddress is inherited from VRFConsumerBaseV2Plus
    error AlreadyInGame();
    error EntryTooLow();
    error CannotReferSelf();
    error NoActiveGame();
    error SeedNotReady();
    error RoundNotEnded();
    error AlreadySettled();
    error NoParticipants();
    error NoFundsToWithdraw();
    error NoPrizeToClaim();
    error TimelockNotExpired();
    error NoEmergencyRequested();
    error NotTimedOut();
    error WithdrawalFailed();

    // ═══════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Deploy ClawFlipETH v2 with Chainlink VRF
     * @param _treasury Treasury address for fees (cannot be zero)
     * @param _minEntry Minimum entry fee in wei
     * @param _vrfCoordinator Chainlink VRF Coordinator address
     * @param _vrfSubscriptionId VRF subscription ID
     * @param _vrfKeyHash VRF key hash (gas lane)
     */
    constructor(
        address _treasury,
        uint256 _minEntry,
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _vrfKeyHash
    ) Ownable(msg.sender) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        // FIX #7: Zero address validation
        if (_treasury == address(0)) revert ZeroAddress();
        if (_vrfCoordinator == address(0)) revert ZeroAddress();
        
        treasury = _treasury;
        minEntry = _minEntry;
        vrfSubscriptionId = _vrfSubscriptionId;
        vrfKeyHash = _vrfKeyHash;
    }

    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Enter a new game with ETH
     * @dev Requests VRF randomness - player must wait for seed before flipping
     * @param referrer Optional referrer address (address(0) if none)
     */
    function enterGame(address referrer) external payable nonReentrant {
        if (sessions[msg.sender].active) revert AlreadyInGame();
        if (msg.value < minEntry) revert EntryTooLow();
        if (referrer == msg.sender) revert CannotReferSelf();

        uint256 entryFee = msg.value;
        
        // Calculate fee splits
        uint256 prizeContribution = (entryFee * PRIZE_POOL_BPS) / BPS_DENOMINATOR;
        uint256 buybackAmount = (entryFee * BUYBACK_BPS) / BPS_DENOMINATOR;
        uint256 treasuryAmount = (entryFee * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 referrerAmount = (entryFee * REFERRER_BPS) / BPS_DENOMINATOR;

        // Store referrer if first time being referred
        if (referrer != address(0) && referredBy[msg.sender] == address(0)) {
            referredBy[msg.sender] = referrer;
        }
        
        // Use stored referrer if exists
        address actualReferrer = referredBy[msg.sender];
        
        // Distribute fees
        if (actualReferrer != address(0)) {
            // FIX #4: Only update referralEarnings AFTER successful transfer
            (bool refSuccess, ) = actualReferrer.call{value: referrerAmount}("");
            if (refSuccess) {
                referralEarnings[actualReferrer] += referrerAmount;
                emit ReferralPaid(actualReferrer, msg.sender, referrerAmount);
            } else {
                // If referrer payment fails, add to buyback
                buybackAmount += referrerAmount;
            }
        } else {
            // No referrer - add to buyback
            buybackAmount += referrerAmount;
        }
        
        // Send to treasury
        (bool treasurySuccess, ) = treasury.call{value: treasuryAmount}("");
        require(treasurySuccess, "Treasury transfer failed");
        
        // Accumulate buyback funds
        buybackAccumulator += buybackAmount;
        totalBuybackAccumulated += buybackAmount;

        // Add to prize pool
        uint256 roundId = getCurrentRoundId();
        rounds[roundId].prizePool += prizeContribution;
        rounds[roundId].participantCount++;

        emit FeesDistributed(prizeContribution, buybackAmount, treasuryAmount, 
            actualReferrer != address(0) ? referrerAmount : 0);

        // FIX #1: Request Chainlink VRF instead of insecure pseudo-random
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: VRF_NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        
        // Map request to player
        vrfRequestToPlayer[requestId] = msg.sender;

        sessions[msg.sender] = GameSession({
            player: msg.sender,
            entryFee: entryFee,
            streak: 0,
            flipIndex: 0,
            startTime: uint64(block.timestamp),
            roundId: roundId,
            referrer: actualReferrer,
            active: true,
            seedReady: false,
            vrfRequestId: requestId
        });

        emit GameStarted(msg.sender, entryFee, roundId, actualReferrer, requestId);
    }

    /**
     * @notice VRF callback - sets the random seed for a player's game
     * @dev Called by VRF Coordinator - seed is stored privately, never exposed
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        address player = vrfRequestToPlayer[requestId];
        require(player != address(0), "Unknown request");
        
        GameSession storage session = sessions[player];
        require(session.active, "Game not active");
        require(!session.seedReady, "Seed already set");
        
        // Store seed privately - NOT accessible via any getter
        randomSeeds[player] = randomWords[0];
        session.seedReady = true;
        
        // Clean up mapping
        delete vrfRequestToPlayer[requestId];
        
        emit SeedReady(player, requestId);
    }

    /**
     * @notice Flip the claw! Call HEADS (true) or TAILS (false)
     * @dev Requires VRF seed to be ready. Auto-ends at max flips.
     * @param heads True for heads, false for tails
     */
    function flip(bool heads) external nonReentrant {
        GameSession storage session = sessions[msg.sender];
        if (!session.active) revert NoActiveGame();
        if (!session.seedReady) revert SeedNotReady();
        
        // FIX #6: Auto-end game at max flips instead of leaving player stuck
        if (session.flipIndex >= MAX_FLIPS_PER_WORD) {
            _endGame(msg.sender);
            return;
        }

        // Extract bit from random seed (stored privately)
        uint256 seed = randomSeeds[msg.sender];
        bool coinResult = ((seed >> session.flipIndex) & 1) == 1;
        session.flipIndex++;

        bool playerWon = (heads == coinResult);

        if (playerWon) {
            session.streak++;
            emit FlipResult(msg.sender, heads, coinResult, true, session.streak);

            // Check for new leader
            uint256 roundId = session.roundId;
            if (session.streak > rounds[roundId].highestStreak) {
                rounds[roundId].highestStreak = session.streak;
                rounds[roundId].leader = msg.sender;
                emit NewLeader(roundId, msg.sender, session.streak);
            }
            
            // FIX #6: Auto-end if we just used the last flip
            if (session.flipIndex >= MAX_FLIPS_PER_WORD) {
                _endGame(msg.sender);
            }
        } else {
            emit FlipResult(msg.sender, heads, coinResult, false, session.streak);
            _endGame(msg.sender);
        }
    }

    /**
     * @notice Voluntarily end your game and lock in your streak
     */
    function cashOut() external nonReentrant {
        if (!sessions[msg.sender].active) revert NoActiveGame();
        _endGame(msg.sender);
    }

    /**
     * @notice Timeout an inactive game
     * @param player Address of the player to timeout
     */
    function timeoutGame(address player) external nonReentrant {
        GameSession storage session = sessions[player];
        if (!session.active) revert NoActiveGame();
        if (block.timestamp <= session.startTime + MAX_GAME_DURATION) revert NotTimedOut();
        _endGame(player);
    }
    
    /**
     * @notice Check if player's seed is ready for flipping
     * @param player Address to check
     * @return ready True if seed is ready
     */
    function isSeedReady(address player) external view returns (bool ready) {
        return sessions[player].seedReady;
    }

    // ═══════════════════════════════════════════════════════════
    //                      INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function _endGame(address player) internal {
        GameSession storage session = sessions[player];
        uint256 finalStreak = session.streak;
        uint256 roundId = session.roundId;

        if (finalStreak > playerBestStreak[roundId][player]) {
            playerBestStreak[roundId][player] = finalStreak;
        }

        session.active = false;
        
        // Clear sensitive data
        delete randomSeeds[player];
        
        emit GameEnded(player, finalStreak, roundId);
    }

    // ═══════════════════════════════════════════════════════════
    //                      ROUND SETTLEMENT
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Settle a completed daily round
     * @dev Uses pull pattern - failed transfers store in unclaimedPrizes
     * @param roundId Round ID to settle
     */
    function settleRound(uint256 roundId) external nonReentrant {
        if (roundId >= getCurrentRoundId()) revert RoundNotEnded();
        DailyRound storage round = rounds[roundId];
        if (round.settled) revert AlreadySettled();
        if (round.participantCount == 0) revert NoParticipants();

        round.settled = true;

        uint256 prize = round.prizePool;
        address winner = round.leader;

        // FIX #3: If no winner, rollover 100% (not 30%)
        if (winner == address(0)) {
            // No winner - rollover entire prize pool
            rounds[getCurrentRoundId()].prizePool += prize;
            emit NoWinnerRollover(roundId, prize);
            emit RoundSettled(roundId, address(0), 0, 0);
            return;
        }

        uint256 winnerPrize = (prize * WINNER_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 rollover = prize - winnerPrize;

        // FIX #2: Pull pattern - if transfer fails, store for later claim
        if (winnerPrize > 0) {
            (bool success, ) = winner.call{value: winnerPrize}("");
            if (success) {
                totalPrizesDistributed += winnerPrize;
            } else {
                // Store for pull-based claim instead of reverting
                unclaimedPrizes[winner] += winnerPrize;
                emit PrizeClaimable(winner, winnerPrize);
            }
        }

        // Rollover remaining to next round
        rounds[getCurrentRoundId()].prizePool += rollover;

        emit RoundSettled(roundId, winner, round.highestStreak, winnerPrize);
    }
    
    /**
     * @notice Claim unclaimed prizes (pull pattern)
     * @dev Winners call this if their prize transfer failed during settlement
     */
    function claimPrize() external nonReentrant {
        uint256 amount = unclaimedPrizes[msg.sender];
        if (amount == 0) revert NoPrizeToClaim();
        
        // Clear before transfer (CEI pattern)
        unclaimedPrizes[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        
        totalPrizesDistributed += amount;
        emit PrizeClaimed(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════
    //                      BUYBACK FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Withdraw accumulated buyback funds (owner only)
     * @dev Funds sent to owner for executing buyback on DEX
     */
    function withdrawBuybackFunds() external onlyOwner nonReentrant {
        uint256 amount = buybackAccumulator;
        if (amount == 0) revert NoFundsToWithdraw();
        
        buybackAccumulator = 0;
        totalBuybackExecuted += amount;
        
        (bool success, ) = owner().call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        
        emit BuybackExecuted(amount, block.timestamp);
    }

    /**
     * @notice Get current buyback accumulator balance
     */
    function getBuybackBalance() external view returns (uint256) {
        return buybackAccumulator;
    }

    // ═══════════════════════════════════════════════════════════
    //                         VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function getCurrentRoundId() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /**
     * @notice Get session info (excludes random seed for security)
     */
    function getSession(address player) external view returns (
        address playerAddr,
        uint256 entryFee,
        uint256 streak,
        uint256 flipIndex,
        uint64 startTime,
        uint256 roundId,
        address referrer,
        bool active,
        bool seedReady
    ) {
        GameSession memory session = sessions[player];
        return (
            session.player,
            session.entryFee,
            session.streak,
            session.flipIndex,
            session.startTime,
            session.roundId,
            session.referrer,
            session.active,
            session.seedReady
        );
    }

    function getRound(uint256 roundId) external view returns (DailyRound memory) {
        return rounds[roundId];
    }

    function getCurrentRound() external view returns (DailyRound memory) {
        return rounds[getCurrentRoundId()];
    }
    
    function getStats() external view returns (
        uint256 _totalBuybackAccumulated,
        uint256 _totalBuybackExecuted,
        uint256 _totalPrizesDistributed,
        uint256 _currentBuybackBalance
    ) {
        return (
            totalBuybackAccumulated,
            totalBuybackExecuted,
            totalPrizesDistributed,
            buybackAccumulator
        );
    }
    
    /**
     * @notice Get total active prize pools (current + unsettled rounds)
     * @dev Used to calculate emergency withdraw exclusions
     */
    function getActivePrizePools() public view returns (uint256 total) {
        uint256 currentRound = getCurrentRoundId();
        
        // Current round pool
        total = rounds[currentRound].prizePool;
        
        // Check last 7 days for unsettled rounds
        for (uint256 i = 1; i <= 7 && i <= currentRound; i++) {
            uint256 pastRound = currentRound - i;
            if (!rounds[pastRound].settled && rounds[pastRound].prizePool > 0) {
                total += rounds[pastRound].prizePool;
            }
        }
        
        return total;
    }

    // ═══════════════════════════════════════════════════════════
    //                       ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function setMinEntry(uint256 _minEntry) external onlyOwner {
        minEntry = _minEntry;
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address (cannot be zero)
     */
    function setTreasury(address _treasury) external onlyOwner {
        // FIX #7: Zero address validation
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }
    
    /**
     * @notice Update VRF configuration
     */
    function setVRFConfig(
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        vrfSubscriptionId = _subscriptionId;
        vrfKeyHash = _keyHash;
        vrfCallbackGasLimit = _callbackGasLimit;
        vrfRequestConfirmations = _requestConfirmations;
    }
    
    // ═══════════════════════════════════════════════════════════
    //                   EMERGENCY FUNCTIONS (FIX #5)
    // ═══════════════════════════════════════════════════════════
    
    /**
     * @notice Request emergency withdraw - starts timelock
     * @dev Must wait EMERGENCY_TIMELOCK before executing
     */
    function requestEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawUnlockTime = block.timestamp + EMERGENCY_TIMELOCK;
        emergencyWithdrawRequested = true;
        emit EmergencyWithdrawRequested(emergencyWithdrawUnlockTime);
    }
    
    /**
     * @notice Cancel emergency withdraw request
     */
    function cancelEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawRequested = false;
        emergencyWithdrawUnlockTime = 0;
        emit EmergencyWithdrawCancelled();
    }
    
    /**
     * @notice Execute emergency withdraw after timelock
     * @dev Excludes active prize pools to protect player funds
     */
    function executeEmergencyWithdraw() external onlyOwner nonReentrant {
        if (!emergencyWithdrawRequested) revert NoEmergencyRequested();
        if (block.timestamp < emergencyWithdrawUnlockTime) revert TimelockNotExpired();
        
        // FIX #5: Exclude active prize pools from emergency withdraw
        uint256 activePools = getActivePrizePools();
        uint256 totalBalance = address(this).balance;
        
        // Can only withdraw funds not committed to prize pools
        uint256 withdrawable = totalBalance > activePools ? totalBalance - activePools : 0;
        
        if (withdrawable == 0) revert NoFundsToWithdraw();
        
        // Reset state
        emergencyWithdrawRequested = false;
        emergencyWithdrawUnlockTime = 0;
        
        // Also deduct from buyback accumulator if that's what we're withdrawing
        if (buybackAccumulator > 0) {
            uint256 buybackWithdrawn = withdrawable > buybackAccumulator ? buybackAccumulator : withdrawable;
            buybackAccumulator -= buybackWithdrawn;
        }
        
        (bool success, ) = owner().call{value: withdrawable}("");
        if (!success) revert WithdrawalFailed();
        
        emit EmergencyWithdrawExecuted(withdrawable);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
