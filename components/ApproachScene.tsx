'use client';

import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, PerspectiveCamera, Points } from '@react-three/drei';
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { useScrollAnimation } from './useScrollAnimation';
import BuildingModel from './BuildingModel';

const ParticleField = () => {
  const pointsRef = useRef<THREE.Points>(null);

  useEffect(() => {
    if (!pointsRef.current) return;

    const count = 500;
    const positions = new Float32Array(count * 3);

    for (let i = 0; i < count * 3; i += 3) {
      positions[i] = (Math.random() - 0.5) * 150;
      positions[i + 1] = (Math.random() - 0.5) * 100;
      positions[i + 2] = (Math.random() - 0.5) * 150;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    return () => geometry.dispose();
  }, []);

  return (
    <Points
      ref={pointsRef}
      stride={3}
      frustumCulled={false}
    >
      <pointsMaterial size={0.15} sizeAttenuation color="#ffffff" transparent opacity={0.3} />
    </Points>
  );
};

const ApproachSceneInner = () => {
  const { camera } = useThree();
  const scrollProgress = useScrollAnimation();

  useFrame(() => {
    // Section 0.35 to 0.55: Approach
    const sectionStart = 0.35;
    const sectionEnd = 0.55;
    const range = sectionEnd - sectionStart;

    if (scrollProgress < sectionStart) return;
    if (scrollProgress > sectionEnd) {
      camera.position.set(2, 8, 15);
      camera.lookAt(0, 5, 0);
      return;
    }

    const sectionProgress = (scrollProgress - sectionStart) / range;

    // Move toward the facade
    const startPos = new THREE.Vector3(35, 15, 40);
    const endPos = new THREE.Vector3(2, 8, 15);

    camera.position.lerp(endPos, sectionProgress);
    camera.lookAt(0, 5, 0);

    // Gradually increase depth of field by narrowing FOV
    if (camera instanceof THREE.PerspectiveCamera) {
      camera.fov = THREE.MathUtils.lerp(50, 60, sectionProgress);
      camera.updateProjectionMatrix();
    }
  });

  return (
    <>
      <PerspectiveCamera makeDefault position={[35, 15, 40]} fov={50} />
      <Environment preset="sunset" environmentIntensity={1.4} />
      <directionalLight
        position={[100, 80, 50]}
        intensity={1.7}
        castShadow
        shadow-mapSize-width={4096}
        shadow-mapSize-height={4096}
        shadow-camera-left={-150}
        shadow-camera-right={150}
        shadow-camera-top={150}
        shadow-camera-bottom={-150}
      />
      <ambientLight intensity={0.7} />
      <ParticleField />
      <BuildingModel />
    </>
  );
};

export const ApproachScene = () => {
  return (
    <div className="approach-scene" style={{ width: '100%', height: '200vh' }}>
      <div className="approach-canvas" style={{ position: 'fixed', inset: 0 }}>
        <Canvas
          shadows
          gl={{
            antialias: true,
            preserveDrawingBuffer: true,
            alpha: true,
          }}
        >
          <ApproachSceneInner />
        </Canvas>
      </div>
    </div>
  );
};
