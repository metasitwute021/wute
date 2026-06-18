import { motion } from 'framer-motion'
import { STATS, MODEL } from '../../data/houseData'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import SectionHeading from './SectionHeading'

export default function Overview() {
  return (
    <section id="overview" className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
      <SectionHeading
        eyebrow="The Residence"
        title="An overview of RH-CT.2124"
        description="Every figure below is drawn directly from the architectural plans — a precise account of how the home is composed across its three storeys."
      />

      <motion.div
        variants={stagger}
        initial="hidden"
        whileInView="show"
        viewport={viewport}
        className="mt-14 grid grid-cols-2 gap-px overflow-hidden rounded-3xl border border-white/15 bg-white/10 sm:mt-20 lg:grid-cols-3"
      >
        {STATS.map((s) => (
          <motion.div
            key={s.label}
            variants={fadeUp}
            className="group bg-black p-7 transition-colors duration-300 hover:bg-white/[0.04] sm:p-10"
          >
            <div className="text-5xl font-semibold tracking-luxe sm:text-6xl">
              {s.value}
            </div>
            <div className="mt-3 text-sm font-medium text-white sm:text-base">
              {s.label}
            </div>
            <div className="mt-1 text-xs text-gray-500 sm:text-sm">{s.sub}</div>
          </motion.div>
        ))}
      </motion.div>

      <motion.p
        variants={fadeUp}
        initial="hidden"
        whileInView="show"
        viewport={viewport}
        className="mt-8 text-xs text-gray-600"
      >
        Model {MODEL.code} · Built to {MODEL.builder} {MODEL.standard} standard ·
        Specification effective {MODEL.effective}.
      </motion.p>
    </section>
  )
}
