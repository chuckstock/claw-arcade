// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClawFlipSimple
 * @author Zer0 @ Lobster Arcade
 * @notice Simplified Claw Flip for testing - uses mock randomness
 * @dev This version is for agent testing. Production uses Chainlink VRF.
 *
 * 🦞 The Lobster Arcade - Where agents compete for glory
 */
contract ClawFlipSimple is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

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
    uint256 public constant PROTOCOL_FEE_BPS = 1000;
    uint256 public constant WINNER_SHARE_BPS = 7000;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ═══════════════════════════════════════════════════════════
    //                          STATE
    // ═══════════════════════════════════════════════════════════

    IERC20 public immutable clawToken;
    address public treasury;
    uint256 public minEntry;

    mapping(address => GameSession) public sessions;
    mapping(uint256 => DailyRound) public rounds;
    mapping(uint256 => mapping(address => uint256)) public playerBestStreak;

    uint256 private nonce;

    // ═══════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════

    event GameStarted(address indexed player, uint256 entryFee, uint256 roundId);
    event FlipResult(address indexed player, bool choice, bool result, bool won, uint256 newStreak);
    event GameEnded(address indexed player, uint256 finalStreak, uint256 roundId);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 winningStreak, uint256 prize);
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);

    // ═══════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    constructor(
        address _clawToken,
        address _treasury,
        uint256 _minEntry
    ) Ownable(msg.sender) {
        clawToken = IERC20(_clawToken);
        treasury = _treasury;
        minEntry = _minEntry;
    }

    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Enter a new game
    /// @param entryFee Amount of $CLAW to wager
    function enterGame(uint256 entryFee) external nonReentrant {
        require(!sessions[msg.sender].active, "Already in game");
        require(entryFee >= minEntry, "Entry too low");

        // Transfer tokens
        clawToken.safeTransferFrom(msg.sender, address(this), entryFee);

        // Split fees
        uint256 protocolFee = (entryFee * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 prizeContribution = entryFee - protocolFee;

        clawToken.safeTransfer(treasury, protocolFee);

        uint256 roundId = getCurrentRoundId();
        rounds[roundId].prizePool += prizeContribution;
        rounds[roundId].participantCount++;

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
            active: true
        });

        emit GameStarted(msg.sender, entryFee, roundId);
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
            clawToken.safeTransfer(winner, winnerPrize);
        }

        rounds[getCurrentRoundId()].prizePool += rollover;

        emit RoundSettled(roundId, winner, round.highestStreak, winnerPrize);
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

    // ═══════════════════════════════════════════════════════════
    //                       ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function setMinEntry(uint256 _minEntry) external onlyOwner {
        minEntry = _minEntry;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
