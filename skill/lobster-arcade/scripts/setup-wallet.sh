#!/bin/bash
# Setup a new wallet for Lobster Arcade
# Usage: setup-wallet.sh

set -e

echo "🦞 Lobster Arcade Wallet Setup"
echo "=============================="
echo ""

# Check if cast is available
if ! command -v cast &> /dev/null; then
    echo "❌ 'cast' command not found"
    echo ""
    echo "Install Foundry first:"
    echo "  curl -L https://foundry.paradigm.xyz | bash"
    echo "  foundryup"
    exit 1
fi

# Check if wallet already exists
if [ -n "$WALLET_PRIVATE_KEY" ]; then
    ADDR=$(cast wallet address --private-key "$WALLET_PRIVATE_KEY" 2>/dev/null || echo "invalid")
    if [ "$ADDR" != "invalid" ]; then
        echo "✅ Wallet already configured!"
        echo "Address: $ADDR"
        echo ""
        echo "Checking balance..."
        BAL=$(cast balance "$ADDR" --rpc-url https://sepolia.base.org --ether 2>/dev/null || echo "0")
        echo "Balance: $BAL ETH (Base Sepolia)"
        exit 0
    fi
fi

# Create new wallet
echo "Creating new wallet..."
echo ""

WALLET_OUTPUT=$(cast wallet new)
echo "$WALLET_OUTPUT"

# Extract address and key
ADDRESS=$(echo "$WALLET_OUTPUT" | grep "Address:" | awk '{print $2}')
PRIVATE_KEY=$(echo "$WALLET_OUTPUT" | grep "Private key:" | awk '{print $3}')

echo ""
echo "=============================="
echo "🔐 SAVE THIS INFORMATION!"
echo "=============================="
echo ""
echo "Address:     $ADDRESS"
echo "Private Key: $PRIVATE_KEY"
echo ""
echo "To use this wallet, run:"
echo ""
echo "  export WALLET_PRIVATE_KEY=\"$PRIVATE_KEY\""
echo ""
echo "Or add to your shell profile:"
echo ""
echo "  echo 'export WALLET_PRIVATE_KEY=\"$PRIVATE_KEY\"' >> ~/.bashrc"
echo "  source ~/.bashrc"
echo ""
echo "=============================="
echo "📋 NEXT: Get testnet ETH"
echo "=============================="
echo ""
echo "Your wallet needs Base Sepolia ETH to play."
echo ""
echo "Send ETH to: $ADDRESS"
echo ""
echo "Faucets:"
echo "  • https://app.optimism.io/faucet (Superchain)"
echo "  • https://bwarelabs.com/faucets/base-sepolia"
echo "  • https://www.alchemy.com/faucets/base-sepolia"
echo ""
echo "After funding, check balance:"
echo "  cast balance $ADDRESS --rpc-url https://sepolia.base.org --ether"
echo ""
echo "Then play:"
echo "  claw-flip.sh enter"
echo "  claw-flip.sh flip heads"
echo ""
