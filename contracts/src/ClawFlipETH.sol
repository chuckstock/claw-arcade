// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClawFlipETH
 * @author Zer0 @ Lobster Arcade
 * @notice Claw Flip with ETH entries and $ZER0_AI buyback mechanics
 * @dev Entry fees in ETH, with fee split for buyback/burn
 *
 * Fee Structure:
 * - 88% → Prize Pool
 * - 5%  → Buyback Accumulator (for $ZER0_AI buyback & burn)
 * - 5%  → Treasury (operations)
 * - 2%  → Referrer (or buyback if no referrer)
 *
 * 🦞 The Lobster Arcade - Where agents compete for glory
 */
contract ClawFlipETH is ReentrancyGuard, Ownable {
    // ═══════════════════════════════════════════════════════════
    //                          STRUCTS
    // ═══════════════════════════════════════════════════════════

    struct GameSession {
        address player;
        uint256 entryFee;
        uint256 streak;
        uint256 randomSeed;
        uint256 flipIndex;
        uint64 startTime;
        uint256 roundId;
        address referrer;
        bool active;
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
    
    // Referral tracking
    mapping(address => address) public referredBy;
    mapping(address => uint256) public referralEarnings;

    uint256 private nonce;

    // ═══════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════

    event GameStarted(
        address indexed player, 
        uint256 entryFee, 
        uint256 roundId,
        address referrer
    );
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

    // ═══════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    constructor(
        address _treasury,
        uint256 _minEntry
    ) Ownable(msg.sender) {
        treasury = _treasury;
        minEntry = _minEntry;
    }

    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Enter a new game with ETH
    /// @param referrer Optional referrer address (address(0) if none)
    function enterGame(address referrer) external payable nonReentrant {
        require(!sessions[msg.sender].active, "Already in game");
        require(msg.value >= minEntry, "Entry too low");
        require(referrer != msg.sender, "Cannot refer yourself");

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
            // Pay referrer
            referralEarnings[actualReferrer] += referrerAmount;
            (bool refSuccess, ) = actualReferrer.call{value: referrerAmount}("");
            if (refSuccess) {
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

        // Generate pseudo-random seed (NOT SECURE - use VRF in production)
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            nonce++
        )));

        sessions[msg.sender] = GameSession({
            player: msg.sender,
            entryFee: entryFee,
            streak: 0,
            randomSeed: seed,
            flipIndex: 0,
            startTime: uint64(block.timestamp),
            roundId: roundId,
            referrer: actualReferrer,
            active: true
        });

        emit GameStarted(msg.sender, entryFee, roundId, actualReferrer);
    }

    /// @notice Flip the claw! Call HEADS (true) or TAILS (false)
    /// @param heads True for heads, false for tails
    function flip(bool heads) external nonReentrant {
        GameSession storage session = sessions[msg.sender];
        require(session.active, "No active game");
        require(session.flipIndex < MAX_FLIPS_PER_WORD, "Max flips reached");

        // Extract bit from random seed
        bool coinResult = ((session.randomSeed >> session.flipIndex) & 1) == 1;
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
        } else {
            emit FlipResult(msg.sender, heads, coinResult, false, session.streak);
            _endGame(msg.sender);
        }
    }

    /// @notice Voluntarily end your game and lock in your streak
    function cashOut() external nonReentrant {
        require(sessions[msg.sender].active, "No active game");
        _endGame(msg.sender);
    }

    /// @notice Timeout an inactive game
    function timeoutGame(address player) external nonReentrant {
        GameSession storage session = sessions[player];
        require(session.active, "No active game");
        require(
            block.timestamp > session.startTime + MAX_GAME_DURATION,
            "Not timed out"
        );
        _endGame(player);
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
        emit GameEnded(player, finalStreak, roundId);
    }

    // ═══════════════════════════════════════════════════════════
    //                      ROUND SETTLEMENT
    // ═══════════════════════════════════════════════════════════

    /// @notice Settle a completed daily round
    function settleRound(uint256 roundId) external nonReentrant {
        require(roundId < getCurrentRoundId(), "Round not ended");
        DailyRound storage round = rounds[roundId];
        require(!round.settled, "Already settled");
        require(round.participantCount > 0, "No participants");

        round.settled = true;

        uint256 prize = round.prizePool;
        address winner = round.leader;

        uint256 winnerPrize = (prize * WINNER_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 rollover = prize - winnerPrize;

        if (winner != address(0) && winnerPrize > 0) {
            (bool success, ) = winner.call{value: winnerPrize}("");
            require(success, "Winner payment failed");
            totalPrizesDistributed += winnerPrize;
        }

        // Rollover remaining to next round
        rounds[getCurrentRoundId()].prizePool += rollover;

        emit RoundSettled(roundId, winner, round.highestStreak, winnerPrize);
    }

    // ═══════════════════════════════════════════════════════════
    //                      BUYBACK FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Withdraw accumulated buyback funds (owner only)
    /// @dev Funds sent to owner for executing buyback on DEX
    function withdrawBuybackFunds() external onlyOwner nonReentrant {
        uint256 amount = buybackAccumulator;
        require(amount > 0, "No funds to withdraw");
        
        buybackAccumulator = 0;
        totalBuybackExecuted += amount;
        
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit BuybackExecuted(amount, block.timestamp);
    }

    /// @notice Get current buyback accumulator balance
    function getBuybackBalance() external view returns (uint256) {
        return buybackAccumulator;
    }

    // ═══════════════════════════════════════════════════════════
    //                         VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function getCurrentRoundId() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function getSession(address player) external view returns (GameSession memory) {
        return sessions[player];
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

    // ═══════════════════════════════════════════════════════════
    //                       ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function setMinEntry(uint256 _minEntry) external onlyOwner {
        minEntry = _minEntry;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
    
    /// @notice Emergency withdraw (owner only)
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
