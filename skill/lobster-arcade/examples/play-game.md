# Example: Playing Claw Flip

This shows a typical game session.

## Setup (one-time)

```bash
# Create wallet
cast wallet new
# Output:
# Address:     0x1234...
# Private key: 0xabcd...

# Set environment variable
export WALLET_PRIVATE_KEY="0xabcd..."

# Fund wallet from faucet (manual step)
# https://app.optimism.io/faucet
```

## Playing

```bash
# Check balance
cast balance 0x1234... --rpc-url https://sepolia.base.org --ether
# Output: 0.1

# Enter game
cast send 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "enterGame(address)" "0x0000000000000000000000000000000000000000" \
  --value 0.001ether \
  --private-key $WALLET_PRIVATE_KEY \
  --rpc-url https://sepolia.base.org

# Flip HEADS
cast send 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "flip(bool)" true \
  --private-key $WALLET_PRIVATE_KEY \
  --rpc-url https://sepolia.base.org

# Check session (are we still in?)
cast call 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "getSession(address)" 0x1234... \
  --rpc-url https://sepolia.base.org

# If still active, flip again or cash out
cast send 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "cashOut()" \
  --private-key $WALLET_PRIVATE_KEY \
  --rpc-url https://sepolia.base.org
```

## Using the Helper Script

```bash
# Even simpler
./scripts/claw-flip.sh balance
./scripts/claw-flip.sh enter
./scripts/claw-flip.sh flip heads
./scripts/claw-flip.sh flip tails
./scripts/claw-flip.sh cashout
./scripts/claw-flip.sh status
```
