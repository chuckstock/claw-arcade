// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ClawToken} from "../src/ClawToken.sol";
import {ClawFlip} from "../src/ClawFlip.sol";
import {IClawFlip} from "../src/interfaces/IClawFlip.sol";

/**
 * @title MockVRFCoordinator
 * @notice Mock VRF Coordinator for testing
 */
contract MockVRFCoordinator {
    uint256 public nextRequestId = 1;
    mapping(uint256 => address) public requestToConsumer;

    function requestRandomWords(bytes memory /* request */ ) external returns (uint256) {
        uint256 requestId = nextRequestId++;
        requestToConsumer[requestId] = msg.sender;
        return requestId;
    }

    // Fulfill randomness to a consumer
    function fulfillRandomWords(uint256 requestId, uint256 randomWord) external {
        address consumer = requestToConsumer[requestId];
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;

        // Call the consumer's fulfillRandomWords
        (bool success,) = consumer.call(abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, words));
        require(success, "Fulfillment failed");
    }
}

/**
 * @title ClawFlipTest
 * @notice Unit tests for the ClawFlip game contract
 */
contract ClawFlipTest is Test {
    ClawToken public clawToken;
    ClawFlip public clawFlip;
    MockVRFCoordinator public vrfCoordinator;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant MIN_ENTRY = 10 * 10 ** 18;
    uint256 public constant SUBSCRIPTION_ID = 1;
    bytes32 public constant KEY_HASH = keccak256("test-key-hash");

    // Known random seed where first 8 bits are: 1,0,1,1,0,0,1,0 (0xB2 = 178)
    // Player wins on heads: bits 0,2,3,6 (positions 0,2,3,6)
    // Player loses on heads: bits 1,4,5,7
    uint256 public constant TEST_RANDOM_SEED = 0xB2; // 10110010 in binary

    event GameStarted(address indexed player, uint256 entryFee, uint256 indexed roundId, uint256 requestId);
    event FlipResult(address indexed player, bool choice, bool result, bool won, uint256 newStreak);
    event GameEnded(address indexed player, uint256 finalStreak, uint256 indexed roundId);
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 winningStreak, uint256 prize);

    function setUp() public {
        // Deploy mock VRF
        vrfCoordinator = new MockVRFCoordinator();

        // Deploy token
        clawToken = new ClawToken(owner, INITIAL_SUPPLY);

        // Deploy game
        clawFlip = new ClawFlip(
            address(vrfCoordinator),
            address(clawToken),
            SUBSCRIPTION_ID,
            KEY_HASH,
            MIN_ENTRY,
            treasury
        );

        // Fund players
        clawToken.transfer(player1, 10000 * 10 ** 18);
        clawToken.transfer(player2, 10000 * 10 ** 18);

        // Approve game contract
        vm.prank(player1);
        clawToken.approve(address(clawFlip), type(uint256).max);

        vm.prank(player2);
        clawToken.approve(address(clawFlip), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════
    //                        TOKEN TESTS
    // ═══════════════════════════════════════════════════════════

    function test_TokenDeployment() public view {
        assertEq(clawToken.name(), "Claw Token");
        assertEq(clawToken.symbol(), "CLAW");
        assertEq(clawToken.decimals(), 18);
        assertEq(clawToken.totalSupply(), INITIAL_SUPPLY);
    }

    function test_TokenMaxSupply() public {
        uint256 remaining = clawToken.MAX_SUPPLY() - clawToken.totalSupply();
        clawToken.mint(player1, remaining);

        vm.expectRevert();
        clawToken.mint(player1, 1);
    }

    // ═══════════════════════════════════════════════════════════
    //                      GAME ENTRY TESTS
    // ═══════════════════════════════════════════════════════════

    function test_EnterGame() public {
        uint256 entryFee = 100 * 10 ** 18;
        uint256 roundId = clawFlip.getCurrentRoundId();

        vm.prank(player1);
        vm.expectEmit(true, true, true, true);
        emit GameStarted(player1, entryFee, roundId, 1);
        clawFlip.enterGame(entryFee);

        // Check session
        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertEq(session.player, player1);
        assertEq(session.entryFee, entryFee);
        assertEq(session.streak, 0);
        assertEq(session.randomSeed, 0); // VRF not fulfilled yet
        assertTrue(session.active);

        // Check round prize pool (90% of entry)
        IClawFlip.DailyRound memory round = clawFlip.getRound(roundId);
        assertEq(round.prizePool, (entryFee * 90) / 100);
        assertEq(round.participantCount, 1);

        // Check treasury received 10%
        assertEq(clawToken.balanceOf(treasury), (entryFee * 10) / 100);
    }

    function test_EnterGame_RevertIfAlreadyInGame() public {
        uint256 entryFee = 100 * 10 ** 18;

        vm.startPrank(player1);
        clawFlip.enterGame(entryFee);

        vm.expectRevert(ClawFlip.AlreadyInGame.selector);
        clawFlip.enterGame(entryFee);
        vm.stopPrank();
    }

    function test_EnterGame_RevertIfEntryTooLow() public {
        uint256 lowEntry = 5 * 10 ** 18; // Below MIN_ENTRY

        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(ClawFlip.EntryTooLow.selector, lowEntry, MIN_ENTRY));
        clawFlip.enterGame(lowEntry);
    }

    // ═══════════════════════════════════════════════════════════
    //                        FLIP TESTS
    // ═══════════════════════════════════════════════════════════

    function test_Flip_WaitingForVRF() public {
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        // Try to flip before VRF callback
        vm.prank(player1);
        vm.expectRevert(ClawFlip.WaitingForVRF.selector);
        clawFlip.flip(true);
    }

    function test_Flip_Win() public {
        // Enter game
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        // Fulfill VRF with known seed (first bit is 0, so tails wins)
        // Seed 0xB2 = 10110010, bit 0 is 0 (tails)
        vrfCoordinator.fulfillRandomWords(1, TEST_RANDOM_SEED);

        // Flip tails (bit 0 is 0, so tails = false wins)
        vm.prank(player1);
        vm.expectEmit(true, true, true, true);
        emit FlipResult(player1, false, false, true, 1);
        clawFlip.flip(false); // tails

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertEq(session.streak, 1);
        assertEq(session.flipIndex, 1);
        assertTrue(session.active);
    }

    function test_Flip_Lose() public {
        uint256 roundId = clawFlip.getCurrentRoundId();

        // Enter game
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        // Fulfill VRF (bit 0 is 0)
        vrfCoordinator.fulfillRandomWords(1, TEST_RANDOM_SEED);

        // Flip heads when bit is 0 (tails) - should lose
        vm.prank(player1);
        vm.expectEmit(true, true, true, true);
        emit FlipResult(player1, true, false, false, 0);
        vm.expectEmit(true, true, true, true);
        emit GameEnded(player1, 0, roundId);
        clawFlip.flip(true); // heads - loses

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertFalse(session.active);
    }

    function test_Flip_MultipleWins() public {
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        // Use a seed where we know the bit pattern
        // All 1s means heads (true) always wins
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        // Win 5 flips with heads
        vm.startPrank(player1);
        for (uint256 i = 1; i <= 5; i++) {
            clawFlip.flip(true);
            assertEq(clawFlip.getSession(player1).streak, i);
        }
        vm.stopPrank();
    }

    function test_Flip_NewLeader() public {
        uint256 roundId = clawFlip.getCurrentRoundId();

        // Player 1 enters and gets 3 streak
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        vm.startPrank(player1);
        clawFlip.flip(true);
        clawFlip.flip(true);

        vm.expectEmit(true, true, true, true);
        emit NewLeader(roundId, player1, 3);
        clawFlip.flip(true);
        clawFlip.endGame();
        vm.stopPrank();

        assertEq(clawFlip.getRound(roundId).leader, player1);
        assertEq(clawFlip.getRound(roundId).highestStreak, 3);

        // Player 2 beats the streak
        vm.prank(player2);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(2, type(uint256).max);

        vm.startPrank(player2);
        clawFlip.flip(true);
        clawFlip.flip(true);
        clawFlip.flip(true);

        vm.expectEmit(true, true, true, true);
        emit NewLeader(roundId, player2, 4);
        clawFlip.flip(true);
        vm.stopPrank();

        assertEq(clawFlip.getRound(roundId).leader, player2);
        assertEq(clawFlip.getRound(roundId).highestStreak, 4);
    }

    // ═══════════════════════════════════════════════════════════
    //                      END GAME TESTS
    // ═══════════════════════════════════════════════════════════

    function test_EndGame_Voluntary() public {
        uint256 roundId = clawFlip.getCurrentRoundId();

        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        vm.startPrank(player1);
        clawFlip.flip(true);
        clawFlip.flip(true);

        vm.expectEmit(true, true, true, true);
        emit GameEnded(player1, 2, roundId);
        clawFlip.endGame();
        vm.stopPrank();

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertFalse(session.active);
        assertEq(session.streak, 2);

        // Best streak recorded
        assertEq(clawFlip.playerBestStreak(roundId, player1), 2);
    }

    function test_EndGame_NoActiveGame() public {
        vm.prank(player1);
        vm.expectRevert(ClawFlip.NoActiveGame.selector);
        clawFlip.endGame();
    }

    function test_TimeoutGame() public {
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        // Try to timeout before duration
        vm.expectRevert(ClawFlip.NotTimedOut.selector);
        clawFlip.timeoutGame(player1);

        // Warp past timeout duration
        vm.warp(block.timestamp + clawFlip.MAX_GAME_DURATION() + 1);

        // Now timeout should work
        clawFlip.timeoutGame(player1);

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertFalse(session.active);
    }

    // ═══════════════════════════════════════════════════════════
    //                    ROUND SETTLEMENT TESTS
    // ═══════════════════════════════════════════════════════════

    function test_SettleRound() public {
        uint256 roundId = clawFlip.getCurrentRoundId();

        // Player 1 plays
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        vm.startPrank(player1);
        clawFlip.flip(true);
        clawFlip.flip(true);
        clawFlip.flip(true);
        clawFlip.endGame();
        vm.stopPrank();

        // Player 2 plays
        vm.prank(player2);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(2, type(uint256).max);

        vm.startPrank(player2);
        clawFlip.flip(true);
        clawFlip.flip(true);
        clawFlip.endGame();
        vm.stopPrank();

        // Can't settle before round ends
        vm.expectRevert(ClawFlip.RoundNotEnded.selector);
        clawFlip.settleRound(roundId);

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        // Get prize pool before settlement
        uint256 prizePool = clawFlip.getRound(roundId).prizePool;
        uint256 winnerPrize = (prizePool * 70) / 100;
        uint256 rollover = prizePool - winnerPrize;

        // Settle round
        uint256 player1BalanceBefore = clawToken.balanceOf(player1);

        vm.expectEmit(true, true, true, true);
        emit RoundSettled(roundId, player1, 3, winnerPrize);
        clawFlip.settleRound(roundId);

        // Check winner received prize
        assertEq(clawToken.balanceOf(player1), player1BalanceBefore + winnerPrize);

        // Check round is settled
        assertTrue(clawFlip.getRound(roundId).settled);

        // Check rollover to current round
        assertEq(clawFlip.getCurrentRound().prizePool, rollover);
    }

    function test_SettleRound_AlreadySettled() public {
        uint256 roundId = clawFlip.getCurrentRoundId();

        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        vm.prank(player1);
        clawFlip.endGame();

        vm.warp(block.timestamp + 1 days);
        clawFlip.settleRound(roundId);

        vm.expectRevert(ClawFlip.RoundAlreadySettled.selector);
        clawFlip.settleRound(roundId);
    }

    // ═══════════════════════════════════════════════════════════
    //                      VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_CanFlip() public {
        assertFalse(clawFlip.canFlip(player1));

        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        // Still can't flip - waiting for VRF
        assertFalse(clawFlip.canFlip(player1));

        vrfCoordinator.fulfillRandomWords(1, 12345);

        // Now can flip
        assertTrue(clawFlip.canFlip(player1));
    }

    function test_RemainingFlips() public {
        assertEq(clawFlip.remainingFlips(player1), 0);

        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);
        vrfCoordinator.fulfillRandomWords(1, type(uint256).max);

        assertEq(clawFlip.remainingFlips(player1), 256);

        vm.prank(player1);
        clawFlip.flip(true);

        assertEq(clawFlip.remainingFlips(player1), 255);
    }

    function test_GetCurrentRound() public view {
        IClawFlip.DailyRound memory round = clawFlip.getCurrentRound();
        assertEq(round.prizePool, 0);
        assertEq(round.participantCount, 0);
        assertFalse(round.settled);
    }

    // ═══════════════════════════════════════════════════════════
    //                       ADMIN TESTS
    // ═══════════════════════════════════════════════════════════

    function test_SetMinEntry() public {
        uint256 newMinEntry = 50 * 10 ** 18;
        clawFlip.setMinEntry(newMinEntry);
        assertEq(clawFlip.minEntry(), newMinEntry);
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        clawFlip.setTreasury(newTreasury);
        assertEq(clawFlip.treasury(), newTreasury);
    }

    function test_Pause() public {
        clawFlip.pause();

        vm.prank(player1);
        vm.expectRevert();
        clawFlip.enterGame(100 * 10 ** 18);

        clawFlip.unpause();

        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18); // Should work
    }

    function test_EmergencyWithdraw() public {
        // Send some tokens to the contract
        clawToken.transfer(address(clawFlip), 1000 * 10 ** 18);

        uint256 ownerBalanceBefore = clawToken.balanceOf(owner);
        clawFlip.emergencyWithdraw(address(clawToken), 500 * 10 ** 18);

        assertEq(clawToken.balanceOf(owner), ownerBalanceBefore + 500 * 10 ** 18);
    }

    function test_AdminFunctions_OnlyOwner() public {
        vm.startPrank(player1);

        vm.expectRevert();
        clawFlip.setMinEntry(100);

        vm.expectRevert();
        clawFlip.setTreasury(player1);

        vm.expectRevert();
        clawFlip.pause();

        vm.expectRevert();
        clawFlip.emergencyWithdraw(address(clawToken), 100);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //                       FUZZ TESTS
    // ═══════════════════════════════════════════════════════════

    function testFuzz_EntryFee(uint256 entryFee) public {
        entryFee = bound(entryFee, MIN_ENTRY, 1000 * 10 ** 18);

        vm.prank(player1);
        clawFlip.enterGame(entryFee);

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertEq(session.entryFee, entryFee);

        uint256 expectedPrize = (entryFee * 90) / 100;
        assertEq(clawFlip.getCurrentRound().prizePool, expectedPrize);
    }

    function testFuzz_RandomSeed(uint256 seed) public {
        vm.prank(player1);
        clawFlip.enterGame(100 * 10 ** 18);

        vrfCoordinator.fulfillRandomWords(1, seed);

        IClawFlip.GameSession memory session = clawFlip.getSession(player1);
        assertEq(session.randomSeed, seed);
    }
}
