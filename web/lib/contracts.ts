import { baseSepolia } from 'wagmi/chains';

export const CHAIN = baseSepolia;

export const CONTRACTS = {
  clawToken: '0x8BB8CaE058527C7e0d4E90Cc30abaC396604634a' as const,
  clawFlip: '0x6468dDde375dFeF55239c00B3049B1bb97646E65' as const,
};

export const CLAW_TOKEN_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const CLAW_FLIP_ABI = [
  {
    inputs: [{ name: 'entryFee', type: 'uint256' }],
    name: 'enterGame',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'heads', type: 'bool' }],
    name: 'flip',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'cashOut',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'player', type: 'address' }],
    name: 'getSession',
    outputs: [
      {
        components: [
          { name: 'player', type: 'address' },
          { name: 'entryFee', type: 'uint256' },
          { name: 'streak', type: 'uint256' },
          { name: 'randomSeed', type: 'uint256' },
          { name: 'flipIndex', type: 'uint256' },
          { name: 'startTime', type: 'uint64' },
          { name: 'roundId', type: 'uint256' },
          { name: 'active', type: 'bool' },
        ],
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getCurrentRound',
    outputs: [
      {
        components: [
          { name: 'prizePool', type: 'uint256' },
          { name: 'highestStreak', type: 'uint256' },
          { name: 'leader', type: 'address' },
          { name: 'participantCount', type: 'uint256' },
          { name: 'settled', type: 'bool' },
        ],
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'minEntry',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getCurrentRoundId',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'player', type: 'address' },
      { indexed: false, name: 'choice', type: 'bool' },
      { indexed: false, name: 'result', type: 'bool' },
      { indexed: false, name: 'won', type: 'bool' },
      { indexed: false, name: 'newStreak', type: 'uint256' },
    ],
    name: 'FlipResult',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'player', type: 'address' },
      { indexed: false, name: 'entryFee', type: 'uint256' },
      { indexed: false, name: 'roundId', type: 'uint256' },
    ],
    name: 'GameStarted',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'player', type: 'address' },
      { indexed: false, name: 'finalStreak', type: 'uint256' },
      { indexed: false, name: 'roundId', type: 'uint256' },
    ],
    name: 'GameEnded',
    type: 'event',
  },
] as const;
