import { motion } from 'framer-motion'
import SectionHeading from './SectionHeading'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import { MATERIALS } from '../../data/houseData'

export default function Materials() {
  return (
    <section id="materials" className="border-t border-white/10 bg-black">
      <div className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Materials"
          title="Specified without compromise"
          description="Signature brands and construction standards selected for longevity, comfort and a refined finish throughout."
        />

        <motion.div
          variants={stagger}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="mt-14 grid grid-cols-1 gap-4 sm:mt-20 sm:grid-cols-2 lg:grid-cols-4"
        >
          {MATERIALS.map((m) => (
            <motion.div
              key={m.name}
              variants={fadeUp}
              className="group relative flex flex-col justify-between gap-8 rounded-3xl border border-white/12 p-6 transition-colors duration-300 hover:border-white/40"
            >
              <span className="self-start rounded-full bg-white/[0.06] px-3 py-1 text-[10px] uppercase tracking-eyebrow text-gray-400">
                {m.tag}
              </span>
              <div>
                <h3 className="text-lg font-semibold tracking-luxe">{m.name}</h3>
                <p className="mt-2 text-sm leading-relaxed text-gray-500">
                  {m.spec}
                </p>
              </div>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  )
}
