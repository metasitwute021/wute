'use client';

import { motion } from 'framer-motion';
import { useScrollAnimation } from './useScrollAnimation';
import { useEffect, useState } from 'react';

export const ContactSection = () => {
  const scrollProgress = useScrollAnimation();
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    // Show when we reach section 7 (95% scroll progress)
    if (scrollProgress > 0.95) {
      setIsVisible(true);
    }
  }, [scrollProgress]);

  return (
    <section
      className="contact-section"
      style={{
        width: '100%',
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'linear-gradient(180deg, #0a0a0a 0%, #1a1a1a 100%)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Background building silhouette */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: 0.1,
          background: 'url(data:image/svg+xml,%3Csvg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"%3E%3Cpath d="M20,30 L20,70 L30,70 L30,40 L40,40 L40,70 L60,70 L60,35 L75,35 L75,70 L85,70 L85,25" stroke="white" fill="none" stroke-width="0.5"/%3E%3C/svg%3E)',
          backgroundRepeat: 'repeat',
          backgroundSize: '200px 200px',
          pointerEvents: 'none',
        }}
      />

      <motion.div
        className="contact-content"
        style={{
          textAlign: 'center',
          zIndex: 10,
          position: 'relative',
        }}
        initial={{ opacity: 0, y: 20 }}
        animate={isVisible ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
        transition={{ duration: 1 }}
      >
        <h2
          style={{
            fontSize: 'clamp(2rem, 5vw, 4rem)',
            fontWeight: 700,
            letterSpacing: '-1px',
            marginBottom: '2rem',
          }}
        >
          Ready to Experience Luxury?
        </h2>

        <p
          style={{
            fontSize: 'clamp(1rem, 1.5vw, 1.2rem)',
            fontWeight: 300,
            marginBottom: '3rem',
            maxWidth: '600px',
            margin: '0 auto 3rem',
            opacity: 0.8,
          }}
        >
          Schedule a private viewing and discover how design, technology, and
          luxury converge.
        </p>

        <div
          style={{
            display: 'flex',
            gap: '2rem',
            justifyContent: 'center',
            flexWrap: 'wrap',
            marginBottom: '3rem',
          }}
        >
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            style={{
              padding: '1rem 2.5rem',
              fontSize: '1rem',
              fontWeight: 600,
              letterSpacing: '0.5px',
              background: '#d4af37',
              color: '#0a0a0a',
              border: 'none',
              cursor: 'pointer',
              transition: 'all 0.3s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.boxShadow =
                '0 20px 40px rgba(212, 175, 55, 0.3)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.boxShadow = 'none';
            }}
          >
            Schedule Your Visit
          </motion.button>

          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            style={{
              padding: '1rem 2.5rem',
              fontSize: '1rem',
              fontWeight: 600,
              letterSpacing: '0.5px',
              border: '1px solid #d4af37',
              color: '#d4af37',
              background: 'transparent',
              cursor: 'pointer',
              transition: 'all 0.3s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.boxShadow =
                '0 20px 40px rgba(212, 175, 55, 0.2)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.boxShadow = 'none';
            }}
          >
            Request Information
          </motion.button>
        </div>

        <div
          style={{
            display: 'flex',
            gap: '2rem',
            justifyContent: 'center',
            flexWrap: 'wrap',
            opacity: 0.6,
            fontSize: '0.95rem',
            fontWeight: 300,
          }}
        >
          <a href="tel:+1234567890" style={{ textDecoration: 'none' }}>
            +1 (234) 567-890
          </a>
          <span>•</span>
          <a href="mailto:info@luxuryarch.com" style={{ textDecoration: 'none' }}>
            info@luxuryarch.com
          </a>
          <span>•</span>
          <a href="#" style={{ textDecoration: 'none' }}>
            Download Brochure
          </a>
        </div>
      </motion.div>
    </section>
  );
};
