'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, PerspectiveCamera } from '@react-three/drei';
import { useRef } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';

const WalkthroughEnvironment = () => {
  return (
    <>
      {/* Floor */}
      <mesh position={[0, 0, 0]} receiveShadow>
        <planeGeometry args={[200, 200]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.4} />
      </mesh>

      {/* Walls */}
      <mesh position={[0, 15, -60]} receiveShadow>
        <planeGeometry args={[200, 30]} />
        <meshStandardMaterial color="#0f0f0f" roughness={0.5} />
      </mesh>

      {/* Multiple rooms */}
      <mesh position={[-40, 15, -20]} receiveShadow>
        <planeGeometry args={[60, 30]} />
        <meshStandardMaterial color="#0f0f0f" roughness={0.5} />
      </mesh>

      {/* Ceiling details */}
      <mesh position={[0, 28, 0]} rotation={[0, 0, 0]} receiveShadow>
        <planeGeometry args={[200, 200]} />
        <meshStandardMaterial color="#0a0a0a" roughness={0.8} />
      </mesh>

      {/* Columns */}
      {[[-30, 14, -30], [30, 14, -30], [-30, 14, 30], [30, 14, 30]].map(
        (pos, i) => (
          <mesh key={i} position={pos as [number, number, number]} castShadow>
            <cylinderGeometry args={[3, 3, 28, 32]} />
            <meshStandardMaterial color="#2a2a2a" metalness={0.3} roughness={0.4} />
          </mesh>
        )
      )}

      {/* Dynamic lighting */}
      <pointLight position={[0, 20, 0]} intensity={0.7} color="#d4af37" />
      <pointLight position={[-40, 18, -20]} intensity={0.5} color="#a8d8ff" />
      <pointLight position={[40, 18, 20]} intensity={0.5} color="#d4af37" />
    </>
  );
};

const WalkthroughSceneInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    // Section 0.75 to 0.85: Immersive walkthrough
    const sectionStart = 0.75;
    const sectionEnd = 0.85;
    const range = sectionEnd - sectionStart;

    if (scrollProgress < sectionStart) return;
    if (scrollProgress > sectionEnd) {
      camera.position.set(0, 8, 30);
      camera.lookAt(0, 8, -20);
      return;
    }

    const sectionProgress = (scrollProgress - sectionStart) / range;

    // Navigate through space
    camera.position.x = Math.sin(sectionProgress * Math.PI * 2) * 40;
    camera.position.y = 8 + Math.sin(sectionProgress * Math.PI) * 2;
    camera.position.z = 30 - sectionProgress * 50;

    camera.lookAt(0, 8, -20);
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[0, 8, 30]} fov={70} />
      <Environment preset="studio" environmentIntensity={0.9} />

      <directionalLight
        position={[50, 30, 30]}
        intensity={1}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
      />
      <ambientLight intensity={0.5} />

      <WalkthroughEnvironment />
    </>
  );
};

export const ImmersiveWalkthrough = () => {
  return (
    <div className="immersive-walkthrough" style={{ width: '100%', height: '150vh' }}>
      <div className="walkthrough-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          shadows
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <WalkthroughSceneInner />
        </Canvas>
      </div>
    </div>
  );
};
