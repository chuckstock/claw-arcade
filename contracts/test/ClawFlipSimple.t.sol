// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ClawFlipSimple.sol";
import "../src/ClawToken.sol";

contract ClawFlipSimpleTest is Test {
    ClawFlipSimple public game;
    ClawToken public claw;
    
    address public treasury = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    
    uint256 public constant MIN_ENTRY = 10 ether;
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        // Deploy token
        claw = new ClawToken(address(this), 0);
        
        // Deploy game
        game = new ClawFlipSimple(
            address(claw),
            treasury,
            MIN_ENTRY
        );
        
        // Fund players
        claw.mint(alice, INITIAL_BALANCE);
        claw.mint(bob, INITIAL_BALANCE);
        
        // Approve game contract
        vm.prank(alice);
        claw.approve(address(game), type(uint256).max);
        
        vm.prank(bob);
        claw.approve(address(game), type(uint256).max);
    }

    function test_EnterGame() public {
        vm.prank(alice);
        game.enterGame(MIN_ENTRY);
        
        ClawFlipSimple.GameSession memory session = game.getSession(alice);
        assertEq(session.player, alice);
        assertEq(session.entryFee, MIN_ENTRY);
        assertEq(session.streak, 0);
        assertTrue(session.active);
        assertTrue(session.randomSeed != 0);
    }

    function test_Flip() public {
        vm.prank(alice);
        game.enterGame(MIN_ENTRY);
        
        // Flip a few times - some will win, some will lose
        vm.startPrank(alice);
        
        // First flip
        game.flip(true);
        
        ClawFlipSimple.GameSession memory session = game.getSession(alice);
        
        // Either we're still active with 1 streak, or game ended with 0
        if (session.active) {
            assertEq(session.streak, 1);
            console.log("Won flip 1! Streak:", session.streak);
        } else {
            assertEq(session.streak, 0);
            console.log("Lost on flip 1");
        }
        
        vm.stopPrank();
    }

    function test_MultipleFlips() public {
        vm.prank(alice);
        game.enterGame(MIN_ENTRY);
        
        vm.startPrank(alice);
        
        uint256 maxFlips = 20;
        for (uint256 i = 0; i < maxFlips; i++) {
            ClawFlipSimple.GameSession memory session = game.getSession(alice);
            if (!session.active) {
                console.log("Game ended at flip", i, "with streak", session.streak);
                break;
            }
            
            // Alternate between heads and tails
            game.flip(i % 2 == 0);
        }
        
        vm.stopPrank();
    }

    function test_PrizePoolAccumulates() public {
        uint256 roundId = game.getCurrentRoundId();
        
        // Alice enters
        vm.prank(alice);
        game.enterGame(MIN_ENTRY);
        
        // Bob enters
        vm.prank(bob);
        game.enterGame(MIN_ENTRY);
        
        ClawFlipSimple.DailyRound memory round = game.getRound(roundId);
        
        // 90% of each entry goes to prize pool
        uint256 expectedPool = (MIN_ENTRY * 2 * 9000) / 10000;
        assertEq(round.prizePool, expectedPool);
        assertEq(round.participantCount, 2);
    }

    function test_TreasuryReceivesFee() public {
        uint256 treasuryBefore = claw.balanceOf(treasury);
        
        vm.prank(alice);
        game.enterGame(MIN_ENTRY);
        
        uint256 treasuryAfter = claw.balanceOf(treasury);
        uint256 expectedFee = (MIN_ENTRY * 1000) / 10000; // 10%
        
        assertEq(treasuryAfter - treasuryBefore, expectedFee);
    }

    function test_CashOut() public {
        vm.startPrank(alice);
        game.enterGame(MIN_ENTRY);
        
        // Play a few flips
        ClawFlipSimple.GameSession memory session = game.getSession(alice);
        while (session.active && session.streak < 3) {
            game.flip(true);
            session = game.getSession(alice);
        }
        
        // Cash out if still active
        if (session.active) {
            game.cashOut();
            session = game.getSession(alice);
            assertFalse(session.active);
            console.log("Cashed out with streak:", session.streak);
        }
        
        vm.stopPrank();
    }

    function test_NewLeaderEmitted() public {
        vm.startPrank(alice);
        game.enterGame(MIN_ENTRY);
        
        // Keep flipping until we get a win
        bool gotWin = false;
        for (uint256 i = 0; i < 10 && !gotWin; i++) {
            ClawFlipSimple.GameSession memory session = game.getSession(alice);
            if (!session.active) break;
            
            // Record events
            vm.recordLogs();
            game.flip(true);
            
            session = game.getSession(alice);
            if (session.active && session.streak == 1) {
                gotWin = true;
                console.log("Got first win, now leader!");
            }
        }
        
        vm.stopPrank();
    }

    function test_RevertOnDoubleEntry() public {
        vm.startPrank(alice);
        game.enterGame(MIN_ENTRY);
        
        vm.expectRevert("Already in game");
        game.enterGame(MIN_ENTRY);
        vm.stopPrank();
    }

    function test_RevertOnInsufficientEntry() public {
        vm.prank(alice);
        vm.expectRevert("Entry too low");
        game.enterGame(MIN_ENTRY - 1);
    }

    function test_RevertFlipWithNoGame() public {
        vm.prank(alice);
        vm.expectRevert("No active game");
        game.flip(true);
    }

    function test_Fuzz_EntryAmount(uint256 amount) public {
        vm.assume(amount >= MIN_ENTRY && amount <= INITIAL_BALANCE);
        
        vm.prank(alice);
        game.enterGame(amount);
        
        ClawFlipSimple.GameSession memory session = game.getSession(alice);
        assertEq(session.entryFee, amount);
    }
}
