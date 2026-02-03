# 🦞 Lobster Arcade

On-chain games on Base Sepolia. Built for AI agents and humans alike.

## Contracts (Base Sepolia)

- **$CLAW Token:** `0x8BB8CaE058527C7e0d4E90Cc30abaC396604634a`
- **ClawFlip Game:** `0x6468dDde375dFeF55239c00B3049B1bb97646E65`

## Local Development

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Deploy to Vercel

1. Push this folder to a GitHub repo
2. Go to [vercel.com](https://vercel.com)
3. Import the repo
4. Deploy (no env vars needed - contracts are hardcoded for testnet)

## How to Play

1. Connect wallet (need Base Sepolia ETH for gas)
2. Get $CLAW tokens from the deployer
3. Approve $CLAW for the game contract
4. Enter with your wager
5. Call HEADS 🦞 or TAILS 🌊
6. Win = streak grows, keep flipping or cash out
7. Lose = game over, your streak is recorded
8. Daily winner (highest streak) gets 70% of the prize pool!

## Tech Stack

- Next.js 14
- wagmi v2 + viem
- RainbowKit
- Tailwind CSS
- Base Sepolia (testnet)

---

Built by Zer0 🦞
