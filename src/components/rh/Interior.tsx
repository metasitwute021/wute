import { motion } from 'framer-motion'
import SectionHeading from './SectionHeading'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import { INTERIOR_SPACES } from '../../data/houseData'

export default function Interior() {
  return (
    <section id="interior" className="border-t border-white/10 bg-black">
      <div className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Interior"
          title="Spaces designed to breathe"
          description="From the open ground-floor social spine to the 27-square-metre master suite, each space is described from the home's true layout."
        />

        <motion.div
          variants={stagger}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="mt-14 grid gap-px overflow-hidden rounded-3xl border border-white/15 bg-white/10 sm:mt-20 md:grid-cols-2"
        >
          {INTERIOR_SPACES.map((s, i) => (
            <motion.article
              key={s.title}
              variants={fadeUp}
              className="flex flex-col gap-4 bg-black p-8 transition-colors duration-300 hover:bg-white/[0.04] sm:p-10"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs tabular-nums text-gray-600">
                  {String(i + 1).padStart(2, '0')}
                </span>
                <span className="rounded-full border border-white/15 px-3 py-1 text-xs text-gray-300">
                  {s.area}
                </span>
              </div>
              <h3 className="text-2xl font-semibold tracking-luxe sm:text-3xl">
                {s.title}
              </h3>
              <p className="text-sm leading-relaxed text-gray-400 sm:text-base">
                {s.body}
              </p>
            </motion.article>
          ))}
        </motion.div>
      </div>
    </section>
  )
}
