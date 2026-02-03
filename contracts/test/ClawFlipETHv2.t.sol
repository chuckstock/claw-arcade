// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ClawFlipETHv2.sol";
import "../src/mocks/MockVRFCoordinatorV2_5.sol";

/**
 * @title ClawFlipETHv2Test
 * @notice Comprehensive tests for ClawFlipETH v2 covering all security fixes
 */
contract ClawFlipETHv2Test is Test {
    ClawFlipETHv2 public game;
    MockVRFCoordinatorV2_5 public vrfCoordinator;
    
    address public treasury = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public referrer = address(0xDEF);
    address public owner = address(0x0123);
    
    uint256 public constant MIN_ENTRY = 0.01 ether;
    uint256 public constant VRF_SUB_ID = 1;
    bytes32 public constant VRF_KEY_HASH = bytes32(uint256(1));
    
    // Known seed that produces predictable flip results for testing
    // Binary: all 1s = all heads
    uint256 public constant ALL_HEADS_SEED = type(uint256).max;
    // Binary: all 0s = all tails
    uint256 public constant ALL_TAILS_SEED = 0;
    // Alternating pattern
    uint256 public constant ALTERNATING_SEED = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;

    function setUp() public {
        // Deploy mock VRF coordinator
        vrfCoordinator = new MockVRFCoordinatorV2_5();
        
        // Deploy game as owner
        vm.prank(owner);
        game = new ClawFlipETHv2(
            treasury,
            MIN_ENTRY,
            address(vrfCoordinator),
            VRF_SUB_ID,
            VRF_KEY_HASH
        );
        
        // Fund players and owner
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(referrer, 1 ether);
        vm.deal(owner, 1 ether);
    }
    
    // Allow test contract to receive ETH
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════
    //                    BASIC GAME TESTS
    // ═══════════════════════════════════════════════════════════

    function test_EnterGame() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        (
            address player,
            uint256 entryFee,
            uint256 streak,
            uint256 flipIndex,
            ,
            ,
            address ref,
            bool active,
            bool seedReady
        ) = game.getSession(alice);
        
        assertEq(player, alice);
        assertEq(entryFee, MIN_ENTRY);
        assertEq(streak, 0);
        assertEq(flipIndex, 0);
        assertTrue(active);
        assertFalse(seedReady); // Seed not ready until VRF callback
        assertEq(ref, address(0));
    }

    function test_EnterGameWithReferrer() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        (,,,,,, address ref,,) = game.getSession(alice);
        assertEq(ref, referrer);
        assertEq(game.referredBy(alice), referrer);
    }

    function test_RevertFlipBeforeSeedReady() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Try to flip before VRF callback
        vm.prank(alice);
        vm.expectRevert(ClawFlipETHv2.SeedNotReady.selector);
        game.flip(true);
    }

    function test_FlipAfterVRFCallback() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Fulfill VRF with known seed (all heads)
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        // Now flip should work
        assertTrue(game.isSeedReady(alice));
        
        vm.prank(alice);
        game.flip(true); // Heads - should win with all-heads seed
        
        (,, uint256 streak,,,,,bool active,) = game.getSession(alice);
        assertEq(streak, 1);
        assertTrue(active);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FIX #1: VRF TESTS
    // ═══════════════════════════════════════════════════════════

    function test_VRF_SeedNotExposed() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        uint256 secretSeed = 12345;
        vrfCoordinator.fulfillRandomWords(requestId, secretSeed);
        
        // Session getter should NOT expose the random seed
        // The struct returned has no randomSeed field
        (
            address player,
            uint256 entryFee,
            uint256 streak,
            uint256 flipIndex,
            uint64 startTime,
            uint256 roundId,
            address ref,
            bool active,
            bool seedReady
        ) = game.getSession(alice);
        
        // Verify we got real data but no seed
        assertEq(player, alice);
        assertTrue(seedReady);
        // There's no way to access the seed - it's private
    }

    function test_VRF_CannotFlipWithoutSeed() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Don't fulfill VRF - seed not ready
        assertFalse(game.isSeedReady(alice));
        
        vm.prank(alice);
        vm.expectRevert(ClawFlipETHv2.SeedNotReady.selector);
        game.flip(true);
    }

    function test_VRF_MultiplePlayersIndependentSeeds() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        uint256 aliceRequestId = vrfCoordinator.lastRequestId();
        
        vm.prank(bob);
        game.enterGame{value: MIN_ENTRY}(address(0));
        uint256 bobRequestId = vrfCoordinator.lastRequestId();
        
        // Different request IDs
        assertNotEq(aliceRequestId, bobRequestId);
        
        // Fulfill with different seeds
        vrfCoordinator.fulfillRandomWords(aliceRequestId, ALL_HEADS_SEED);
        vrfCoordinator.fulfillRandomWords(bobRequestId, ALL_TAILS_SEED);
        
        // Alice wins with heads
        vm.prank(alice);
        game.flip(true);
        (,, uint256 aliceStreak,,,,,bool aliceActive,) = game.getSession(alice);
        assertEq(aliceStreak, 1);
        assertTrue(aliceActive);
        
        // Bob loses with heads (seed is all tails)
        vm.prank(bob);
        game.flip(true);
        (,, uint256 bobStreak,,,,,bool bobActive,) = game.getSession(bob);
        assertEq(bobStreak, 0);
        assertFalse(bobActive);
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #2: PULL PATTERN TESTS
    // ═══════════════════════════════════════════════════════════

    function test_PullPattern_NormalPaymentWorks() public {
        // Setup: alice wins a round
        _setupWinningGame(alice);
        
        // Warp to next day and settle
        vm.warp(block.timestamp + 1 days);
        uint256 roundId = game.getCurrentRoundId() - 1;
        
        uint256 aliceBalanceBefore = alice.balance;
        game.settleRound(roundId);
        
        // Alice should receive prize directly
        assertTrue(alice.balance > aliceBalanceBefore);
        assertEq(game.unclaimedPrizes(alice), 0);
    }

    function test_PullPattern_FailedTransferStoresPrize() public {
        // Deploy a contract that rejects ETH
        RejectingWinner rejecter = new RejectingWinner(game, vrfCoordinator);
        vm.deal(address(rejecter), 1 ether);
        
        // Rejecter enters and wins
        rejecter.enterAndPlay();
        
        // Warp to next day and settle
        vm.warp(block.timestamp + 1 days);
        uint256 roundId = game.getCurrentRoundId() - 1;
        
        ClawFlipETHv2.DailyRound memory round = game.getRound(roundId);
        uint256 expectedPrize = (round.prizePool * 7000) / 10000;
        
        // Settlement should NOT revert even though winner rejects ETH
        game.settleRound(roundId);
        
        // Prize should be stored for claiming
        assertEq(game.unclaimedPrizes(address(rejecter)), expectedPrize);
    }

    function test_PullPattern_ClaimPrize() public {
        // Deploy a contract that rejects ETH initially
        RejectingWinner rejecter = new RejectingWinner(game, vrfCoordinator);
        vm.deal(address(rejecter), 1 ether);
        
        rejecter.enterAndPlay();
        
        vm.warp(block.timestamp + 1 days);
        uint256 roundId = game.getCurrentRoundId() - 1;
        
        game.settleRound(roundId);
        
        uint256 prizeAmount = game.unclaimedPrizes(address(rejecter));
        assertTrue(prizeAmount > 0);
        
        // Now rejecter accepts ETH and claims
        rejecter.setAcceptETH(true);
        uint256 balanceBefore = address(rejecter).balance;
        
        rejecter.claimPrize();
        
        assertEq(address(rejecter).balance - balanceBefore, prizeAmount);
        assertEq(game.unclaimedPrizes(address(rejecter)), 0);
    }

    function test_PullPattern_CannotClaimZero() public {
        vm.prank(alice);
        vm.expectRevert(ClawFlipETHv2.NoPrizeToClaim.selector);
        game.claimPrize();
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #3: NO-WINNER ROLLOVER TESTS
    // ═══════════════════════════════════════════════════════════

    function test_NoWinnerRollover_100Percent() public {
        // Alice enters but immediately loses
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_TAILS_SEED);
        
        // Flip heads to lose immediately (seed is all tails)
        vm.prank(alice);
        game.flip(true);
        
        // No one has a winning streak - leader should be address(0)
        uint256 roundId = game.getCurrentRoundId();
        ClawFlipETHv2.DailyRound memory round = game.getRound(roundId);
        assertEq(round.leader, address(0));
        
        uint256 prizePoolBefore = round.prizePool;
        
        // Warp to next day
        vm.warp(block.timestamp + 1 days);
        uint256 newRoundId = game.getCurrentRoundId();
        
        // Settle the old round
        game.settleRound(roundId);
        
        // 100% should rollover (not 70% to winner + 30% rollover)
        ClawFlipETHv2.DailyRound memory newRound = game.getRound(newRoundId);
        assertEq(newRound.prizePool, prizePoolBefore);
    }

    function test_NoWinnerRollover_EmitsEvent() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_TAILS_SEED);
        
        vm.prank(alice);
        game.flip(true); // Lose immediately
        
        uint256 roundId = game.getCurrentRoundId();
        uint256 prizePool = game.getRound(roundId).prizePool;
        
        vm.warp(block.timestamp + 1 days);
        
        vm.expectEmit(true, false, false, true);
        emit ClawFlipETHv2.NoWinnerRollover(roundId, prizePool);
        
        game.settleRound(roundId);
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #4: REFERRAL ACCOUNTING TESTS
    // ═══════════════════════════════════════════════════════════

    function test_ReferralEarnings_UpdatedAfterTransfer() public {
        uint256 referrerBalanceBefore = referrer.balance;
        uint256 referrerEarningsBefore = game.referralEarnings(referrer);
        
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        uint256 expectedReferral = (MIN_ENTRY * 200) / 10000; // 2%
        
        // Earnings should only be tracked after successful transfer
        assertEq(referrer.balance - referrerBalanceBefore, expectedReferral);
        assertEq(game.referralEarnings(referrer) - referrerEarningsBefore, expectedReferral);
    }

    function test_ReferralEarnings_NotUpdatedOnFailedTransfer() public {
        // Deploy a rejecting referrer
        RejectingReferrer rejectingRef = new RejectingReferrer();
        
        uint256 earningsBefore = game.referralEarnings(address(rejectingRef));
        uint256 buybackBefore = game.buybackAccumulator();
        
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(rejectingRef));
        
        // Referral earnings should NOT be updated
        assertEq(game.referralEarnings(address(rejectingRef)), earningsBefore);
        
        // Referrer's 2% should go to buyback instead
        uint256 expectedReferral = (MIN_ENTRY * 200) / 10000;
        uint256 expectedBuyback = (MIN_ENTRY * 700) / 10000; // 5% + 2%
        assertEq(game.buybackAccumulator() - buybackBefore, expectedBuyback);
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #5: EMERGENCY WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════

    function test_EmergencyWithdraw_RequiresTimelock() public {
        // Fund contract
        vm.deal(address(game), 1 ether);
        
        vm.startPrank(owner);
        
        // Request emergency withdraw
        game.requestEmergencyWithdraw();
        
        // Try to execute immediately - should fail
        vm.expectRevert(ClawFlipETHv2.TimelockNotExpired.selector);
        game.executeEmergencyWithdraw();
        
        vm.stopPrank();
    }

    function test_EmergencyWithdraw_WorksAfterTimelock() public {
        // Fund contract with some extra ETH (simulating accumulated fees)
        vm.deal(address(game), 1 ether);
        
        vm.startPrank(owner);
        
        game.requestEmergencyWithdraw();
        
        // Warp past timelock
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 ownerBalanceBefore = owner.balance;
        game.executeEmergencyWithdraw();
        
        // Owner should have received funds
        assertTrue(owner.balance > ownerBalanceBefore);
        
        vm.stopPrank();
    }

    function test_EmergencyWithdraw_ExcludesActivePrizePools() public {
        // Alice enters game - creates prize pool
        vm.prank(alice);
        game.enterGame{value: 1 ether}(address(0));
        
        uint256 activePools = game.getActivePrizePools();
        assertTrue(activePools > 0);
        
        // Add extra ETH
        vm.deal(address(game), address(game).balance + 0.5 ether);
        
        vm.startPrank(owner);
        game.requestEmergencyWithdraw();
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 ownerBalanceBefore = owner.balance;
        uint256 totalBefore = address(game).balance;
        
        game.executeEmergencyWithdraw();
        
        // Should have withdrawn something but not the prize pool
        uint256 withdrawn = owner.balance - ownerBalanceBefore;
        assertTrue(withdrawn > 0);
        
        // Prize pool should still be in contract
        assertTrue(address(game).balance >= activePools);
        
        vm.stopPrank();
    }

    function test_EmergencyWithdraw_CanBeCancelled() public {
        vm.startPrank(owner);
        
        game.requestEmergencyWithdraw();
        assertTrue(game.emergencyWithdrawRequested());
        
        game.cancelEmergencyWithdraw();
        assertFalse(game.emergencyWithdrawRequested());
        
        // Cannot execute after cancel
        vm.warp(block.timestamp + 3 days + 1);
        vm.expectRevert(ClawFlipETHv2.NoEmergencyRequested.selector);
        game.executeEmergencyWithdraw();
        
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #6: MAX FLIPS AUTO-END TESTS
    // ═══════════════════════════════════════════════════════════

    function test_MaxFlips_AutoEndsGame() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        vm.startPrank(alice);
        
        // Flip 256 times (all winning with all-heads seed and calling heads)
        for (uint256 i = 0; i < 256; i++) {
            (,,,,,,,bool active1,) = game.getSession(alice);
            if (!active1) break;
            game.flip(true);
        }
        
        // Game should be auto-ended
        (,, uint256 streak,,,,,bool active2,) = game.getSession(alice);
        assertFalse(active2);
        assertEq(streak, 256);
        
        vm.stopPrank();
    }

    function test_MaxFlips_CannotExceed256() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        vm.startPrank(alice);
        
        // Max out flips
        for (uint256 i = 0; i < 256; i++) {
            game.flip(true);
        }
        
        // Trying to flip again should fail (game is ended)
        vm.expectRevert(ClawFlipETHv2.NoActiveGame.selector);
        game.flip(true);
        
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //              FIX #7: ZERO ADDRESS TESTS
    // ═══════════════════════════════════════════════════════════

    function test_Constructor_RevertZeroTreasury() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new ClawFlipETHv2(
            address(0),  // Zero treasury
            MIN_ENTRY,
            address(vrfCoordinator),
            VRF_SUB_ID,
            VRF_KEY_HASH
        );
    }

    function test_Constructor_RevertZeroVRFCoordinator() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new ClawFlipETHv2(
            treasury,
            MIN_ENTRY,
            address(0),  // Zero VRF coordinator
            VRF_SUB_ID,
            VRF_KEY_HASH
        );
    }

    function test_SetTreasury_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        game.setTreasury(address(0));
    }

    function test_SetTreasury_Works() public {
        address newTreasury = address(0x1234);
        
        vm.prank(owner);
        game.setTreasury(newTreasury);
        
        assertEq(game.treasury(), newTreasury);
    }

    // ═══════════════════════════════════════════════════════════
    //                    SETTLEMENT TESTS
    // ═══════════════════════════════════════════════════════════

    function test_Settlement_WinnerGets70Percent() public {
        _setupWinningGame(alice);
        
        uint256 roundId = game.getCurrentRoundId();
        ClawFlipETHv2.DailyRound memory round = game.getRound(roundId);
        uint256 expectedPrize = (round.prizePool * 7000) / 10000;
        
        vm.warp(block.timestamp + 1 days);
        uint256 aliceBalanceBefore = alice.balance;
        
        game.settleRound(roundId);
        
        assertEq(alice.balance - aliceBalanceBefore, expectedPrize);
    }

    function test_Settlement_30PercentRollsOver() public {
        _setupWinningGame(alice);
        
        uint256 roundId = game.getCurrentRoundId();
        ClawFlipETHv2.DailyRound memory round = game.getRound(roundId);
        uint256 expectedRollover = round.prizePool - (round.prizePool * 7000) / 10000;
        
        vm.warp(block.timestamp + 1 days);
        uint256 newRoundId = game.getCurrentRoundId();
        
        game.settleRound(roundId);
        
        ClawFlipETHv2.DailyRound memory newRound = game.getRound(newRoundId);
        assertEq(newRound.prizePool, expectedRollover);
    }

    function test_Settlement_CannotSettleCurrentRound() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 roundId = game.getCurrentRoundId();
        
        vm.expectRevert(ClawFlipETHv2.RoundNotEnded.selector);
        game.settleRound(roundId);
    }

    function test_Settlement_CannotDoubleSettle() public {
        _setupWinningGame(alice);
        
        uint256 roundId = game.getCurrentRoundId();
        vm.warp(block.timestamp + 1 days);
        
        game.settleRound(roundId);
        
        vm.expectRevert(ClawFlipETHv2.AlreadySettled.selector);
        game.settleRound(roundId);
    }

    // ═══════════════════════════════════════════════════════════
    //                    TIMEOUT TESTS
    // ═══════════════════════════════════════════════════════════

    function test_Timeout_CanTimeoutInactiveGame() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Warp past max game duration
        vm.warp(block.timestamp + 1 hours + 1);
        
        game.timeoutGame(alice);
        
        (,,,,,,,bool active,) = game.getSession(alice);
        assertFalse(active);
    }

    function test_Timeout_CannotTimeoutTooEarly() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Try to timeout before duration
        vm.warp(block.timestamp + 30 minutes);
        
        vm.expectRevert(ClawFlipETHv2.NotTimedOut.selector);
        game.timeoutGame(alice);
    }

    function test_Timeout_PreservesStreak() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        // Win a few flips
        vm.startPrank(alice);
        game.flip(true);
        game.flip(true);
        game.flip(true);
        vm.stopPrank();
        
        // Timeout
        vm.warp(block.timestamp + 1 hours + 1);
        game.timeoutGame(alice);
        
        (,, uint256 streak,,,,,,) = game.getSession(alice);
        assertEq(streak, 3);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FEE DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_FeeDistribution() public {
        uint256 treasuryBefore = treasury.balance;
        uint256 referrerBefore = referrer.balance;
        
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        // Check treasury received 5%
        uint256 expectedTreasury = (MIN_ENTRY * 500) / 10000;
        assertEq(treasury.balance - treasuryBefore, expectedTreasury);
        
        // Check referrer received 2%
        uint256 expectedReferrer = (MIN_ENTRY * 200) / 10000;
        assertEq(referrer.balance - referrerBefore, expectedReferrer);
        
        // Check buyback accumulator has 5%
        uint256 expectedBuyback = (MIN_ENTRY * 500) / 10000;
        assertEq(game.buybackAccumulator(), expectedBuyback);
        
        // Check prize pool has 88%
        uint256 expectedPrize = (MIN_ENTRY * 8800) / 10000;
        ClawFlipETHv2.DailyRound memory round = game.getCurrentRound();
        assertEq(round.prizePool, expectedPrize);
    }

    function test_FeeDistribution_NoReferrer() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Without referrer, the 2% goes to buyback (5% + 2% = 7%)
        uint256 expectedBuyback = (MIN_ENTRY * 700) / 10000;
        assertEq(game.buybackAccumulator(), expectedBuyback);
    }

    // ═══════════════════════════════════════════════════════════
    //                    EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════

    function test_RevertOnDoubleEntry() public {
        vm.startPrank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        vm.expectRevert(ClawFlipETHv2.AlreadyInGame.selector);
        game.enterGame{value: MIN_ENTRY}(address(0));
        vm.stopPrank();
    }

    function test_RevertOnInsufficientEntry() public {
        vm.prank(alice);
        vm.expectRevert(ClawFlipETHv2.EntryTooLow.selector);
        game.enterGame{value: MIN_ENTRY - 1}(address(0));
    }

    function test_RevertSelfReferral() public {
        vm.prank(alice);
        vm.expectRevert(ClawFlipETHv2.CannotReferSelf.selector);
        game.enterGame{value: MIN_ENTRY}(alice);
    }

    function test_ReferralPersists() public {
        // First game with referrer
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_TAILS_SEED);
        
        vm.prank(alice);
        game.flip(true); // Lose
        
        // Second game without specifying referrer
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Referrer should still be set
        (,,,,,, address ref,,) = game.getSession(alice);
        assertEq(ref, referrer);
    }

    function test_MultiplePlayersCompete() public {
        // Alice enters
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        vrfCoordinator.fulfillRandomWords(vrfCoordinator.lastRequestId(), ALL_HEADS_SEED);
        
        // Alice wins 3
        vm.startPrank(alice);
        game.flip(true);
        game.flip(true);
        game.flip(true);
        game.cashOut();
        vm.stopPrank();
        
        // Bob enters
        vm.prank(bob);
        game.enterGame{value: MIN_ENTRY}(address(0));
        vrfCoordinator.fulfillRandomWords(vrfCoordinator.lastRequestId(), ALL_HEADS_SEED);
        
        // Bob wins 5 - becomes leader
        vm.startPrank(bob);
        for (uint i = 0; i < 5; i++) {
            game.flip(true);
        }
        game.cashOut();
        vm.stopPrank();
        
        // Check bob is leader
        uint256 roundId = game.getCurrentRoundId();
        ClawFlipETHv2.DailyRound memory round = game.getRound(roundId);
        assertEq(round.leader, bob);
        assertEq(round.highestStreak, 5);
    }

    function test_CashOut() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        vm.startPrank(alice);
        game.flip(true);
        game.flip(true);
        game.cashOut();
        
        (,, uint256 streak,,,,,bool active,) = game.getSession(alice);
        assertFalse(active);
        assertEq(streak, 2);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //                    FUZZ TESTS
    // ═══════════════════════════════════════════════════════════

    function testFuzz_EntryAmount(uint256 amount) public {
        vm.assume(amount >= MIN_ENTRY && amount <= 1 ether);
        
        vm.deal(alice, amount);
        vm.prank(alice);
        game.enterGame{value: amount}(address(0));
        
        (,uint256 entryFee,,,,,,,) = game.getSession(alice);
        assertEq(entryFee, amount);
    }

    function testFuzz_RandomSeed(uint256 seed) public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, seed);
        
        assertTrue(game.isSeedReady(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //                    HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    function _setupWinningGame(address player) internal {
        vm.deal(player, 1 ether);
        vm.prank(player);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, ALL_HEADS_SEED);
        
        // Win at least one flip to become leader
        vm.startPrank(player);
        game.flip(true);
        game.cashOut();
        vm.stopPrank();
    }
}

