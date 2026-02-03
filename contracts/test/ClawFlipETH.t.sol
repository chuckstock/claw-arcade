// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ClawFlipETH.sol";

contract ClawFlipETHTest is Test {
    ClawFlipETH public game;
    
    address public treasury = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public referrer = address(0xDEF);
    address public owner = address(0x0123);
    
    uint256 public constant MIN_ENTRY = 0.01 ether;

    function setUp() public {
        // Deploy game as owner
        vm.prank(owner);
        game = new ClawFlipETH(treasury, MIN_ENTRY);
        
        // Fund players and owner
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(referrer, 1 ether);
        vm.deal(owner, 1 ether);
    }
    
    // Allow test contract to receive ETH
    receive() external payable {}

    function test_EnterGame() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        assertEq(session.player, alice);
        assertEq(session.entryFee, MIN_ENTRY);
        assertEq(session.streak, 0);
        assertTrue(session.active);
        assertEq(session.referrer, address(0));
    }

    function test_EnterGameWithReferrer() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        assertEq(session.referrer, referrer);
        assertEq(game.referredBy(alice), referrer);
    }

    function test_FeeDistribution() public {
        uint256 treasuryBefore = treasury.balance;
        uint256 referrerBefore = referrer.balance;
        
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        // Check treasury received 5%
        uint256 expectedTreasury = (MIN_ENTRY * 500) / 10000; // 5%
        assertEq(treasury.balance - treasuryBefore, expectedTreasury);
        
        // Check referrer received 2%
        uint256 expectedReferrer = (MIN_ENTRY * 200) / 10000; // 2%
        assertEq(referrer.balance - referrerBefore, expectedReferrer);
        
        // Check buyback accumulator has 5%
        uint256 expectedBuyback = (MIN_ENTRY * 500) / 10000; // 5%
        assertEq(game.buybackAccumulator(), expectedBuyback);
        
        // Check prize pool has 88%
        uint256 expectedPrize = (MIN_ENTRY * 8800) / 10000; // 88%
        ClawFlipETH.DailyRound memory round = game.getCurrentRound();
        assertEq(round.prizePool, expectedPrize);
    }

    function test_FeeDistributionNoReferrer() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Without referrer, the 2% goes to buyback (5% + 2% = 7%)
        uint256 expectedBuyback = (MIN_ENTRY * 700) / 10000; // 7%
        assertEq(game.buybackAccumulator(), expectedBuyback);
    }

    function test_Flip() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        vm.prank(alice);
        game.flip(true);
        
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        
        // Either won (streak=1, active) or lost (streak=0, inactive)
        if (session.active) {
            assertEq(session.streak, 1);
            console.log("Won flip 1! Streak:", session.streak);
        } else {
            assertEq(session.streak, 0);
            console.log("Lost on flip 1");
        }
    }

    function test_MultipleFlips() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        vm.startPrank(alice);
        
        uint256 maxFlips = 20;
        for (uint256 i = 0; i < maxFlips; i++) {
            ClawFlipETH.GameSession memory session = game.getSession(alice);
            if (!session.active) {
                console.log("Game ended at flip", i, "with streak", session.streak);
                break;
            }
            game.flip(i % 2 == 0);
        }
        
        vm.stopPrank();
    }

    function test_CashOut() public {
        vm.startPrank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        while (session.active && session.streak < 3) {
            game.flip(true);
            session = game.getSession(alice);
        }
        
        if (session.active) {
            game.cashOut();
            session = game.getSession(alice);
            assertFalse(session.active);
            console.log("Cashed out with streak:", session.streak);
        }
        
        vm.stopPrank();
    }

    function test_BuybackWithdraw() public {
        // Multiple entries to accumulate buyback funds
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // End alice's game
        vm.prank(alice);
        game.cashOut();
        
        vm.prank(bob);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        uint256 buybackBalance = game.buybackAccumulator();
        assertTrue(buybackBalance > 0);
        
        // Withdraw as owner
        uint256 ownerBefore = owner.balance;
        
        vm.prank(owner);
        game.withdrawBuybackFunds();
        
        assertEq(game.buybackAccumulator(), 0);
        assertEq(owner.balance - ownerBefore, buybackBalance);
        assertEq(game.totalBuybackExecuted(), buybackBalance);
    }

    function test_PrizePoolAccumulates() public {
        uint256 roundId = game.getCurrentRoundId();
        
        // Alice enters
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // End alice's game
        vm.prank(alice);
        game.cashOut();
        
        // Bob enters
        vm.prank(bob);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        ClawFlipETH.DailyRound memory round = game.getRound(roundId);
        
        // 88% of each entry goes to prize pool
        uint256 expectedPool = (MIN_ENTRY * 2 * 8800) / 10000;
        assertEq(round.prizePool, expectedPool);
        assertEq(round.participantCount, 2);
    }

    function test_RevertOnDoubleEntry() public {
        vm.startPrank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        vm.expectRevert("Already in game");
        game.enterGame{value: MIN_ENTRY}(address(0));
        vm.stopPrank();
    }

    function test_RevertOnInsufficientEntry() public {
        vm.prank(alice);
        vm.expectRevert("Entry too low");
        game.enterGame{value: MIN_ENTRY - 1}(address(0));
    }

    function test_RevertFlipWithNoGame() public {
        vm.prank(alice);
        vm.expectRevert("No active game");
        game.flip(true);
    }
    
    function test_RevertSelfReferral() public {
        vm.prank(alice);
        vm.expectRevert("Cannot refer yourself");
        game.enterGame{value: MIN_ENTRY}(alice);
    }

    function test_ReferralPersists() public {
        // First game with referrer
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(referrer);
        
        vm.prank(alice);
        game.cashOut();
        
        // Second game without specifying referrer
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        // Referrer should still be set
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        assertEq(session.referrer, referrer);
    }

    function test_GetStats() public {
        vm.prank(alice);
        game.enterGame{value: MIN_ENTRY}(address(0));
        
        (
            uint256 totalAccum,
            uint256 totalExec,
            uint256 totalPrizes,
            uint256 currentBalance
        ) = game.getStats();
        
        assertTrue(totalAccum > 0);
        assertEq(totalExec, 0);
        assertEq(totalPrizes, 0);
        assertEq(currentBalance, totalAccum);
    }

    function test_Fuzz_EntryAmount(uint256 amount) public {
        vm.assume(amount >= MIN_ENTRY && amount <= 1 ether);
        
        vm.deal(alice, amount);
        vm.prank(alice);
        game.enterGame{value: amount}(address(0));
        
        ClawFlipETH.GameSession memory session = game.getSession(alice);
        assertEq(session.entryFee, amount);
    }
}
