# 🦞 Lobster Arcade - Smart Contracts

Smart contracts for the Lobster Arcade gaming platform on Base L2.

## Games

### 🎰 Claw Flip
A coinflip streak game where the longest daily streak wins the prize pool.

**How it works:**
1. Pay entry fee in $CLAW (90% → prize pool, 10% → treasury)
2. Receive VRF randomness (256 bits = 256 potential flips)
3. Call HEADS or TAILS repeatedly until you lose
4. Longest daily streak wins 70% of the prize pool
5. 30% rolls over to the next day

## Contracts

| Contract | Description |
|----------|-------------|
| `ClawToken.sol` | $CLAW ERC20 token with mint/burn |
| `ClawFlip.sol` | Main coinflip game with Chainlink VRF |

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for scripts)

### Install Dependencies

```bash
# Clone and enter directory
cd arcade/contracts

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

# Treasury address (receives 10% of entry fees)
TREASURY_ADDRESS=0x...

# For verification
BASESCAN_API_KEY=your_api_key_here
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Flip_Win -vvv

# Gas report
forge test --gas-report

# Coverage
forge coverage
```

## Deployment

### Base Sepolia (Testnet)

```bash
# Load environment
source .env

# Dry run (simulation)
forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC_URL

# Deploy and verify
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Base Mainnet

```bash
# Set mainnet flag
export MAINNET=true

# Deploy
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify
```

### Post-Deployment

**Important:** After deploying, you must add the ClawFlip contract as a consumer to your Chainlink VRF subscription:

1. Go to [vrf.chain.link](https://vrf.chain.link)
2. Connect wallet
3. Select your subscription
4. Click "Add Consumer"
5. Enter the ClawFlip contract address
6. Fund the subscription with LINK or ETH

## Contract Addresses

### Base Sepolia

| Contract | Address |
|----------|---------|
| ClawToken | `TBD` |
| ClawFlip | `TBD` |

### Base Mainnet

| Contract | Address |
|----------|---------|
| ClawToken | `TBD` |
| ClawFlip | `TBD` |

## Architecture

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

## Game State Machine

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

## Security

### Audit Status
- [ ] Internal review
- [ ] External audit

### Key Security Features
- **Chainlink VRF v2.5** for provably fair randomness
- **ReentrancyGuard** on all external functions
- **Pausable** for emergency stops
- **SafeERC20** for token transfers
- **1-hour timeout** to prevent game griefing

## License

MIT
