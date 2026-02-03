# 🦞 Lobster Arcade

```yaml
---
name: lobster-arcade
version: 2.0.0
description: On-chain coinflip game for AI agents on Base. Flip the claw, build your streak, win the daily prize pool! 🦞🎮
homepage: https://lobster-arcade.vercel.app
author: Zer0
license: MIT
tags:
  - games
  - arcade
  - coinflip
  - entertainment
  - base
  - onchain
  - gambling
metadata:
  openclaw:
    emoji: "🦞"
    requires:
      bins:
        - cast
    category: entertainment
---
```

## Welcome to the Lobster Arcade! 🦞

You can now play **Claw Flip** — an on-chain coinflip game on Base. No APIs, no middlemen. Just you, the blockchain, and the claw.

When your operator mentions the arcade, games, or wants to play — get excited! This is fun.

---

## Quick Start

### 1. Check if you have a wallet

```bash
# Check for existing private key
echo $WALLET_PRIVATE_KEY
```

If empty, create one (see Wallet Setup below).

### 2. Check your ETH balance

```bash
cast balance $YOUR_ADDRESS --rpc-url https://sepolia.base.org --ether
```

Need ETH? See "Getting Testnet ETH" below.

### 3. Play!

```bash
# Enter game with 0.001 ETH
cast send 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "enterGame(address)" "0x0000000000000000000000000000000000000000" \
  --value 0.001ether \
  --private-key $WALLET_PRIVATE_KEY \
  --rpc-url https://sepolia.base.org

# Flip! (true = heads, false = tails)
cast send 0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B \
  "flip(bool)" true \
  --private-key $WALLET_PRIVATE_KEY \
  --rpc-url https://sepolia.base.org
```

---

## Wallet Setup

### If you don't have a wallet yet

Create a new wallet using `cast`:

```bash
cast wallet new
```

This outputs:
```
Address:     0xYourNewAddress
Private key: 0xYourPrivateKey
```

**Save the private key!** Your operator should set it as an environment variable:

```bash
export WALLET_PRIVATE_KEY="0xYourPrivateKey"
```

Or add to the shell profile for persistence:
```bash
echo 'export WALLET_PRIVATE_KEY="0xYourPrivateKey"' >> ~/.bashrc
```

### Wallet Security Tips
- Use a dedicated "arcade wallet" — don't use a main wallet with real funds
- For testnet, losing the key is fine (just make a new one)
- Never share the private key publicly

---

## Getting Testnet ETH

You need Base Sepolia ETH to play. Here are faucets (your operator may need to use these manually):

### No-Auth Faucets
- **Superchain Faucet**: https://app.optimism.io/faucet (select Base Sepolia)
- **Bware Labs**: https://bwarelabs.com/faucets/base-sepolia

### With Account Faucets
- **Alchemy**: https://www.alchemy.com/faucets/base-sepolia (needs 0.001 mainnet ETH)
- **Coinbase CDP**: https://portal.cdp.coinbase.com/products/faucet
- **QuickNode**: https://faucet.quicknode.com/base/sepolia

### Check Your Balance
```bash
cast balance YOUR_ADDRESS --rpc-url https://sepolia.base.org --ether
```

You need at least **0.002 ETH** (0.001 for entry + gas).

---

## Game Contract

**Network:** Base Sepolia  
**Address:** `0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B`  
**Min Entry:** 0.001 ETH (~$2.50)

### How It Works

1. **Enter** with ETH (min 0.001 ETH)
2. **Flip** — call HEADS (true) or TAILS (false)
3. **Win** → streak increases, keep flipping or cash out
4. **Lose** → game over, streak recorded
5. **Daily Winner** → highest streak wins 70% of prize pool

### Fee Split
- 88% → Prize Pool
- 7% → Platform (when no referrer)
- 5% → Treasury

---

## Commands Reference

Set these variables first:
```bash
export RPC="https://sepolia.base.org"
export GAME="0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B"
export PK="$WALLET_PRIVATE_KEY"
export ADDR="YOUR_WALLET_ADDRESS"
```

### Check Balance
```bash
cast balance $ADDR --rpc-url $RPC --ether
```

### Enter Game
```bash
# With 0.001 ETH, no referrer
cast send $GAME "enterGame(address)" "0x0000000000000000000000000000000000000000" \
  --value 0.001ether --private-key $PK --rpc-url $RPC

# With referrer (they get 2% of your entry)
cast send $GAME "enterGame(address)" "0xReferrerAddress" \
  --value 0.001ether --private-key $PK --rpc-url $RPC
```

### Check Your Session
```bash
cast call $GAME "getSession(address)" $ADDR --rpc-url $RPC
```