// ═══════════════════════════════════════════════════════════
//                    HELPER CONTRACTS
// ═══════════════════════════════════════════════════════════

/**
 * @notice Contract that rejects ETH - used to test pull pattern
 */
contract RejectingWinner {
    ClawFlipETHv2 public game;
    MockVRFCoordinatorV2_5 public vrfCoordinator;
    bool public acceptETH;
    
    constructor(ClawFlipETHv2 _game, MockVRFCoordinatorV2_5 _vrf) {
        game = _game;
        vrfCoordinator = _vrf;
        acceptETH = false;
    }
    
    function setAcceptETH(bool _accept) external {
        acceptETH = _accept;
    }
    
    function enterAndPlay() external {
        game.enterGame{value: 0.01 ether}(address(0));
        
        uint256 requestId = vrfCoordinator.lastRequestId();
        vrfCoordinator.fulfillRandomWords(requestId, type(uint256).max);
        
        // Win one flip
        game.flip(true);
        game.cashOut();
    }
    
    function claimPrize() external {
        game.claimPrize();
    }
    
    receive() external payable {
        require(acceptETH, "No ETH");
    }
}

/**
 * @notice Contract that always rejects ETH - used to test referral accounting
 */
contract RejectingReferrer {
    receive() external payable {
        revert("No ETH");
    }
}
