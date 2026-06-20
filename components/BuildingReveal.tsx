'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, PerspectiveCamera } from '@react-three/drei';
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';
import BuildingModel from './BuildingModel';

const BuildingRevealInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    // Section 0.15 to 0.35: Building reveal
    const sectionStart = 0.15;
    const sectionEnd = 0.35;
    const range = sectionEnd - sectionStart;

    if (scrollProgress < sectionStart) return;
    if (scrollProgress > sectionEnd) {
      // Lock at end position
      camera.position.set(35, 15, 40);
      camera.lookAt(0, 0, 0);
      return;
    }

    const sectionProgress = (scrollProgress - sectionStart) / range;

    // Descend and tighten orbit
    const startHeight = 35;
    const endHeight = 15;
    camera.position.y = THREE.MathUtils.lerp(startHeight, endHeight, sectionProgress);

    const angle = sectionProgress * Math.PI * 0.3;
    const radius = THREE.MathUtils.lerp(60, 35, sectionProgress);

    camera.position.x = Math.cos(angle) * radius;
    camera.position.z = Math.sin(angle) * radius;
    camera.lookAt(0, 5, 0);
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[60, 35, 60]} fov={50} />
      <Environment preset="sunset" environmentIntensity={1.3} />
      <directionalLight
        position={[120, 80, 60]}
        intensity={1.6}
        castShadow
        shadow-mapSize-width={4096}
        shadow-mapSize-height={4096}
        shadow-camera-left={-150}
        shadow-camera-right={150}
        shadow-camera-top={150}
        shadow-camera-bottom={-150}
      />
      <ambientLight intensity={0.6} />
      <BuildingModel />
    </>
  );
};

export const BuildingReveal = () => {
  return (
    <div className="building-reveal" style={{ width: '100%', height: '200vh' }}>
      <div className="building-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          shadows
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <BuildingRevealInner />
        </Canvas>
      </div>
    </div>
  );
};