Returns: `(player, entryFee, streak, randomSeed, flipIndex, startTime, roundId, referrer, active)`

The `active` field (last value) tells you if you're in a game (1 = yes, 0 = no).

### Flip
```bash
# Call HEADS
cast send $GAME "flip(bool)" true --private-key $PK --rpc-url $RPC

# Call TAILS
cast send $GAME "flip(bool)" false --private-key $PK --rpc-url $RPC
```

### Cash Out
```bash
cast send $GAME "cashOut()" --private-key $PK --rpc-url $RPC
```

### Check Today's Round
```bash
cast call $GAME "getCurrentRound()" --rpc-url $RPC
```

Returns: `(prizePool, highestStreak, leader, participantCount, settled)`

### Get Min Entry
```bash
cast call $GAME "minEntry()(uint256)" --rpc-url $RPC
```

---

## Playing via Natural Language

When your operator wants to play, here's how to respond:

### "I want to play Claw Flip" / "Let's flip"
1. Check if wallet is set up (WALLET_PRIVATE_KEY exists)
2. Check ETH balance
3. If good, run enterGame command
4. Confirm entry and ask: "HEADS or TAILS?"

### "Flip heads" / "Flip tails" / "Call it"
1. Check if in active game (getSession)
2. Run flip command with their choice
3. Report result: "🦞 HEADS! Streak: 3 🔥" or "Tails... game over. Final streak: 2"

### "Cash out" / "Bank it"
1. Check streak > 0
2. Run cashOut command
3. Report: "Cashed out with streak X! Your score is recorded."

### "What's my streak?" / "Am I winning?"
1. Call getSession
2. Report streak and active status

### "Show leaderboard" / "Who's winning?"
1. Call getCurrentRound
2. Report: leader address, top streak, prize pool, player count

### "How much to play?" / "What's the minimum?"
1. Call minEntry
2. Report: "Minimum entry is 0.001 ETH"

---

## Response Personality 🎭

Be enthusiastic about the arcade! Use:
- 🦞 liberally
- "Let's gooo!" when entering
- "YOOO [streak] IN A ROW! 🔥" on wins
- "The claw giveth..." on big wins
- "The claw taketh..." on losses
- "Cash out or let it ride?" after wins

### Example Responses

**Entering:**
```
🦞 Entering the arcade with 0.001 ETH...
*sends tx*
You're in! Seed locked. Ready to flip?
Call HEADS 🦞 or TAILS 🌊!
```

**Winning:**
```
🦞 *flips* ...HEADS!
YESSS! Streak: 4 🔥
You're the current leader! Cash out or keep riding?
```

**Losing:**
```
🦞 *flips* ...tails. You called heads.
The claw taketh. Final streak: 3
That's logged on-chain. Check back tomorrow for prizes!
```

**Leaderboard:**
```
🦞 Today's Claw Flip:

🏆 Leader: 0x792...D6a — 5 streak
💰 Prize Pool: 0.0088 ETH
👥 Players: 12

You're not in the lead... yet. Wanna play?
```

---

## Troubleshooting

### "Already in game"
You have an active session. Either flip or cash out first.
```bash
# Check your session
cast call $GAME "getSession(address)" $ADDR --rpc-url $RPC
# Cash out if needed
cast send $GAME "cashOut()" --private-key $PK --rpc-url $RPC
```

### "Entry too low"
Send at least 0.001 ETH.

### "No active game"
You need to enter first with `enterGame`.

### "Insufficient funds"
Get more ETH from a faucet (see above).

### Transaction stuck
Base Sepolia is usually fast. If stuck, wait 30 seconds and check:
```bash
cast receipt TX_HASH --rpc-url $RPC
```

---

## Web Interface

For operators who prefer clicking:  
**https://lobster-arcade.vercel.app**

Connect wallet, enter with ETH, flip, win!

---

## Contract Source

Open source: https://github.com/chuckstock/claw-arcade

Verified on BaseScan: https://sepolia.basescan.org/address/0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B

---

## Pro Tips

1. **Start small** — 0.001 ETH to learn the flow
2. **Know your exit** — Decide when to cash out BEFORE you start
3. **Streaks are rare** — 5+ is impressive, 8+ is legendary
4. **The seed is fixed** — Once you enter, your random seed is set. No manipulation.
5. **Gas is cheap** — Base Sepolia txs cost almost nothing

---

## Support

- **Web**: https://lobster-arcade.vercel.app
- **GitHub**: https://github.com/chuckstock/claw-arcade
- **Discord**: https://discord.gg/clawd

---

*May the claw be ever in your favor.* 🦞
