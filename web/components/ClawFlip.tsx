'use client';

import { useState, useEffect, useCallback } from 'react';
import { useAccount, useBalance, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatEther, parseEther } from 'viem';
import { CONTRACTS, CLAW_FLIP_ETH_ABI } from '@/lib/contracts';

type GameSession = {
  player: string;
  entryFee: bigint;
  streak: bigint;
  flipIndex: bigint;
  startTime: bigint;
  roundId: bigint;
  referrer: string;
  active: boolean;
  seedReady: boolean;
};

type RoundInfo = {
  prizePool: bigint;
  highestStreak: bigint;
  leader: string;
  participantCount: bigint;
  settled: boolean;
};

type TransactionStatus = 'idle' | 'pending' | 'confirming' | 'success' | 'error';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

// Confetti component for big wins
function Confetti() {
  const [particles, setParticles] = useState<Array<{ id: number; x: number; delay: number; color: string }>>([]);
  
  useEffect(() => {
    const colors = ['#DC2626', '#EF4444', '#F97316', '#FBBF24', '#4ADE80', '#22D3EE', '#A855F7'];
    const newParticles = Array.from({ length: 50 }, (_, i) => ({
      id: i,
      x: Math.random() * 100,
      delay: Math.random() * 0.5,
      color: colors[Math.floor(Math.random() * colors.length)],
    }));
    setParticles(newParticles);
    
    const timer = setTimeout(() => setParticles([]), 3000);
    return () => clearTimeout(timer);
  }, []);

  if (particles.length === 0) return null;

  return (
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-50">
      {particles.map((p) => (
        <div
          key={p.id}
          className="absolute animate-confetti"
          style={{
            left: `${p.x}%`,
            animationDelay: `${p.delay}s`,
            backgroundColor: p.color,
            width: '10px',
            height: '10px',
            borderRadius: '2px',
          }}
        />
      ))}
      <style jsx>{`
        @keyframes confetti {
          0% {
            transform: translateY(-10px) rotate(0deg);
            opacity: 1;
          }
          100% {
            transform: translateY(100vh) rotate(720deg);
            opacity: 0;
          }
        }
        .animate-confetti {
          animation: confetti 3s ease-out forwards;
        }
      `}</style>
    </div>
  );
}

// Loading spinner for VRF waiting
function VRFSpinner() {
  return (
    <div className="flex flex-col items-center justify-center py-8">
      <div className="relative">
        {/* Outer ring */}
        <div className="w-24 h-24 rounded-full border-4 border-lobster-light animate-pulse" />
        {/* Spinning ring */}
        <div className="absolute inset-0 w-24 h-24 rounded-full border-4 border-transparent border-t-lobster-red animate-spin" />
        {/* Lobster icon */}
        <div className="absolute inset-0 flex items-center justify-center text-4xl animate-bounce">
          🦞
        </div>
      </div>
      <div className="mt-4 text-center">
        <p className="text-lg font-bold text-lobster-dark">Summoning Randomness...</p>
        <p className="text-sm text-lobster-blue mt-1">Chainlink VRF is generating your seed</p>
        <div className="flex justify-center gap-1 mt-3">
          <span className="w-2 h-2 bg-lobster-red rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
          <span className="w-2 h-2 bg-lobster-red rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
          <span className="w-2 h-2 bg-lobster-red rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
        </div>
      </div>
    </div>
  );
}

// Transaction status indicator
function TxStatus({ status, message }: { status: TransactionStatus; message?: string }) {
  if (status === 'idle') return null;
  
  const config = {
    pending: { bg: 'bg-yellow-100', text: 'text-yellow-800', icon: '⏳', label: 'Waiting for signature...' },
    confirming: { bg: 'bg-blue-100', text: 'text-blue-800', icon: '⛓️', label: 'Confirming on chain...' },
    success: { bg: 'bg-green-100', text: 'text-green-800', icon: '✅', label: message || 'Transaction confirmed!' },
    error: { bg: 'bg-red-100', text: 'text-red-800', icon: '❌', label: message || 'Transaction failed' },
  }[status];

  return (
    <div className={`${config.bg} ${config.text} rounded-lg px-4 py-2 mb-4 flex items-center gap-2 text-sm font-medium animate-fade-in`}>
      <span>{config.icon}</span>
      <span>{config.label}</span>
    </div>
  );
}

