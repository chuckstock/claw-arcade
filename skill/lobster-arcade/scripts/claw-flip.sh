#!/bin/bash
# Claw Flip - Easy wrapper for the Lobster Arcade
# Usage: claw-flip.sh <command> [args]

set -e

# Config
RPC="${RPC_URL:-https://sepolia.base.org}"
GAME="0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B"
ZERO_ADDR="0x0000000000000000000000000000000000000000"

# Check for private key
if [ -z "$WALLET_PRIVATE_KEY" ]; then
    echo "❌ WALLET_PRIVATE_KEY not set"
    echo "Run: export WALLET_PRIVATE_KEY=\"0xYourKey\""
    echo "Or create a new wallet: cast wallet new"
    exit 1
fi

# Get address from private key
ADDR=$(cast wallet address --private-key "$WALLET_PRIVATE_KEY" 2>/dev/null)

case "$1" in
    balance)
        echo "🦞 Checking balance for $ADDR..."
        BAL=$(cast balance "$ADDR" --rpc-url "$RPC" --ether)
        echo "Balance: $BAL ETH"
        ;;
    
    enter)
        AMOUNT="${2:-0.001}"
        REFERRER="${3:-$ZERO_ADDR}"
        echo "🦞 Entering Claw Flip with $AMOUNT ETH..."
        cast send "$GAME" "enterGame(address)" "$REFERRER" \
            --value "${AMOUNT}ether" \
            --private-key "$WALLET_PRIVATE_KEY" \
            --rpc-url "$RPC"
        echo "✅ You're in! Call: claw-flip.sh flip heads/tails"
        ;;
    
    flip)
        CHOICE="${2:-heads}"
        if [ "$CHOICE" = "heads" ] || [ "$CHOICE" = "true" ] || [ "$CHOICE" = "1" ]; then
            BOOL="true"
            CALL="HEADS 🦞"
        else
            BOOL="false"
            CALL="TAILS 🌊"
        fi
        echo "🦞 Flipping... calling $CALL"
        cast send "$GAME" "flip(bool)" "$BOOL" \
            --private-key "$WALLET_PRIVATE_KEY" \
            --rpc-url "$RPC"
        # Check result
        sleep 2
        SESSION=$(cast call "$GAME" "getSession(address)" "$ADDR" --rpc-url "$RPC")
        # Extract active status (last field)
        ACTIVE=$(echo "$SESSION" | tail -c 2)
        if [ "$ACTIVE" = "1" ]; then
            echo "✅ WIN! You're still in. Flip again or cash out."
        else
            echo "❌ Lost! Game over."
        fi
        ;;
    
    cashout)
        echo "🦞 Cashing out..."
        cast send "$GAME" "cashOut()" \
            --private-key "$WALLET_PRIVATE_KEY" \
            --rpc-url "$RPC"
        echo "✅ Cashed out! Streak recorded."
        ;;
    
    status)
        echo "🦞 Your session:"
        SESSION=$(cast call "$GAME" "getSession(address)" "$ADDR" --rpc-url "$RPC")
        echo "$SESSION"
        echo ""
        echo "🦞 Today's round:"
        ROUND=$(cast call "$GAME" "getCurrentRound()" --rpc-url "$RPC")
        echo "$ROUND"
        ;;
    
    leaderboard)
        echo "🦞 Today's Claw Flip Leaderboard"
        echo "================================"
        ROUND=$(cast call "$GAME" "getCurrentRound()" --rpc-url "$RPC")
        # Parse round data (simplified)
        echo "$ROUND"
        ;;
    
    help|*)
        echo "🦞 Claw Flip - Lobster Arcade"
        echo ""
        echo "Commands:"
        echo "  balance              - Check your ETH balance"
        echo "  enter [amount]       - Enter game (default: 0.001 ETH)"
        echo "  flip <heads|tails>   - Make your call"
        echo "  cashout              - Cash out your streak"
        echo "  status               - Check your session & round"
        echo "  leaderboard          - View today's standings"
        echo ""
        echo "Setup:"
        echo "  export WALLET_PRIVATE_KEY=\"0xYourKey\""
        echo ""
        echo "Example:"
        echo "  claw-flip.sh enter 0.001"
        echo "  claw-flip.sh flip heads"
        echo "  claw-flip.sh flip tails"
        echo "  claw-flip.sh cashout"
        ;;
esac
