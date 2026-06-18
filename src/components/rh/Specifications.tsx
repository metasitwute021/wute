import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Plus } from 'lucide-react'
import SectionHeading from './SectionHeading'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import { SPECIFICATIONS } from '../../data/houseData'

export default function Specifications() {
  const [open, setOpen] = useState<number | null>(0)

  return (
    <section id="specs" className="border-t border-white/10">
      <div className="mx-auto max-w-[1100px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Specification"
          title="Royal House Premium standard"
          description="The complete material schedule that underpins RH-CT.2124 — backed by a 20-year structural warranty."
        />

        <motion.div
          variants={stagger}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="mt-14 divide-y divide-white/12 border-y border-white/12"
        >
          {SPECIFICATIONS.map((group, i) => {
            const isOpen = open === i
            return (
              <motion.div key={group.category} variants={fadeUp}>
                <button
                  onClick={() => setOpen(isOpen ? null : i)}
                  className="flex w-full items-center justify-between gap-4 py-6 text-left"
                >
                  <span className="flex items-center gap-4">
                    <span className="text-xs tabular-nums text-gray-600">
                      {String(i + 1).padStart(2, '0')}
                    </span>
                    <span className="text-xl font-medium tracking-luxe sm:text-2xl">
                      {group.category}
                    </span>
                  </span>
                  <motion.span
                    animate={{ rotate: isOpen ? 45 : 0 }}
                    transition={{ duration: 0.3 }}
                    className="shrink-0 text-gray-400"
                  >
                    <Plus size={22} />
                  </motion.span>
                </button>

                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
                      className="overflow-hidden"
                    >
                      <dl className="grid gap-px overflow-hidden rounded-2xl border border-white/12 bg-white/10 pb-0 sm:grid-cols-2">
                        {group.items.map((it) => (
                          <div key={it.k} className="bg-black p-5">
                            <dt className="text-sm font-medium text-white">
                              {it.k}
                            </dt>
                            <dd className="mt-1 text-sm text-gray-400">{it.v}</dd>
                          </div>
                        ))}
                      </dl>
                      <div className="h-6" />
                    </motion.div>
                  )}
                </AnimatePresence>
              </motion.div>
            )
          })}
        </motion.div>
      </div>
    </section>
  )
}
