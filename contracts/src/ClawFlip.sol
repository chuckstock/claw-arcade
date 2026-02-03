// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IClawFlip} from "./interfaces/IClawFlip.sol";

/**
 * @title ClawFlip
 * @author Lobster Arcade
 * @notice Coinflip streak game where the longest daily streak wins the prize pool
 * @dev Uses Chainlink VRF v2.5 for provably fair randomness
 *
 * Game Flow:
 * 1. Player calls enterGame(entryFee) - pays $CLAW, requests VRF randomness
 * 2. VRF callback provides 256 bits of randomness
 * 3. Player calls flip(heads/tails) repeatedly until they lose or quit
 * 4. Streak is recorded; highest daily streak wins 70% of prize pool
 */
contract ClawFlip is IClawFlip, VRFConsumerBaseV2Plus, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ═══════════════════════════════════════════════════════════

    /// @notice Maximum flips per VRF word (256 bits = 256 flips)
    uint256 public constant MAX_FLIPS_PER_WORD = 256;

    /// @notice Maximum game duration before timeout (1 hour)
    uint256 public constant MAX_GAME_DURATION = 1 hours;

    /// @notice Protocol fee in basis points (10% = 1000 bps)
    uint256 public constant PROTOCOL_FEE_BPS = 1000;

    /// @notice Winner share of prize pool (70%)
    uint256 public constant WINNER_SHARE_BPS = 7000;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ═══════════════════════════════════════════════════════════
    //                        VRF CONFIG
    // ═══════════════════════════════════════════════════════════

    /// @notice VRF callback gas limit
    uint32 public constant CALLBACK_GAS_LIMIT = 200_000;

    /// @notice VRF request confirmations
    uint16 public constant REQUEST_CONFIRMATIONS = 1;

    /// @notice Number of random words per request
    uint32 public constant NUM_WORDS = 1;

    /// @notice VRF key hash (gas lane)
    bytes32 public keyHash;

    /// @notice Chainlink VRF subscription ID
    uint256 public subscriptionId;

    /// @notice Whether to pay VRF in native ETH (true) or LINK (false)
    bool public payVrfInNative = true;

    // ═══════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════

    /// @notice The $CLAW token contract
    IERC20 public immutable claw;

    /// @notice Minimum entry fee
    uint256 public minEntry;

    /// @notice Treasury address for protocol fees
    address public treasury;

    /// @notice Player address => Game session
    mapping(address => GameSession) private _sessions;

    /// @notice VRF request ID => Player address
    mapping(uint256 => address) public vrfRequestToPlayer;

    /// @notice Round ID => Round data
    mapping(uint256 => DailyRound) private _rounds;

    /// @notice Round ID => Player => Best streak
    mapping(uint256 => mapping(address => uint256)) public playerBestStreak;

    // ═══════════════════════════════════════════════════════════
    //                          ERRORS
    // ═══════════════════════════════════════════════════════════

    error AlreadyInGame();
    error NoActiveGame();
    error EntryTooLow(uint256 provided, uint256 minimum);
    error WaitingForVRF();
    error MaxFlipsReached();
    error NotTimedOut();
    error RoundNotEnded();
    error RoundAlreadySettled();
    error NoParticipants();
    error UnknownVRFRequest();
    error InvalidAddress();
    error InvalidKeyHash();

    // ═══════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Deploy ClawFlip game contract
     * @param vrfCoordinator Chainlink VRF Coordinator address
     * @param clawToken $CLAW token address
     * @param _subscriptionId Chainlink VRF subscription ID
     * @param _keyHash VRF key hash for gas lane selection
     * @param _minEntry Minimum entry fee in $CLAW
     * @param _treasury Treasury address for protocol fees
     */
    constructor(
        address vrfCoordinator,
        address clawToken,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint256 _minEntry,
        address _treasury
    ) VRFConsumerBaseV2Plus(vrfCoordinator) Ownable(msg.sender) {
        if (clawToken == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();
        if (_keyHash == bytes32(0)) revert InvalidKeyHash();

        claw = IERC20(clawToken);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        minEntry = _minEntry;
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Enter a new game session
     * @param entryFee Amount of $CLAW to stake
     */
    function enterGame(uint256 entryFee) external nonReentrant whenNotPaused {
        if (_sessions[msg.sender].active) revert AlreadyInGame();
        if (entryFee < minEntry) revert EntryTooLow(entryFee, minEntry);

        // Transfer $CLAW from player
        claw.safeTransferFrom(msg.sender, address(this), entryFee);

        // Split: 90% to prize pool, 10% to treasury
        uint256 protocolFee = (entryFee * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 prizeContribution = entryFee - protocolFee;

        // Send protocol fee to treasury
        claw.safeTransfer(treasury, protocolFee);

        // Add to current round's prize pool
        uint256 roundId = getCurrentRoundId();
        _rounds[roundId].prizePool += prizeContribution;
        _rounds[roundId].participantCount++;

        // Request VRF randomness
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: payVrfInNative}))
            })
        );

        vrfRequestToPlayer[requestId] = msg.sender;

        // Initialize session
        _sessions[msg.sender] = GameSession({
            player: msg.sender,
            entryFee: entryFee,
            streak: 0,
            randomSeed: 0,
            flipIndex: 0,
            startTime: uint64(block.timestamp),
            roundId: roundId,
            active: true
        });

        emit GameStarted(msg.sender, entryFee, roundId, requestId);
    }

    /**
     * @notice Flip the coin - call HEADS (true) or TAILS (false)
     * @param heads True for heads, false for tails
     */
    function flip(bool heads) external nonReentrant whenNotPaused {
        GameSession storage session = _sessions[msg.sender];

        if (!session.active) revert NoActiveGame();
        if (session.randomSeed == 0) revert WaitingForVRF();
        if (session.flipIndex >= MAX_FLIPS_PER_WORD) revert MaxFlipsReached();

        // Extract the next bit from the random seed
        bool coinResult = ((session.randomSeed >> session.flipIndex) & 1) == 1;
        session.flipIndex++;

        bool playerWon = (heads == coinResult);

        if (playerWon) {
            session.streak++;
            emit FlipResult(msg.sender, heads, coinResult, true, session.streak);

            // Check if new round leader
            uint256 roundId = session.roundId;
            if (session.streak > _rounds[roundId].highestStreak) {
                _rounds[roundId].highestStreak = session.streak;
                _rounds[roundId].leader = msg.sender;
                emit NewLeader(roundId, msg.sender, session.streak);
            }
        } else {
            emit FlipResult(msg.sender, heads, coinResult, false, session.streak);
            _endGame(msg.sender);
        }
    }

    /**
     * @notice Voluntarily end your game (cash out your streak)
     */
    function endGame() external nonReentrant {
        if (!_sessions[msg.sender].active) revert NoActiveGame();
        _endGame(msg.sender);
    }

    /**
     * @notice Timeout an inactive game
     * @param player Address of the player to timeout
     */
    function timeoutGame(address player) external nonReentrant {
        GameSession storage session = _sessions[player];
        if (!session.active) revert NoActiveGame();
        if (block.timestamp <= session.startTime + MAX_GAME_DURATION) revert NotTimedOut();
        _endGame(player);
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Internal function to end a game and record the streak
     * @param player Address of the player
     */
    function _endGame(address player) internal {
        GameSession storage session = _sessions[player];
        uint256 finalStreak = session.streak;
        uint256 roundId = session.roundId;

        // Update player's best streak for this round
        if (finalStreak > playerBestStreak[roundId][player]) {
            playerBestStreak[roundId][player] = finalStreak;
        }

        // Deactivate session
        session.active = false;

        emit GameEnded(player, finalStreak, roundId);
    }

    /**
     * @notice VRF callback - receives random number
     * @param requestId The VRF request ID
     * @param randomWords Array of random words
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address player = vrfRequestToPlayer[requestId];
        if (player == address(0)) revert UnknownVRFRequest();

        _sessions[player].randomSeed = randomWords[0];
        delete vrfRequestToPlayer[requestId];

        emit RandomnessReceived(player, requestId);
    }

    // ═══════════════════════════════════════════════════════════
    //                     ROUND SETTLEMENT
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Settle a completed daily round
     * @param roundId The round ID to settle
     */
    function settleRound(uint256 roundId) external nonReentrant {
        if (roundId >= getCurrentRoundId()) revert RoundNotEnded();

        DailyRound storage round = _rounds[roundId];
        if (round.settled) revert RoundAlreadySettled();
        if (round.participantCount == 0) revert NoParticipants();

        round.settled = true;

        uint256 prize = round.prizePool;
        address winner = round.leader;

        // Winner takes 70%
        uint256 winnerPrize = (prize * WINNER_SHARE_BPS) / BPS_DENOMINATOR;
        // 30% rolls over to next round
        uint256 rollover = prize - winnerPrize;

        // Transfer prize to winner
        if (winner != address(0) && winnerPrize > 0) {
            claw.safeTransfer(winner, winnerPrize);
        }

        // Add rollover to current round
        _rounds[getCurrentRoundId()].prizePool += rollover;

        emit RoundSettled(roundId, winner, round.highestStreak, winnerPrize);
    }

    // ═══════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Get the current round ID (Unix day number)
     * @return Current round ID
     */
    function getCurrentRoundId() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /**
     * @notice Get a player's game session
     * @param player Player address
     * @return The player's game session
     */
    function getSession(address player) external view returns (GameSession memory) {
        return _sessions[player];
    }

    /**
     * @notice Get a specific round's data
     * @param roundId Round ID to query
     * @return The round data
     */
    function getRound(uint256 roundId) external view returns (DailyRound memory) {
        return _rounds[roundId];
    }

    /**
     * @notice Get the current round's data
     * @return The current round data
     */
    function getCurrentRound() external view returns (DailyRound memory) {
        return _rounds[getCurrentRoundId()];
    }

    /**
     * @notice Check if a player can flip (has active game with randomness)
     * @param player Player address
     * @return True if player can flip
     */
    function canFlip(address player) external view returns (bool) {
        GameSession storage session = _sessions[player];
        return session.active && session.randomSeed != 0 && session.flipIndex < MAX_FLIPS_PER_WORD;
    }

    /**
     * @notice Get remaining flips for a player
     * @param player Player address
     * @return Number of remaining flips
     */
    function remainingFlips(address player) external view returns (uint256) {
        GameSession storage session = _sessions[player];
        if (!session.active || session.randomSeed == 0) return 0;
        return MAX_FLIPS_PER_WORD - session.flipIndex;
    }

    // ═══════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Set minimum entry fee
     * @param _minEntry New minimum entry
     */
    function setMinEntry(uint256 _minEntry) external onlyOwner {
        minEntry = _minEntry;
    }

    /**
     * @notice Set VRF subscription ID
     * @param _subscriptionId New subscription ID
     */
    function setSubscriptionId(uint256 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    /**
     * @notice Set VRF key hash
     * @param _keyHash New key hash
     */
    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        if (_keyHash == bytes32(0)) revert InvalidKeyHash();
        keyHash = _keyHash;
    }

    /**
     * @notice Set treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
    }

    /**
     * @notice Set VRF payment method
     * @param _payInNative True to pay in ETH, false for LINK
     */
    function setPayVrfInNative(bool _payInNative) external onlyOwner {
        payVrfInNative = _payInNative;
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens (use carefully)
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
