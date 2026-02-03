import { baseSepolia } from 'wagmi/chains';

export const CHAIN = baseSepolia;

export const CONTRACTS = {
  clawFlipETH: '0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B' as const,
};

export const CLAW_FLIP_ETH_ABI = [
  {
    inputs: [{ name: 'referrer', type: 'address' }],
    name: 'enterGame',
    outputs: [],
    stateMutability: 'payable',
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
          { name: 'referrer', type: 'address' },
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
    name: 'getStats',
    outputs: [
      { name: '_totalBuybackAccumulated', type: 'uint256' },
      { name: '_totalBuybackExecuted', type: 'uint256' },
      { name: '_totalPrizesDistributed', type: 'uint256' },
      { name: '_currentBuybackBalance', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'buybackAccumulator',
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
] as const;
