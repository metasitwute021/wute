import { motion } from 'framer-motion'
import { ArrowDownRight, Layers } from 'lucide-react'
import heroImg from '../../assets/exterior-hero.webp'
import { MODEL } from '../../data/houseData'

const EASE = [0.16, 1, 0.3, 1] as const

export default function Hero() {
  return (
    <section id="top" className="relative h-[100svh] w-full overflow-hidden">
      {/* Backdrop */}
      <div className="absolute inset-0">
        <img
          src={heroImg}
          alt={`${MODEL.code} exterior`}
          className="h-full w-full object-cover animate-kenburns"
        />
        {/* Cinematic gradients */}
        <div className="absolute inset-0 bg-gradient-to-t from-black via-black/30 to-black/60" />
        <div className="absolute inset-0 bg-gradient-to-r from-black/70 via-transparent to-transparent" />
      </div>

      {/* Content */}
      <div className="relative z-10 mx-auto flex h-full max-w-[1400px] flex-col justify-end px-5 pb-24 sm:px-8 sm:pb-28">
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: EASE, delay: 0.2 }}
          className="mb-5 flex items-center gap-3 text-[11px] uppercase tracking-eyebrow text-gray-300"
        >
          <Layers size={14} />
          {MODEL.builder} · {MODEL.standard}
        </motion.div>

        <h1 className="max-w-5xl text-balance text-[15vw] font-semibold leading-[0.9] tracking-luxe sm:text-7xl md:text-8xl lg:text-9xl">
          {MODEL.code.split('').map((c, i) => (
            <motion.span
              key={i}
              initial={{ opacity: 0, y: '0.55em' }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, ease: EASE, delay: 0.25 + i * 0.04 }}
              className="inline-block"
            >
              {c}
            </motion.span>
          ))}
        </h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, ease: EASE, delay: 0.7 }}
          className="mt-6 max-w-xl text-base leading-relaxed text-gray-300 sm:text-lg"
        >
          A three-storey architectural statement of light, volume and quiet
          luxury. Five bedrooms rising across 304 square metres of land —
          engineered to the Royal House Premium standard.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, ease: EASE, delay: 0.85 }}
          className="mt-9 flex flex-col gap-3 sm:flex-row sm:items-center"
        >
          <a
            href="#floorplans"
            className="inline-flex items-center justify-center gap-2 rounded-full bg-white px-7 py-3.5 text-sm font-semibold text-black transition-transform hover:scale-[1.03] active:scale-95"
          >
            View Floor Plan
          </a>
          <a
            href="#interior"
            className="inline-flex items-center justify-center gap-2 rounded-full border border-white/25 px-7 py-3.5 text-sm font-medium text-white transition-colors hover:bg-white/10"
          >
            Explore Interior
            <ArrowDownRight size={16} />
          </a>
        </motion.div>
      </div>

      {/* Scroll hint */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.4 }}
        className="absolute bottom-6 left-1/2 z-10 hidden -translate-x-1/2 sm:block"
      >
        <div className="h-12 w-[1px] animate-pulse bg-gradient-to-b from-white/0 via-white/60 to-white/0" />
      </motion.div>
    </section>
  )
}
