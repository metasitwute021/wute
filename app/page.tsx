'use client';

import { Suspense } from 'react';
import { HeroScene } from '@/components/HeroScene';
import { BuildingReveal } from '@/components/BuildingReveal';
import { ApproachScene } from '@/components/ApproachScene';
import { LivingRoomScene } from '@/components/LivingRoomScene';
import { ImmersiveWalkthrough } from '@/components/ImmersiveWalkthrough';
import { FloorPlan } from '@/components/FloorPlan';
import { ContactSection } from '@/components/ContactSection';

const LoadingFallback = () => (
  <div
    style={{
      width: '100%',
      height: '100%',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: '#0a0a0a',
      color: '#ffffff',
      fontSize: '1rem',
      fontWeight: 300,
    }}
  >
    Loading...
  </div>
);

export default function Home() {
  return (
    <main style={{ width: '100%', overflow: 'hidden' }}>
      {/* Section 1: Hero */}
      <Suspense fallback={<LoadingFallback />}>
        <HeroScene />
      </Suspense>

      {/* Section 2: Building Reveal */}
      <Suspense fallback={<LoadingFallback />}>
        <BuildingReveal />
      </Suspense>

      {/* Section 3: Approach */}
      <Suspense fallback={<LoadingFallback />}>
        <ApproachScene />
      </Suspense>

      {/* Section 5: Living Room */}
      <Suspense fallback={<LoadingFallback />}>
        <LivingRoomScene />
      </Suspense>

      {/* Section 6: Immersive Walkthrough */}
      <Suspense fallback={<LoadingFallback />}>
        <ImmersiveWalkthrough />
      </Suspense>

      {/* Section 7: Floor Plan */}
      <Suspense fallback={<LoadingFallback />}>
        <FloorPlan />
      </Suspense>

      {/* Section 8: Contact */}
      <Suspense fallback={<LoadingFallback />}>
        <ContactSection />
      </Suspense>
    </main>
  );
}
