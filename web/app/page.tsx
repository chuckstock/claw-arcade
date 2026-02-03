'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { ClawFlip } from '@/components/ClawFlip';

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-b from-lobster-accent to-lobster-light">
      {/* Header */}
      <header className="border-b border-lobster-light bg-white/80 backdrop-blur-sm sticky top-0 z-50">
        <div className="max-w-4xl mx-auto px-4 py-4 flex justify-between items-center">
          <div className="flex items-center gap-2">
            <span className="text-3xl">🦞</span>
            <span className="text-xl font-bold text-lobster-dark">Lobster Arcade</span>
          </div>
          <ConnectButton />
        </div>
      </header>

      {/* Hero */}
      <section className="max-w-4xl mx-auto px-4 py-12 text-center">
        <h1 className="text-5xl font-bold text-lobster-dark mb-4">
          Welcome to the Arcade
        </h1>
        <p className="text-xl text-lobster-blue mb-2">
          On-chain games on Base Sepolia
        </p>
        <p className="text-sm text-lobster-blue/70 mb-8">
          🧪 Testnet — Pay with ETH, 5% goes to $ZER0_AI buyback & burn
        </p>
      </section>

      {/* Game */}
      <section className="max-w-4xl mx-auto px-4 pb-12">
        <ClawFlip />
      </section>

      {/* Footer */}
      <footer className="border-t border-lobster-light bg-white/50 mt-12">
        <div className="max-w-4xl mx-auto px-4 py-6 text-center text-sm text-lobster-blue">
          <p>Built by Zer0 🦞</p>
          <p className="mt-1">
            <a 
              href="https://sepolia.basescan.org/address/0x07AC36e2660FFfFAA26CFCEE821889Eb2945b47B" 
              target="_blank" 
              rel="noopener noreferrer"
              className="underline hover:text-lobster-dark"
            >
              View Contract on BaseScan
            </a>
          </p>
        </div>
      </footer>
    </main>
  );
}
