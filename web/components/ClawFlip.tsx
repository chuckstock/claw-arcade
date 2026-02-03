'use client';

import { useState, useEffect } from 'react';
import { useAccount, useBalance, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatEther, parseEther } from 'viem';
import { CONTRACTS, CLAW_FLIP_ETH_ABI } from '@/lib/contracts';

type GameSession = {
  player: string;
  entryFee: bigint;
  streak: bigint;
  randomSeed: bigint;
  flipIndex: bigint;
  startTime: bigint;
  roundId: bigint;
  referrer: string;
  active: boolean;
};

type RoundInfo = {
  prizePool: bigint;
  highestStreak: bigint;
  leader: string;
  participantCount: bigint;
  settled: boolean;
};

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export function ClawFlip() {
  const { address, isConnected } = useAccount();
  const [wagerAmount, setWagerAmount] = useState('0.001');
  const [referrer, setReferrer] = useState('');
  const [isFlipping, setIsFlipping] = useState(false);
  const [lastResult, setLastResult] = useState<{ won: boolean; choice: string } | null>(null);

  // Read ETH balance
  const { data: ethBalance, refetch: refetchBalance } = useBalance({
    address: address,
  });

  // Read game session
  const { data: session, refetch: refetchSession } = useReadContract({
    address: CONTRACTS.clawFlipETH,
    abi: CLAW_FLIP_ETH_ABI,
    functionName: 'getSession',
    args: address ? [address] : undefined,
  }) as { data: GameSession | undefined; refetch: () => void };

  // Read current round
  const { data: currentRound, refetch: refetchRound } = useReadContract({
    address: CONTRACTS.clawFlipETH,
    abi: CLAW_FLIP_ETH_ABI,
    functionName: 'getCurrentRound',
  }) as { data: RoundInfo | undefined; refetch: () => void };

  // Read buyback stats
  const { data: buybackBalance } = useReadContract({
    address: CONTRACTS.clawFlipETH,
    abi: CLAW_FLIP_ETH_ABI,
    functionName: 'buybackAccumulator',
  });

  // Write contracts
  const { writeContract: enterGame, data: enterHash } = useWriteContract();
  const { writeContract: flip, data: flipHash } = useWriteContract();
  const { writeContract: cashOut, data: cashOutHash } = useWriteContract();

  // Wait for transactions
  const { isLoading: isEntering } = useWaitForTransactionReceipt({ hash: enterHash });
  const { isLoading: isFlippingTx } = useWaitForTransactionReceipt({ hash: flipHash });
  const { isLoading: isCashingOut } = useWaitForTransactionReceipt({ hash: cashOutHash });

  // Refetch on transaction completion
  useEffect(() => {
    if (enterHash || flipHash || cashOutHash) {
      const timer = setTimeout(() => {
        refetchBalance();
        refetchSession();
        refetchRound();
        setIsFlipping(false);
      }, 2000);
      return () => clearTimeout(timer);
    }
  }, [enterHash, flipHash, cashOutHash]);

  const handleEnterGame = () => {
    const ref = referrer && referrer.startsWith('0x') ? referrer as `0x${string}` : ZERO_ADDRESS;
    enterGame({
      address: CONTRACTS.clawFlipETH,
      abi: CLAW_FLIP_ETH_ABI,
      functionName: 'enterGame',
      args: [ref],
      value: parseEther(wagerAmount),
    });
  };

  const handleFlip = (heads: boolean) => {
    setIsFlipping(true);
    setLastResult({ won: false, choice: heads ? 'HEADS' : 'TAILS' });
    flip({
      address: CONTRACTS.clawFlipETH,
      abi: CLAW_FLIP_ETH_ABI,
      functionName: 'flip',
      args: [heads],
    });
  };

  const handleCashOut = () => {
    cashOut({
      address: CONTRACTS.clawFlipETH,
      abi: CLAW_FLIP_ETH_ABI,
      functionName: 'cashOut',
    });
  };

  const isInGame = session?.active;
  const isLoading = isEntering || isFlippingTx || isCashingOut;

  if (!isConnected) {
    return (
      <div className="text-center py-12">
        <div className="text-6xl mb-4">🦞</div>
        <h2 className="text-2xl font-bold text-lobster-dark mb-2">Connect Your Wallet</h2>
        <p className="text-lobster-blue">Connect to play Claw Flip on Base Sepolia</p>
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto">
      {/* Balance Display */}
      <div className="bg-white rounded-xl p-6 shadow-lg mb-6">
        <div className="flex justify-between items-center">
          <span className="text-lobster-blue">Your ETH Balance</span>
          <span className="text-2xl font-bold text-lobster-dark">
            {ethBalance ? Number(formatEther(ethBalance.value)).toFixed(4) : '0'} ETH
          </span>
        </div>
      </div>

      {/* Game Area */}
      <div className="bg-white rounded-xl p-8 shadow-lg mb-6">
        {!isInGame ? (
          /* Entry Screen */
          <div className="text-center">
            <h2 className="text-3xl font-bold text-lobster-dark mb-6">🪙 Claw Flip</h2>
            <p className="text-lobster-blue mb-6">
              Call it right, extend your streak. Daily winner takes the pot!
            </p>
            
            <div className="mb-4">
              <label className="block text-sm text-lobster-blue mb-2">Wager Amount (ETH)</label>
              <input
                type="number"
                value={wagerAmount}
                onChange={(e) => setWagerAmount(e.target.value)}
                className="w-full px-4 py-3 rounded-lg border-2 border-lobster-light focus:border-lobster-red outline-none text-center text-2xl font-bold"
                min="0.001"
                step="0.001"
              />
            </div>

            <div className="mb-6">
              <label className="block text-sm text-lobster-blue mb-2">Referrer (optional)</label>
              <input
                type="text"
                value={referrer}
                onChange={(e) => setReferrer(e.target.value)}
                placeholder="0x..."
                className="w-full px-4 py-2 rounded-lg border-2 border-lobster-light focus:border-lobster-blue outline-none text-sm font-mono"
              />
            </div>

            <button
              onClick={handleEnterGame}
              disabled={isLoading}
              className="w-full py-4 bg-lobster-red text-white rounded-xl font-bold text-lg hover:bg-red-700 transition disabled:opacity-50"
            >
              {isEntering ? 'Entering...' : '🦞 Enter Game'}
            </button>
            
            <p className="text-xs text-lobster-blue mt-4">
              Fee split: 88% prize pool • 5% buyback • 5% treasury • 2% referrer
            </p>
          </div>
        ) : (
          /* In Game */
          <div className="text-center">
            <div className="mb-4">
              <span className="text-sm text-lobster-blue">Current Streak</span>
              <div className="text-5xl font-bold text-lobster-red">
                {session.streak.toString()} 🔥
              </div>
            </div>

            {/* Coin Animation */}
            <div className="coin mx-auto mb-6">
              <div className={`coin-inner ${isFlipping || isFlippingTx ? 'flipping' : ''}`}>
                <div className="coin-face coin-heads">🦞</div>
                <div className="coin-face coin-tails">🌊</div>
              </div>
            </div>

            {lastResult && !isFlippingTx && (
              <div className={`mb-4 text-lg font-bold ${lastResult.won ? 'text-green-500' : 'text-lobster-red'}`}>
                Called {lastResult.choice}
              </div>
            )}

            <div className="grid grid-cols-2 gap-4 mb-6">
              <button
                onClick={() => handleFlip(true)}
                disabled={isLoading}
                className="py-4 bg-lobster-red text-white rounded-xl font-bold text-lg hover:bg-red-700 transition disabled:opacity-50"
              >
                {isFlippingTx ? '...' : '🦞 HEADS'}
              </button>
              <button
                onClick={() => handleFlip(false)}
                disabled={isLoading}
                className="py-4 bg-lobster-blue text-white rounded-xl font-bold text-lg hover:bg-lobster-dark transition disabled:opacity-50"
              >
                {isFlippingTx ? '...' : '🌊 TAILS'}
              </button>
            </div>

            <button
              onClick={handleCashOut}
              disabled={isLoading || session.streak === BigInt(0)}
              className="w-full py-3 bg-green-500 text-white rounded-xl font-bold hover:bg-green-600 transition disabled:opacity-50"
            >
              {isCashingOut ? 'Cashing Out...' : '💰 Cash Out'}
            </button>
          </div>
        )}
      </div>

      {/* Round Info */}
      {currentRound && (
        <div className="bg-white rounded-xl p-6 shadow-lg mb-6">
          <h3 className="text-lg font-bold text-lobster-dark mb-4">📊 Today's Round</h3>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span className="text-lobster-blue">Prize Pool</span>
              <div className="font-bold">{Number(formatEther(currentRound.prizePool)).toFixed(4)} ETH</div>
            </div>
            <div>
              <span className="text-lobster-blue">Players</span>
              <div className="font-bold">{currentRound.participantCount.toString()}</div>
            </div>
            <div>
              <span className="text-lobster-blue">Top Streak</span>
              <div className="font-bold">{currentRound.highestStreak.toString()} 🔥</div>
            </div>
            <div>
              <span className="text-lobster-blue">Leader</span>
              <div className="font-bold font-mono text-xs">
                {currentRound.leader === ZERO_ADDRESS
                  ? 'None yet' 
                  : `${currentRound.leader.slice(0, 6)}...${currentRound.leader.slice(-4)}`}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Buyback Stats */}
      {buybackBalance !== undefined && (
        <div className="bg-gradient-to-r from-lobster-dark to-lobster-blue rounded-xl p-6 shadow-lg text-white">
          <h3 className="text-lg font-bold mb-2">🔥 $ZER0_AI Buyback Fund</h3>
          <div className="text-2xl font-bold">
            {Number(formatEther(buybackBalance as bigint)).toFixed(4)} ETH
          </div>
          <p className="text-xs opacity-75 mt-2">
            Accumulated for weekly buyback & burn
          </p>
        </div>
      )}
    </div>
  );
}
