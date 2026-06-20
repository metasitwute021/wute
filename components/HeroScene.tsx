'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, OrbitControls, PerspectiveCamera } from '@react-three/drei';
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';
import BuildingModel from './BuildingModel';

const HeroSceneInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();
  const groupRef = useRef<THREE.Group>(null);

  useFrame(() => {
    if (!groupRef.current) return;

    // Section 0 to 0.15: Zoom in and rotate
    const sectionProgress = scrollProgress / 0.15;
    const clampedProgress = Math.min(sectionProgress, 1);

    // Start high above, gradually descend
    const startHeight = 50;
    const endHeight = 35;
    camera.position.y = THREE.MathUtils.lerp(startHeight, endHeight, clampedProgress);

    // Orbit around the building
    const angle = clampedProgress * Math.PI * 0.5;
    const radius = THREE.MathUtils.lerp(80, 60, clampedProgress);

    camera.position.x = Math.cos(angle) * radius;
    camera.position.z = Math.sin(angle) * radius;
    camera.lookAt(0, 0, 0);
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[80, 50, 80]} fov={45} />
      <Environment preset="sunset" environmentIntensity={1.2} />
      <directionalLight
        position={[100, 100, 50]}
        intensity={1.5}
        castShadow
        shadow-mapSize-width={4096}
        shadow-mapSize-height={4096}
        shadow-camera-left={-150}
        shadow-camera-right={150}
        shadow-camera-top={150}
        shadow-camera-bottom={-150}
      />
      <ambientLight intensity={0.5} />
      <BuildingModel />
      <group ref={groupRef} />
    </>
  );
};

export const HeroScene = () => {
  return (
    <div className="hero-scene" style={{ width: '100%', height: '300vh' }}>
      <div className="hero-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          shadows
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <HeroSceneInner />
        </Canvas>
      </div>
      <div className="hero-content" style={{ position: 'relative', pointerEvents: 'none' }}>
        <div
          className="hero-text"
          style={{
            position: 'fixed',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            textAlign: 'center',
            zIndex: 10,
          }}
        >
          <h1
            style={{
              fontSize: 'clamp(3rem, 8vw, 7rem)',
              fontWeight: 700,
              letterSpacing: '-2px',
              marginBottom: '1rem',
              opacity: 0.9,
            }}
          >
            Architecture Beyond
            <br />
            Imagination
          </h1>
          <p
            style={{
              fontSize: 'clamp(1rem, 2vw, 1.5rem)',
              fontWeight: 300,
              letterSpacing: '0.5px',
              maxWidth: '600px',
              margin: '0 auto',
              opacity: 0.7,
            }}
          >
            Where design, technology and luxury converge.
          </p>
        </div>
      </div>
    </div>
  );
};
