'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, PerspectiveCamera } from '@react-three/drei';
import { useRef } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';

const LivingRoomEnvironment = () => {
  return (
    <>
      {/* Floor */}
      <mesh position={[0, 0, 0]} receiveShadow>
        <planeGeometry args={[100, 100]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.4} metalness={0.1} />
      </mesh>

      {/* Back wall */}
      <mesh position={[0, 15, -40]} receiveShadow>
        <planeGeometry args={[100, 30]} />
        <meshStandardMaterial color="#0f0f0f" roughness={0.5} />
      </mesh>

      {/* Left wall */}
      <mesh position={[-50, 15, 0]} rotation={[0, Math.PI / 2, 0]} receiveShadow>
        <planeGeometry args={[100, 30]} />
        <meshStandardMaterial color="#0f0f0f" roughness={0.5} />
      </mesh>

      {/* Right wall */}
      <mesh position={[50, 15, 0]} rotation={[0, Math.PI / 2, 0]} receiveShadow>
        <planeGeometry args={[100, 30]} />
        <meshStandardMaterial color="#0f0f0f" roughness={0.5} />
      </mesh>

      {/* Large window frame */}
      <mesh position={[0, 15, 30]} rotation={[0, Math.PI, 0]}>
        <boxGeometry args={[60, 20, 0.5]} />
        <meshStandardMaterial color="#1a1a1a" metalness={0.8} roughness={0.2} />
      </mesh>

      {/* Sofa */}
      <mesh position={[-15, 3, 15]} castShadow receiveShadow>
        <boxGeometry args={[30, 2, 8]} />
        <meshStandardMaterial color="#2a2a2a" roughness={0.3} />
      </mesh>

      {/* Coffee table */}
      <mesh position={[0, 2, 5]} castShadow receiveShadow>
        <boxGeometry args={[20, 1, 12]} />
        <meshStandardMaterial color="#3a3a3a" metalness={0.2} roughness={0.4} />
      </mesh>

      {/* Feature wall */}
      <mesh position={[0, 15, -35]} castShadow>
        <boxGeometry args={[60, 25, 2]} />
        <meshStandardMaterial color="#1a1a1a" metalness={0.1} />
      </mesh>

      {/* Accent lighting - warm tone */}
      <spotLight
        position={[30, 20, 10]}
        angle={Math.PI / 6}
        penumbra={0.5}
        intensity={0.8}
        castShadow
        color="#d4af37"
      />

      {/* Accent lighting - side */}
      <spotLight
        position={[-30, 20, 10]}
        angle={Math.PI / 6}
        penumbra={0.5}
        intensity={0.6}
        castShadow
        color="#a8d8ff"
      />
    </>
  );
};

const LivingRoomSceneInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    // Section 0.55 to 0.75: Living room
    const sectionStart = 0.55;
    const sectionEnd = 0.75;
    const range = sectionEnd - sectionStart;

    if (scrollProgress < sectionStart) return;
    if (scrollProgress > sectionEnd) {
      camera.position.set(-20, 8, 25);
      camera.lookAt(-5, 5, 0);
      return;
    }

    const sectionProgress = (scrollProgress - sectionStart) / range;

    // Pan through interior
    const startPos = new THREE.Vector3(2, 8, 15);
    const endPos = new THREE.Vector3(-20, 8, 25);

    camera.position.lerp(endPos, sectionProgress);

    const startLook = new THREE.Vector3(0, 5, 0);
    const endLook = new THREE.Vector3(-5, 5, 0);
    const lookPos = new THREE.Vector3().lerpVectors(startLook, endLook, sectionProgress);

    camera.lookAt(lookPos);
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[0, 8, 20]} fov={60} />
      <Environment preset="studio" environmentIntensity={0.8} />

      <directionalLight
        position={[40, 30, 30]}
        intensity={0.9}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
      />
      <ambientLight intensity={0.4} color="#ffffff" />

      {/* Warm fill light */}
      <pointLight position={[0, 20, 0]} intensity={0.5} color="#d4af37" />

      <LivingRoomEnvironment />
    </>
  );
};

export const LivingRoomScene = () => {
  return (
    <div className="living-room-scene" style={{ width: '100%', height: '200vh' }}>
      <div className="living-room-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          shadows
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <LivingRoomSceneInner />
        </Canvas>
      </div>
      <div
        className="room-label"
        style={{
          position: 'fixed',
          bottom: '5%',
          right: '5%',
          zIndex: 10,
          pointerEvents: 'none',
        }}
      >
        <p style={{ fontSize: '0.9rem', opacity: 0.6, fontWeight: 300 }}>
          Luxury Living Space
        </p>
      </div>
    </div>
  );
};
