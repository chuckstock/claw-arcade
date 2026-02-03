// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IClawFlip
 * @notice Interface for the Claw Flip coinflip streak game
 */
interface IClawFlip {
    // ═══════════════════════════════════════════════════════════
    //                          STRUCTS
    // ═══════════════════════════════════════════════════════════

    /// @notice State of a player's game session
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

    /// @notice State of a daily round
    struct DailyRound {
        uint256 prizePool;
        uint256 highestStreak;
        address leader;
        uint256 participantCount;
        bool settled;
    }

    // ═══════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════

    /// @notice Emitted when a player starts a new game
    event GameStarted(address indexed player, uint256 entryFee, uint256 indexed roundId, uint256 requestId);

    /// @notice Emitted after each flip
    event FlipResult(address indexed player, bool choice, bool result, bool won, uint256 newStreak);

    /// @notice Emitted when a game ends
    event GameEnded(address indexed player, uint256 finalStreak, uint256 indexed roundId);

    /// @notice Emitted when a daily round is settled
    event RoundSettled(uint256 indexed roundId, address winner, uint256 winningStreak, uint256 prize);

    /// @notice Emitted when there's a new round leader
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);

    /// @notice Emitted when VRF randomness is received
    event RandomnessReceived(address indexed player, uint256 requestId);

    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Enter a new game with an entry fee
    /// @param entryFee Amount of $CLAW to stake (must be >= minEntry)
    function enterGame(uint256 entryFee) external;

    /// @notice Flip the coin - choose heads (true) or tails (false)
    /// @param heads True for heads, false for tails
    function flip(bool heads) external;

    /// @notice Voluntarily end your game and record your streak
    function endGame() external;

    /// @notice Timeout an inactive game after MAX_GAME_DURATION
    /// @param player Address of the player to timeout
    function timeoutGame(address player) external;

    /// @notice Settle a completed daily round and distribute prizes
    /// @param roundId The round ID to settle
    function settleRound(uint256 roundId) external;

    // ═══════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get the current round ID (Unix day number)
    function getCurrentRoundId() external view returns (uint256);

    /// @notice Get a player's game session
    function getSession(address player) external view returns (GameSession memory);

    /// @notice Get a specific round's data
    function getRound(uint256 roundId) external view returns (DailyRound memory);

    /// @notice Get the current round's data
    function getCurrentRound() external view returns (DailyRound memory);

    /// @notice Check if a player can flip (has active game with randomness)
    function canFlip(address player) external view returns (bool);

    /// @notice Get remaining flips for a player
    function remainingFlips(address player) external view returns (uint256);
}
