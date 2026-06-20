'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { PerspectiveCamera, Line } from '@react-three/drei';
import { useRef, useState, useEffect } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';

const FloorPlanGeometry = () => {
  const groupRef = useRef<THREE.Group>(null);
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    if (!groupRef.current) return;

    // Section 0.85 to 0.95: Floor plan
    const sectionStart = 0.85;
    const sectionEnd = 0.95;
    const range = sectionEnd - sectionStart;

    if (scrollProgress < sectionStart) return;
    if (scrollProgress > sectionEnd) {
      groupRef.current.rotation.y = Math.PI * 0.2;
      return;
    }

    const sectionProgress = (scrollProgress - sectionStart) / range;
    groupRef.current.rotation.y = sectionProgress * Math.PI * 0.2;
    groupRef.current.position.z = sectionProgress * 10;
  });

  return (
    <group ref={groupRef}>
      {/* Living area outline */}
      <mesh position={[-20, 5, 0]}>
        <planeGeometry args={[25, 18]} />
        <meshStandardMaterial
          color="#0f0f0f"
          metalness={0.6}
          roughness={0.2}
          emissive="#d4af37"
          emissiveIntensity={0.2}
        />
      </mesh>

      {/* Kitchen outline */}
      <mesh position={[15, 5, -15]}>
        <planeGeometry args={[18, 20]} />
        <meshStandardMaterial
          color="#0f0f0f"
          metalness={0.6}
          roughness={0.2}
          emissive="#d4af37"
          emissiveIntensity={0.15}
        />
      </mesh>

      {/* Master bedroom */}
      <mesh position={[15, 5, 15]}>
        <planeGeometry args={[18, 22]} />
        <meshStandardMaterial
          color="#0f0f0f"
          metalness={0.6}
          roughness={0.2}
          emissive="#a8d8ff"
          emissiveIntensity={0.15}
        />
      </mesh>

      {/* Guest bedroom */}
      <mesh position={[-20, 5, -15]}>
        <planeGeometry args={[16, 16]} />
        <meshStandardMaterial
          color="#0f0f0f"
          metalness={0.6}
          roughness={0.2}
          emissive="#a8d8ff"
          emissiveIntensity={0.15}
        />
      </mesh>

      {/* Central circulation */}
      <mesh position={[-2, 5, 5]}>
        <cylinderGeometry args={[8, 8, 0.1, 32]} />
        <meshStandardMaterial color="#1a1a1a" metalness={0.4} />
      </mesh>

      {/* Room labels */}
      <group>
        <mesh position={[-20, 6, 0]} scale={[0.5, 0.5, 1]}>
          <planeGeometry args={[15, 2]} />
          <meshBasicMaterial color="#d4af37" transparent opacity={0} />
        </mesh>
      </group>
    </group>
  );
};

const FloorPlanSceneInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    // Position camera for floor plan view
    const sectionStart = 0.85;
    const sectionEnd = 0.95;

    if (scrollProgress >= sectionStart && scrollProgress <= sectionEnd) {
      camera.position.set(0, 45, 25);
      camera.lookAt(0, 5, 0);
    }
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[0, 45, 25]} fov={50} />
      <ambientLight intensity={0.6} color="#ffffff" />
      <directionalLight position={[20, 30, 20]} intensity={0.8} color="#d4af37" />

      <FloorPlanGeometry />
    </>
  );
};

export const FloorPlan = () => {
  return (
    <div className="floor-plan" style={{ width: '100%', height: '150vh' }}>
      <div className="floor-plan-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <FloorPlanSceneInner />
        </Canvas>
      </div>

      <div
        className="floor-plan-info"
        style={{
          position: 'fixed',
          top: '10%',
          left: '5%',
          zIndex: 10,
          pointerEvents: 'none',
        }}
      >
        <h2 style={{ fontSize: '2rem', fontWeight: 600, marginBottom: '1rem' }}>
          Floor Plan
        </h2>
        <div style={{ opacity: 0.7, fontSize: '0.95rem' }}>
          <p>Living Area • Kitchen • Master Suite</p>
          <p>Guest Bedroom • Premium Circulation</p>
        </div>
      </div>
    </div>
  );
};
