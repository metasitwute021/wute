'use client';

import { useEffect, useRef, Suspense } from 'react';
import { useGLTF, useProgress } from '@react-three/drei';
import * as THREE from 'three';
import { OBJLoader } from 'three/examples/jsm/loaders/OBJLoader.js';
import { MTLLoader } from 'three/examples/jsm/loaders/MTLLoader.js';

export const BuildingModel = (props: any) => {
  const groupRef = useRef<THREE.Group>(null);
  const loadedModelRef = useRef<THREE.Group | null>(null);

  useEffect(() => {
    if (!groupRef.current) return;

    const mtlLoader = new MTLLoader();
    const objLoader = new OBJLoader();

    mtlLoader.load('/building_04.mtl', (materials) => {
      materials.preload();
      objLoader.setMaterials(materials);
      objLoader.load('/building_04.obj', (object) => {
        object.scale.set(1, 1, 1);
        object.position.set(0, -5, 0);
        object.castShadow = true;
        object.receiveShadow = true;

        object.traverse((node: any) => {
          if (node.isMesh) {
            node.castShadow = true;
            node.receiveShadow = true;
            if (node.material) {
              node.material.envMapIntensity = 1.5;
            }
          }
        });

        groupRef.current?.add(object);
        loadedModelRef.current = object;
      });
    });

    return () => {
      if (loadedModelRef.current && groupRef.current) {
        groupRef.current.remove(loadedModelRef.current);
      }
    };
  }, []);

  return <group ref={groupRef} {...props} />;
};

export default BuildingModel;
