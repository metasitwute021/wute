import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X } from 'lucide-react'
import SectionHeading from './SectionHeading'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import hero from '../../assets/exterior-hero.webp'
import facade from '../../assets/exterior-facade.webp'
import balcony from '../../assets/exterior-balcony.webp'
import entrance from '../../assets/exterior-entrance.webp'
import garden from '../../assets/exterior-garden.webp'
import full from '../../assets/floorplan-full.webp'
import ground from '../../assets/floor-ground.webp'

const ITEMS = [
  { img: hero, label: 'Exterior — Hero View', span: 'row-span-2' },
  { img: balcony, label: 'Upper Terraces' },
  { img: entrance, label: 'Entrance & Carport' },
  { img: full, label: 'Floor Plans — Full Sheet', span: 'row-span-2' },
  { img: facade, label: 'Front Facade' },
  { img: garden, label: 'Garden Elevation' },
  { img: ground, label: 'Ground Floor Plan' },
]

export default function Gallery() {
  const [lightbox, setLightbox] = useState<{ img: string; label: string } | null>(
    null,
  )

  return (
    <section id="gallery" className="border-t border-white/10">
      <div className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Gallery"
          title="Every angle, in detail"
          description="Renderings and architectural drawings of RH-CT.2124. Tap any image to enlarge."
        />

        <motion.div
          variants={stagger}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="mt-14 grid auto-rows-[200px] grid-cols-2 gap-4 sm:mt-20 sm:auto-rows-[260px] lg:grid-cols-3"
        >
          {ITEMS.map((it) => (
            <motion.button
              key={it.label}
              variants={fadeUp}
              onClick={() => setLightbox(it)}
              className={`group relative overflow-hidden rounded-2xl border border-white/12 ${
                it.span ?? ''
              }`}
            >
              <img
                src={it.img}
                alt={it.label}
                className="h-full w-full object-cover transition-transform duration-[1.2s] ease-out group-hover:scale-105"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100" />
              <span className="absolute bottom-3 left-3 text-left text-sm font-medium opacity-0 transition-opacity duration-300 group-hover:opacity-100">
                {it.label}
              </span>
            </motion.button>
          ))}
        </motion.div>
      </div>

      <AnimatePresence>
        {lightbox && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setLightbox(null)}
            className="fixed inset-0 z-[200] flex items-center justify-center bg-black/95 p-4 backdrop-blur"
          >
            <button
              className="absolute right-5 top-5 grid h-11 w-11 place-items-center rounded-full border border-white/20 text-white"
              aria-label="Close"
            >
              <X size={20} />
            </button>
            <motion.img
              initial={{ scale: 0.96, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.96, opacity: 0 }}
              transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
              src={lightbox.img}
              alt={lightbox.label}
              onClick={(e) => e.stopPropagation()}
              className="max-h-[88vh] max-w-[94vw] rounded-2xl object-contain"
            />
            <span className="absolute bottom-6 left-1/2 -translate-x-1/2 text-sm text-gray-400">
              {lightbox.label}
            </span>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  )
}
