# 🦞 Lobster Arcade - Smart Contracts

Smart contracts for the Lobster Arcade gaming platform on Base L2.

## Games

### 🎰 Claw Flip ETH v2 (RECOMMENDED)
A coinflip streak game where the longest daily streak wins the prize pool.

**How it works:**
1. Pay entry fee in ETH
   - 88% → Prize Pool
   - 5% → Buyback Accumulator (for $ZER0_AI buyback & burn)
   - 5% → Treasury (operations)
   - 2% → Referrer (or buyback if no referrer)
2. Request Chainlink VRF randomness (wait for callback)
3. Call HEADS or TAILS repeatedly until you lose
4. Longest daily streak wins 70% of the prize pool
5. 30% rolls over to the next day (100% if no winner)

## Contracts

| Contract | Description | Status |
|----------|-------------|--------|
| `ClawFlipETHv2.sol` | **Main ETH coinflip game with security fixes** | ✅ Recommended |
| `ClawFlipETH.sol` | Legacy ETH game (insecure RNG) | ⚠️ Deprecated |
| `ClawFlipSimple.sol` | Simple version for reference | 🧪 Testing only |
| `ClawToken.sol` | $CLAW ERC20 token | ✅ Production |

## v2 Security Fixes

ClawFlipETHv2 includes critical security improvements over v1:

| Fix | Issue | Solution |
|-----|-------|----------|
| **#1 Chainlink VRF** | Predictable RNG using blockhash | Chainlink VRF V2.5 for provably fair randomness |
| **#2 Pull Pattern** | Settlement DoS if winner reverts | Failed transfers store in `unclaimedPrizes`, winners call `claimPrize()` |
| **#3 No-Winner Rollover** | Only 30% rolled over when no winner | 100% rollover when `leader == address(0)` |
| **#4 Referral Accounting** | Earnings updated before transfer | Only update `referralEarnings` AFTER successful transfer |
| **#5 Emergency Safeguards** | Could drain active prize pools | 3-day timelock + excludes active prize pools |
| **#6 Max Flips Auto-End** | Player stuck at 256 flips | Auto-end game when `flipIndex` reaches 256 |
| **#7 Zero Address Checks** | Missing validation | `require(_treasury != address(0))` in constructor and setters |

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Chainlink VRF subscription (create at [vrf.chain.link](https://vrf.chain.link))

### Install Dependencies

```bash
cd contracts

# Install Foundry dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.0.1 --no-commit
forge install smartcontractkit/chainlink@v2.9.0 --no-commit
forge install foundry-rs/forge-std --no-commit

# Build
forge build
```

### Environment Setup

Create a `.env` file:

```env
# Private key (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# RPC URLs
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASE_MAINNET_RPC_URL=https://mainnet.base.org

# Chainlink VRF Subscription ID (create at vrf.chain.link)
VRF_SUBSCRIPTION_ID=1234

# Optional overrides
TREASURY_ADDRESS=0x...  # defaults to deployer
MIN_ENTRY=1000000000000000  # 0.001 ETH in wei

# For verification
BASESCAN_API_KEY=your_api_key_here
```

## Testing

```bash
# Run all tests
forge test

# Run v2 tests with verbosity
forge test --match-contract ClawFlipETHv2Test -vvv

# Run specific test
forge test --match-test test_PullPattern -vvv

# Gas report
forge test --gas-report

# Coverage
forge coverage
```

### Test Coverage

The v2 test suite covers:
- ✅ VRF integration (seed not exposed, multiple players, waiting for seed)
- ✅ Pull pattern (failed transfers, claimPrize)
- ✅ No-winner 100% rollover
- ✅ Referral accounting (after-transfer updates)
- ✅ Emergency withdraw (timelock, prize pool exclusion)
- ✅ Max flips auto-end at 256
- ✅ Zero address validation
- ✅ Settlement edge cases
- ✅ Timeout functionality
- ✅ Fee distribution

## Deployment

### Base Sepolia (Testnet)

```bash
# Load environment
source .env

# Deploy v2 contract
forge script script/DeployETHv2.s.sol:DeployETHv2Script \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Local Development (Anvil)

```bash
# Start anvil
anvil

# Deploy with mock VRF
forge script script/DeployETHv2.s.sol:DeployETHv2LocalScript \
  --rpc-url http://localhost:8545 \
  --broadcast
```

### Base Mainnet

```bash
forge script script/DeployETHv2.s.sol:DeployETHv2Script \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify
```

### Post-Deployment

**IMPORTANT:** After deploying, add the contract as a VRF consumer:

1. Go to [vrf.chain.link](https://vrf.chain.link)
2. Connect wallet
3. Select your subscription
4. Click "Add Consumer"
5. Enter the ClawFlipETHv2 contract address
6. Fund the subscription with LINK

## VRF Configuration

### Base Sepolia
| Parameter | Value |
|-----------|-------|
| VRF Coordinator | `0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE` |
| Key Hash (500 gwei) | `0x9e9e46732b32662b9adc6f3abdf6c5e926a666d174a4d6b8e39c4cca76a38897` |

### Base Mainnet
| Parameter | Value |
|-----------|-------|
| VRF Coordinator | `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634` |
| Key Hash (500 gwei) | `0xdc2f87677b01473c763cb0aee938ed3b6a23c9f5a54a0d6d3a1e6fb5f3b1e3f9` |

## Game Flow (v2)

```
┌─────────┐     enterGame()      ┌─────────┐
│  IDLE   │ ─────────────────▶   │ WAITING │  (VRF requested)
└─────────┘                      └─────────┘
                                      │
                            fulfillRandomWords()
                                      ▼
                                ┌─────────┐
                                │ PLAYING │ ◀─────┐
                                └─────────┘       │ (win, flipIndex < 256)
                                      │          │
                                flip(HEADS/TAILS)
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              ┌─────────┐      ┌───────────┐     ┌──────────┐
              │  LOSE   │      │ CONTINUE  │     │ MAX FLIPS│
              └─────────┘      └───────────┘     │  (256)   │
                    │                            └──────────┘
                    │                                  │
                    └──────────────┬───────────────────┘
                                   ▼
                            Record Streak
                            Update Leaderboard
                            Clear Seed
```

## Security

### Audit Status
- [x] Internal review (v2 fixes)
- [ ] External audit

### Key Security Features (v2)
- **Chainlink VRF v2.5** for provably fair randomness
- **Pull pattern** for DoS-resistant prize distribution
- **Timelocked emergency withdraw** protects player funds
- **ReentrancyGuard** on all external functions
- **Zero address validation** throughout
- **1-hour timeout** to prevent game griefing
- **Random seed never exposed** via any getter

## License

MIT
