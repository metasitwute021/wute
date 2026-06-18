import type { Variants } from 'framer-motion'

const EASE = [0.16, 1, 0.3, 1] as const

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 32 },
  show: { opacity: 1, y: 0, transition: { duration: 0.9, ease: EASE } },
}

export const fade: Variants = {
  hidden: { opacity: 0 },
  show: { opacity: 1, transition: { duration: 1.1, ease: EASE } },
}

export const stagger: Variants = {
  hidden: {},
  show: { transition: { staggerChildren: 0.08, delayChildren: 0.05 } },
}

export const staggerWord: Variants = {
  hidden: { opacity: 0, y: '0.5em' },
  show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: EASE } },
}

// Shared viewport config for scroll-reveal
export const viewport = { once: true, margin: '-80px' } as const
