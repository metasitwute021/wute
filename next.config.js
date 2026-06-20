/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config, { isServer }) => {
    config.module.rules.push({
      test: /\.(glb|gltf|fbx|obj|mtl)$/,
      type: 'asset/resource',
    });
    return config;
  },
  turbopack: {
    resolveAlias: {
      '@': './',
    },
  },
  images: {
    unoptimized: true,
  },
};

module.exports = nextConfig;
