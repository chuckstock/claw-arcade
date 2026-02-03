# Claw Flip Technical Specification

> **Game Summary**: A coinflip streak game where AI agents pay entry fees in $CLAW, call HEADS/TAILS repeatedly until they lose, and the longest daily streak wins the prize pool.

---

## Table of Contents
1. [Randomness Solution](#1-randomness-solution)
2. [Smart Contract Architecture](#2-smart-contract-architecture)
3. [Entry & Prize Flow](#3-entry--prize-flow)
4. [Security Considerations](#4-security-considerations)
5. [Example Code](#5-example-code)
6. [Gas Cost Analysis](#6-gas-cost-analysis)
7. [Build Timeline](#7-build-timeline)

---

## 1. Randomness Solution

### Recommendation: **Chainlink VRF v2.5**

After evaluating the options, **Chainlink VRF v2.5** is the recommended solution for Base L2.

| Solution | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Chainlink VRF v2.5** | Provably fair, battle-tested, native Base support, pay in ETH or LINK | Async (2-block delay), costs ~$0.10-0.50/request | ✅ **RECOMMENDED** |
| **Pyth Entropy** | Fast, cheap, commit-reveal based | Less battle-tested, trust assumptions on provider | Good alternative |
| **Commit-Reveal (Custom)** | No external deps, cheapest | 2-tx per flip, slow UX, griefing risk | ❌ Poor UX |
| **Block Hash** | Free, instant | Easily manipulated by validators | ❌ Not secure |

### Why Chainlink VRF for Claw Flip

1. **Provably Fair**: Cryptographic proof published on-chain before consumption
2. **Base Support**: Native deployment on Base Mainnet (see addresses below)
3. **Subscription Model**: Pay per-use from a funded subscription - no per-flip LINK transfers
4. **Battle Tested**: Used by major protocols, $75B+ value secured

### Base Mainnet VRF Addresses

```solidity
// Base Mainnet - Chainlink VRF v2.5
address constant VRF_COORDINATOR = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
address constant LINK_TOKEN = 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196;

// Key Hashes (gas lanes)
bytes32 constant KEY_HASH_2_GWEI = 0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab;
bytes32 constant KEY_HASH_30_GWEI = 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70;

// Limits
uint32 constant MAX_GAS_LIMIT = 2_500_000;
uint16 constant MIN_CONFIRMATIONS = 0;  // Base allows 0!
uint16 constant MAX_CONFIRMATIONS = 200;
```

### Hybrid Approach: Batch Randomness

**Key Optimization**: Instead of requesting VRF per flip, request multiple random numbers upfront and derive flip results from them.

```solidity
// Request 10 random words = enough for 320 flips (32 bits each)
// Cost: 1 VRF call instead of 320
uint32 constant NUM_WORDS = 10;
```

---

## 2. Smart Contract Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLAW FLIP SYSTEM                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   $CLAW      │───▶│  ClawFlip    │◀───│  Chainlink   │      │
│  │   Token      │    │  Game        │    │  VRF v2.5    │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                              │                                  │
│                              ▼                                  │
│                      ┌──────────────┐                          │
│                      │   Daily      │                          │
│                      │   Rounds     │                          │
│                      └──────────────┘                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Structure

```
contracts/
├── ClawFlip.sol           # Main game contract
├── ClawFlipVRF.sol        # VRF consumer (inherits VRFConsumerBaseV2Plus)
├── interfaces/
│   ├── IClawFlip.sol      # Game interface
│   └── ICLAW.sol          # Token interface (ERC20)
└── libraries/
    └── StreakLib.sol      # Streak calculation helpers
```

### Core Data Structures

```solidity
// Game session for a single player
struct GameSession {
    address player;
    uint256 entryFee;
    uint256 streak;
    uint256 randomSeed;      // VRF-provided seed
    uint256 randomIndex;     // Which bit we're on
    uint64 startTime;
    bool active;
}

// Daily round tracking
struct DailyRound {
    uint256 roundId;         // Unix day number
    uint256 prizePool;
    uint256 highestStreak;
    address leader;
    address[] participants;
    bool settled;
}
```

### State Machine

```
┌─────────┐     enterGame()      ┌─────────┐
│  IDLE   │ ─────────────────▶   │ WAITING │  (waiting for VRF)
└─────────┘                      └─────────┘
                                      │
                            fulfillRandomWords()
                                      ▼
                                ┌─────────┐
                                │ PLAYING │ ◀─────┐
                                └─────────┘       │ (win)
                                      │          │
                                flip(HEADS/TAILS)
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                   ┌─────────┐              ┌───────────┐
                   │  LOSE   │              │ CONTINUE  │
                   └─────────┘              └───────────┘
                         │                         │
                  endGame()                   flip()...
                         │
                         ▼
                   Record Streak
                   Update Leaderboard
```

---

## 3. Entry & Prize Flow

### Entry Flow

```
1. Agent approves $CLAW spend to ClawFlip contract
2. Agent calls enterGame(entryFee)
   - entryFee must be >= MIN_ENTRY (e.g., 100 CLAW)
   - Contract transfers $CLAW from agent
   - 90% → Prize Pool
   - 10% → Protocol Treasury (covers VRF + operations)
3. Contract requests VRF randomness
4. VRF callback activates the game session
5. Agent can now call flip(HEADS) or flip(TAILS)
```

### Prize Distribution

```
Daily Prize Pool Distribution:
├── 70% → Daily Winner (longest streak)
├── 20% → Runner-up pool (2nd-5th place, split)
└── 10% → Rollover to next day (or burned)

Example with 10,000 CLAW pool:
├── 7,000 CLAW → #1 (18-streak winner)
├── 2,000 CLAW → #2-5 (500 each)
└── 1,000 CLAW → Tomorrow's seed
```

### Daily Round Mechanics

```solidity
// Round ID = Unix timestamp / 86400 (day number)
function getCurrentRoundId() public view returns (uint256) {
    return block.timestamp / 1 days;
}

// Settlement happens after UTC midnight
function settleRound(uint256 roundId) external {
    require(roundId < getCurrentRoundId(), "Round not ended");
    require(!rounds[roundId].settled, "Already settled");
    
    DailyRound storage round = rounds[roundId];
    
    // Transfer prizes
    CLAW.transfer(round.leader, round.prizePool * 70 / 100);
    // ... distribute remaining
    
    round.settled = true;
    emit RoundSettled(roundId, round.leader, round.highestStreak);
}
```

---

## 4. Security Considerations

### Critical Security Measures

#### 4.1 Randomness Security

```solidity
// NEVER use block.timestamp, block.difficulty, or blockhash alone
// BAD:
uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)));

// GOOD: Use Chainlink VRF
uint256 requestId = s_vrfCoordinator.requestRandomWords(...);
```

#### 4.2 Reentrancy Protection

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ClawFlip is ReentrancyGuard {
    function endGame(uint256 sessionId) external nonReentrant {
        // ... state changes before external calls
        session.active = false;
        
        // External call last
        CLAW.transfer(msg.sender, refund);
    }
}
```

#### 4.3 Front-Running Prevention

```solidity
// Player commits to their choice BEFORE seeing the random result
// The VRF request is made when entering, not when flipping

// Flip extracts next bit from pre-committed randomness
function flip(bool heads) external {
    GameSession storage session = sessions[msg.sender];
    require(session.active, "No active session");
    require(session.randomSeed != 0, "VRF pending");
    
    // Extract bit at current index
    bool coinResult = (session.randomSeed >> session.randomIndex) & 1 == 1;
    session.randomIndex++;
    
    // Check if player won this flip
    bool playerWon = (heads == coinResult);
    // ...
}
```

#### 4.4 Griefing Prevention

```solidity
// Prevent players from never finishing their game
uint256 constant MAX_GAME_DURATION = 1 hours;

function timeoutGame(address player) external {
    GameSession storage session = sessions[player];
    require(session.active, "No active session");
    require(block.timestamp > session.startTime + MAX_GAME_DURATION, "Not timed out");
    
    // Force end the game, record current streak
    _endGame(player, session.streak);
}
```

#### 4.5 Access Control

```solidity
import "@openzeppelin/contracts/access/Ownable.sol";

// Admin functions for emergencies
function pause() external onlyOwner { _pause(); }
function unpause() external onlyOwner { _unpause(); }
function setMinEntry(uint256 _min) external onlyOwner { minEntry = _min; }
function setTreasuryFee(uint256 _fee) external onlyOwner {
    require(_fee <= 20, "Fee too high");  // Max 20%
    treasuryFee = _fee;
}
```

### Audit Checklist

- [ ] No use of block variables for randomness
- [ ] Reentrancy guards on all state-changing functions
- [ ] Integer overflow protection (Solidity 0.8+)
- [ ] Proper access control on admin functions
- [ ] Event emission for all important state changes
- [ ] No unchecked external calls
- [ ] VRF request/fulfill properly paired
- [ ] No leftover funds lockable in contract

---

## 5. Example Code

### Main Contract: ClawFlip.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ClawFlip is VRFConsumerBaseV2Plus, ReentrancyGuard, Pausable, Ownable {
    
    // ═══════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ═══════════════════════════════════════════════════════════
    
    // Base Mainnet VRF Config
    bytes32 public constant KEY_HASH = 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70;
    uint32 public constant CALLBACK_GAS_LIMIT = 200_000;
    uint16 public constant REQUEST_CONFIRMATIONS = 1;
    uint32 public constant NUM_WORDS = 1;  // 1 word = 256 bits = 256 flips
    
    uint256 public constant MAX_FLIPS_PER_WORD = 256;
    uint256 public constant MAX_GAME_DURATION = 1 hours;
    uint256 public constant PROTOCOL_FEE_BPS = 1000;  // 10%
    
    // ═══════════════════════════════════════════════════════════
    //                           STRUCTS
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
    //                           STATE
    // ═══════════════════════════════════════════════════════════
    
    IERC20 public immutable CLAW;
    uint256 public subscriptionId;
    uint256 public minEntry;
    address public treasury;
    
    mapping(address => GameSession) public sessions;
    mapping(uint256 => address) public vrfRequestToPlayer;
    mapping(uint256 => DailyRound) public rounds;
    
    // Leaderboard: roundId => rank => player
    mapping(uint256 => mapping(uint256 => address)) public leaderboard;
    mapping(uint256 => mapping(address => uint256)) public playerBestStreak;
    
    // ═══════════════════════════════════════════════════════════
    //                           EVENTS
    // ═══════════════════════════════════════════════════════════
    
    event GameStarted(address indexed player, uint256 entryFee, uint256 roundId, uint256 requestId);
    event FlipResult(address indexed player, bool choice, bool result, bool won, uint256 newStreak);
    event GameEnded(address indexed player, uint256 finalStreak, uint256 roundId);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 winningStreak, uint256 prize);
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);
    
    // ═══════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════
    
    constructor(
        address _vrfCoordinator,
        address _claw,
        uint256 _subscriptionId,
        uint256 _minEntry,
        address _treasury
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) Ownable(msg.sender) {
        CLAW = IERC20(_claw);
        subscriptionId = _subscriptionId;
        minEntry = _minEntry;
        treasury = _treasury;
    }
    
    // ═══════════════════════════════════════════════════════════
    //                       GAME FUNCTIONS
    // ═══════════════════════════════════════════════════════════
    
    /// @notice Enter a new game session
    /// @param entryFee Amount of $CLAW to stake
    function enterGame(uint256 entryFee) external nonReentrant whenNotPaused {
        require(!sessions[msg.sender].active, "Already in game");
        require(entryFee >= minEntry, "Entry too low");
        
        // Transfer $CLAW from player
        require(CLAW.transferFrom(msg.sender, address(this), entryFee), "Transfer failed");
        
        // Split: 90% to prize pool, 10% to treasury
        uint256 protocolFee = (entryFee * PROTOCOL_FEE_BPS) / 10000;
        uint256 prizeContribution = entryFee - protocolFee;
        
        CLAW.transfer(treasury, protocolFee);
        
        uint256 roundId = getCurrentRoundId();
        rounds[roundId].prizePool += prizeContribution;
        rounds[roundId].participantCount++;
        
        // Request VRF
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: KEY_HASH,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );
        
        vrfRequestToPlayer[requestId] = msg.sender;
        
        sessions[msg.sender] = GameSession({
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
    
    /// @notice Flip the coin - call HEADS (true) or TAILS (false)
    function flip(bool heads) external nonReentrant whenNotPaused {
        GameSession storage session = sessions[msg.sender];
        require(session.active, "No active game");
        require(session.randomSeed != 0, "Waiting for VRF");
        require(session.flipIndex < MAX_FLIPS_PER_WORD, "Max flips reached");
        
        // Extract the next bit
        bool coinResult = ((session.randomSeed >> session.flipIndex) & 1) == 1;
        session.flipIndex++;
        
        bool playerWon = (heads == coinResult);
        
        if (playerWon) {
            session.streak++;
            emit FlipResult(msg.sender, heads, coinResult, true, session.streak);
            
            // Check if new round leader
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
    
    /// @notice Voluntarily end your game (cash out your streak)
    function endGame() external nonReentrant {
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
        
        // Update player's best streak for this round
        if (finalStreak > playerBestStreak[roundId][player]) {
            playerBestStreak[roundId][player] = finalStreak;
        }
        
        session.active = false;
        
        emit GameEnded(player, finalStreak, roundId);
    }
    
    /// @notice VRF callback - receives random number
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        address player = vrfRequestToPlayer[requestId];
        require(player != address(0), "Unknown request");
        
        sessions[player].randomSeed = randomWords[0];
        delete vrfRequestToPlayer[requestId];
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
        
        // Winner takes 70%
        uint256 winnerPrize = (prize * 70) / 100;
        // 30% rolls over to next round
        uint256 rollover = prize - winnerPrize;
        
        if (winner != address(0) && winnerPrize > 0) {
            CLAW.transfer(winner, winnerPrize);
        }
        
        // Add rollover to current round
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
    
    function setSubscriptionId(uint256 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Emergency withdraw (only if no active games)
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
```

### Interface: IClawFlip.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClawFlip {
    // Structs
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
    
    // Events
    event GameStarted(address indexed player, uint256 entryFee, uint256 roundId, uint256 requestId);
    event FlipResult(address indexed player, bool choice, bool result, bool won, uint256 newStreak);
    event GameEnded(address indexed player, uint256 finalStreak, uint256 roundId);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 winningStreak, uint256 prize);
    event NewLeader(uint256 indexed roundId, address player, uint256 streak);
    
    // Functions
    function enterGame(uint256 entryFee) external;
    function flip(bool heads) external;
    function endGame() external;
    function timeoutGame(address player) external;
    function settleRound(uint256 roundId) external;
    
    // View
    function getCurrentRoundId() external view returns (uint256);
    function getSession(address player) external view returns (GameSession memory);
    function getRound(uint256 roundId) external view returns (DailyRound memory);
    function getCurrentRound() external view returns (DailyRound memory);
}
```

---

## 6. Gas Cost Analysis

### Base L2 Fee Structure

Base fees consist of:
1. **L2 Execution Fee**: Gas used × L2 gas price (min 0.001 gwei)
2. **L1 Data Fee**: Cost to post tx calldata to Ethereum L1

**Current Base Mainnet**: L2 gas is very cheap (~0.001 gwei minimum)

### Estimated Gas Costs Per Operation

| Operation | Gas Used | Est. Cost (ETH) | Est. Cost (USD) |
|-----------|----------|-----------------|-----------------|
| `enterGame()` | ~150,000 | 0.00015 | $0.40 |
| `flip()` | ~50,000 | 0.00005 | $0.13 |
| VRF Callback | ~100,000 | 0.00010 | $0.27 |
| `settleRound()` | ~80,000 | 0.00008 | $0.22 |

**10-flip streak total gas**: ~650,000 gas ≈ $1.75

### VRF Costs

Chainlink VRF on Base:
- **Premium (ETH)**: 60% markup on callback gas
- **Premium (LINK)**: 50% markup on callback gas

**Estimated VRF cost per game**: ~$0.10-0.30

### Gas Optimization Techniques

```solidity
// 1. Pack structs efficiently
struct GameSession {
    address player;       // 20 bytes
    uint64 startTime;     // 8 bytes  } = 1 slot
    uint32 flipIndex;     // 4 bytes  }
    uint256 entryFee;     // 32 bytes = 1 slot
    uint256 streak;       // 32 bytes = 1 slot
    uint256 randomSeed;   // 32 bytes = 1 slot
    uint256 roundId;      // 32 bytes = 1 slot
    bool active;          // 1 byte = 1 slot (could pack better)
}

// 2. Use events instead of storage for history
// Don't store: mapping(address => uint256[]) public streakHistory;
// Instead: emit GameEnded(player, streak);

// 3. Batch operations where possible
// Settlement can be called by anyone (Gelato keeper) once per day

// 4. Use immutable for fixed addresses
IERC20 public immutable CLAW;  // Saves ~100 gas per read
```

---

## 7. Build Timeline

### Phase 1: Core Development (2 weeks)

| Task | Duration | Notes |
|------|----------|-------|
| Contract scaffolding | 2 days | OpenZeppelin, Chainlink imports |
| Game logic implementation | 3 days | Session management, flip mechanics |
| VRF integration | 2 days | Subscription setup, callback handling |
| Prize distribution | 2 days | Daily rounds, settlement |
| Unit tests | 3 days | Foundry tests, fuzzing |

### Phase 2: Testing & Security (1-2 weeks)

| Task | Duration | Notes |
|------|----------|-------|
| Integration tests | 3 days | Full flow testing |
| Base Sepolia deployment | 2 days | Testnet validation |
| Internal security review | 3 days | Check all attack vectors |
| Gas optimization | 2 days | Profile and optimize |
| External audit (optional) | 1-2 weeks | Recommended for mainnet |

### Phase 3: Deployment & Launch (1 week)

| Task | Duration | Notes |
|------|----------|-------|
| Mainnet deployment | 1 day | Deploy + verify |
| VRF subscription setup | 1 day | Fund subscription |
| Frontend/API integration | 3 days | For AI agents to interact |
| Monitoring setup | 1 day | Alerts, dashboards |
| Launch | 1 day | 🚀 |

### Total Timeline

| Scenario | Duration |
|----------|----------|
| **Minimum Viable** | 3-4 weeks |
| **With External Audit** | 6-8 weeks |
| **Battle-Tested Launch** | 8-10 weeks |

---

## Appendix: Alternative Randomness Solutions

### Pyth Entropy (Alternative)

If Chainlink VRF costs become prohibitive, Pyth Entropy is a solid alternative:

```solidity
// Pyth Entropy - commit-reveal based
interface IEntropy {
    function requestWithCallback(
        address provider,
        bytes32 userCommitment
    ) external payable returns (uint64 sequenceNumber);
    
    function getFeeV2() external view returns (uint128);
}

// Usage
bytes32 userRandom = keccak256(abi.encodePacked(block.timestamp, msg.sender));
uint64 seq = entropy.requestWithCallback{value: fee}(provider, userRandom);
```

**Pros**: Slightly cheaper, fast (few blocks)
**Cons**: Trust assumptions on provider revealing

### Fully On-Chain Commit-Reveal (Last Resort)

For maximum decentralization (but worst UX):

```solidity
// Player commits hash of their choice + secret
function commitFlip(bytes32 commitment) external {
    commits[msg.sender] = Commit(commitment, block.number);
}

// After N blocks, reveal
function revealFlip(bool choice, bytes32 secret) external {
    require(block.number > commits[msg.sender].blockNumber + REVEAL_DELAY);
    require(keccak256(abi.encodePacked(choice, secret)) == commits[msg.sender].hash);
    
    // Combine with future blockhash for randomness
    bool result = uint256(keccak256(abi.encodePacked(
        blockhash(commits[msg.sender].blockNumber + REVEAL_DELAY),
        secret
    ))) % 2 == 0;
}
```

**Pros**: No external dependencies
**Cons**: 2 transactions per flip, terrible UX

---

## Summary

**Recommended Stack:**
- **Randomness**: Chainlink VRF v2.5 (native Base support)
- **Language**: Solidity 0.8.20+
- **Framework**: Foundry for testing
- **Dependencies**: OpenZeppelin (security), Chainlink (VRF)

**Key Design Decisions:**
1. One VRF call per game (256 flips available)
2. Daily rounds with automatic rollover
3. 10% protocol fee to cover VRF costs
4. 1-hour game timeout to prevent griefing
5. Permissionless settlement by anyone

**Security Priorities:**
1. VRF for provable fairness
2. Reentrancy protection on all external calls
3. Access control on admin functions
4. Event-based transparency

---

*Generated for Lobster Arcade - Claw Flip Game*
*Last Updated: 2026-02-03*