export function ClawFlip() {
  const { address, isConnected } = useAccount();
  const [wagerAmount, setWagerAmount] = useState('0.001');
  const [referrer, setReferrer] = useState('');
  const [isFlipping, setIsFlipping] = useState(false);
  const [lastResult, setLastResult] = useState<{ won: boolean; choice: string } | null>(null);
  const [showConfetti, setShowConfetti] = useState(false);
  const [txStatus, setTxStatus] = useState<TransactionStatus>('idle');
  const [txMessage, setTxMessage] = useState<string>();
  const [isPollingVRF, setIsPollingVRF] = useState(false);

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

  // Read unclaimed prize
  const { data: unclaimedPrize, refetch: refetchPrize } = useReadContract({
    address: CONTRACTS.clawFlipETH,
    abi: CLAW_FLIP_ETH_ABI,
    functionName: 'getUnclaimedPrize',
    args: address ? [address] : undefined,
  }) as { data: bigint | undefined; refetch: () => void };

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
  const { writeContract: enterGame, data: enterHash, error: enterError, reset: resetEnter } = useWriteContract();
  const { writeContract: flip, data: flipHash, error: flipError, reset: resetFlip } = useWriteContract();
  const { writeContract: cashOut, data: cashOutHash, error: cashOutError, reset: resetCashOut } = useWriteContract();
  const { writeContract: claimPrize, data: claimHash, error: claimError, reset: resetClaim } = useWriteContract();

  // Wait for transactions
  const { isLoading: isEntering, isSuccess: enterSuccess } = useWaitForTransactionReceipt({ hash: enterHash });
  const { isLoading: isFlippingTx, isSuccess: flipSuccess } = useWaitForTransactionReceipt({ hash: flipHash });
  const { isLoading: isCashingOut, isSuccess: cashOutSuccess } = useWaitForTransactionReceipt({ hash: cashOutHash });
  const { isLoading: isClaiming, isSuccess: claimSuccess } = useWaitForTransactionReceipt({ hash: claimHash });

  // Poll for VRF readiness after entering game
  useEffect(() => {
    if (enterSuccess && session?.active && !session?.seedReady) {
      setIsPollingVRF(true);
      const pollInterval = setInterval(() => {
        refetchSession();
      }, 2000); // Poll every 2 seconds

      return () => clearInterval(pollInterval);
    }
  }, [enterSuccess, session?.active, session?.seedReady, refetchSession]);

  // Stop polling when seed is ready
  useEffect(() => {
    if (session?.seedReady) {
      setIsPollingVRF(false);
    }
  }, [session?.seedReady]);

  // Handle transaction status updates
  useEffect(() => {
    if (enterHash && isEntering) {
      setTxStatus('confirming');
    } else if (enterSuccess) {
      setTxStatus('success');
      setTxMessage('Entered game! Waiting for randomness...');
      setTimeout(() => setTxStatus('idle'), 3000);
    } else if (enterError) {
      setTxStatus('error');
      setTxMessage(getErrorMessage(enterError));
      setTimeout(() => { setTxStatus('idle'); resetEnter(); }, 5000);
    }
  }, [enterHash, isEntering, enterSuccess, enterError]);

  useEffect(() => {
    if (flipHash && isFlippingTx) {
      setTxStatus('confirming');
    } else if (flipSuccess) {
      setTxStatus('success');
      setTxMessage('Flip complete!');
      refetchSession();
      refetchBalance();
      refetchRound();
      setIsFlipping(false);
      setTimeout(() => setTxStatus('idle'), 2000);
    } else if (flipError) {
      setTxStatus('error');
      setTxMessage(getErrorMessage(flipError));
      setIsFlipping(false);
      setTimeout(() => { setTxStatus('idle'); resetFlip(); }, 5000);
    }
  }, [flipHash, isFlippingTx, flipSuccess, flipError]);

  useEffect(() => {
    if (cashOutHash && isCashingOut) {
      setTxStatus('confirming');
    } else if (cashOutSuccess) {
      setTxStatus('success');
      setTxMessage('Cashed out successfully!');
      refetchSession();
      refetchBalance();
      refetchRound();
      // Show confetti for streak of 3+
      if (session && session.streak >= BigInt(3)) {
        setShowConfetti(true);
        setTimeout(() => setShowConfetti(false), 3000);
      }
      setTimeout(() => setTxStatus('idle'), 3000);
    } else if (cashOutError) {
      setTxStatus('error');
      setTxMessage(getErrorMessage(cashOutError));
      setTimeout(() => { setTxStatus('idle'); resetCashOut(); }, 5000);
    }
  }, [cashOutHash, isCashingOut, cashOutSuccess, cashOutError, session]);

  useEffect(() => {
    if (claimHash && isClaiming) {
      setTxStatus('confirming');
    } else if (claimSuccess) {
      setTxStatus('success');
      setTxMessage('Prize claimed! 🎉');
      setShowConfetti(true);
      refetchPrize();
      refetchBalance();
      setTimeout(() => {
        setShowConfetti(false);
        setTxStatus('idle');
      }, 3000);
    } else if (claimError) {
      setTxStatus('error');
      setTxMessage(getErrorMessage(claimError));
      setTimeout(() => { setTxStatus('idle'); resetClaim(); }, 5000);
    }
  }, [claimHash, isClaiming, claimSuccess, claimError]);

  // Helper to parse error messages
  const getErrorMessage = (error: Error | null): string => {
    if (!error) return 'Unknown error';
    const msg = error.message;
    if (msg.includes('User rejected')) return 'Transaction cancelled';
    if (msg.includes('insufficient funds')) return 'Insufficient ETH balance';
    if (msg.includes('SeedNotReady')) return 'Randomness not ready yet, please wait';
    if (msg.includes('NotInGame')) return 'No active game session';
    if (msg.includes('NoPrizeToClaim')) return 'No prize available to claim';
    if (msg.includes('execution reverted')) {
      const match = msg.match(/reason: ([^"]+)/);
      return match ? match[1] : 'Transaction failed';
    }
    return 'Transaction failed';
  };

  const handleEnterGame = () => {
    setTxStatus('pending');
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
    setTxStatus('pending');
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
    setTxStatus('pending');
    cashOut({
      address: CONTRACTS.clawFlipETH,
      abi: CLAW_FLIP_ETH_ABI,
      functionName: 'cashOut',
    });
  };

  const handleClaimPrize = () => {
    setTxStatus('pending');
    claimPrize({
      address: CONTRACTS.clawFlipETH,
      abi: CLAW_FLIP_ETH_ABI,
      functionName: 'claimPrize',
    });
  };

  const isInGame = session?.active;
  const isWaitingForVRF = isInGame && !session?.seedReady;
  const canFlip = isInGame && session?.seedReady;
  const hasUnclaimedPrize = unclaimedPrize && unclaimedPrize > BigInt(0);
  const isLoading = isEntering || isFlippingTx || isCashingOut || isClaiming;

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
      {showConfetti && <Confetti />}
      
      {/* Balance Display */}
      <div className="bg-white rounded-xl p-6 shadow-lg mb-6">
        <div className="flex justify-between items-center">
          <span className="text-lobster-blue">Your ETH Balance</span>
          <span className="text-2xl font-bold text-lobster-dark">
            {ethBalance ? Number(formatEther(ethBalance.value)).toFixed(4) : '0'} ETH
          </span>
        </div>
      </div>

      {/* Unclaimed Prize Banner */}
      {hasUnclaimedPrize && (
        <div className="bg-gradient-to-r from-yellow-400 to-orange-500 rounded-xl p-6 shadow-lg mb-6 text-white animate-pulse">
          <div className="flex justify-between items-center">
            <div>
              <h3 className="text-lg font-bold">🎉 You Won!</h3>
              <p className="text-2xl font-bold">
                {Number(formatEther(unclaimedPrize)).toFixed(4)} ETH
              </p>
              <p className="text-sm opacity-90">Unclaimed prize waiting for you</p>
            </div>
            <button
              onClick={handleClaimPrize}
              disabled={isClaiming}
              className="px-6 py-3 bg-white text-orange-600 rounded-xl font-bold hover:bg-orange-50 transition disabled:opacity-50"
            >
              {isClaiming ? 'Claiming...' : '💰 Claim'}
            </button>
          </div>
        </div>
      )}

      {/* Transaction Status */}
      <TxStatus status={txStatus} message={txMessage} />

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
            
            <div className="mt-4 p-3 bg-blue-50 rounded-lg">
              <p className="text-xs text-blue-700">
                🔐 <strong>Chainlink VRF Protected</strong> — Fair randomness guaranteed by Chainlink oracles
              </p>
            </div>
          </div>
        ) : isWaitingForVRF ? (
          /* VRF Waiting Screen */
          <VRFSpinner />
        ) : (
          /* In Game - Ready to Flip */
          <div className="text-center">
            <div className="mb-4">
              <span className="text-sm text-lobster-blue">Current Streak</span>
              <div className="text-5xl font-bold text-lobster-red">
                {session.streak.toString()} 🔥
              </div>
            </div>

            {/* Seed Ready Indicator */}
            <div className="mb-4 inline-flex items-center gap-2 px-3 py-1 bg-green-100 text-green-700 rounded-full text-sm font-medium">
              <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
              Randomness Ready
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
                disabled={isLoading || !canFlip}
                className="py-4 bg-lobster-red text-white rounded-xl font-bold text-lg hover:bg-red-700 transition disabled:opacity-50"
              >
                {isFlippingTx ? '...' : '🦞 HEADS'}
              </button>
              <button
                onClick={() => handleFlip(false)}
                disabled={isLoading || !canFlip}
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
            
            {session.streak >= BigInt(3) && (
              <p className="text-sm text-green-600 mt-2 font-medium">
                🔥 Nice streak! Cash out to lock in your win!
              </p>
            )}
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
          {currentRound.leader === address && currentRound.leader !== ZERO_ADDRESS && (
            <div className="mt-4 p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
              <p className="text-sm text-yellow-800 font-medium">
                👑 You're in the lead! Keep it up to win the daily prize!
              </p>
            </div>
          )}
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
