import { motion } from 'framer-motion'
import { CalendarCheck, FileText, Download, ArrowRight } from 'lucide-react'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import { MODEL, LIVING_AREA } from '../../data/houseData'
import floorplanFull from '../../assets/floorplan-full.webp'

const ACTIONS = [
  { icon: CalendarCheck, title: 'Schedule a Visit', sub: 'Tour the show home in person' },
  { icon: FileText, title: 'Request Quotation', sub: 'Tailored to your land & options' },
]

export default function Contact() {
  return (
    <section id="contact" className="border-t border-white/10 bg-black">
      <div className="mx-auto max-w-[1100px] px-5 py-24 sm:px-8 sm:py-32">
        <motion.div
          variants={fadeUp}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="glass-strong overflow-hidden rounded-[2rem] p-8 sm:p-14"
        >
          <p className="text-[11px] uppercase tracking-eyebrow text-gray-400">
            Enquire
          </p>
          <h2 className="mt-4 text-balance text-4xl font-semibold tracking-luxe sm:text-5xl md:text-6xl">
            Begin the conversation
          </h2>
          <p className="mt-5 max-w-xl text-base leading-relaxed text-gray-400">
            Reserve a private viewing of {MODEL.code} — a {LIVING_AREA} m²
            three-storey residence built to the {MODEL.builder} {MODEL.standard}
            {' '}standard.
          </p>

          <motion.div
            variants={stagger}
            initial="hidden"
            whileInView="show"
            viewport={viewport}
            className="mt-10 grid gap-4 sm:grid-cols-2"
          >
            {ACTIONS.map((a) => (
              <motion.button
                key={a.title}
                variants={fadeUp}
                className="group flex items-center justify-between gap-4 rounded-2xl border border-white/15 p-6 text-left transition-colors hover:border-white/40 hover:bg-white/[0.04]"
              >
                <span className="flex items-center gap-4">
                  <a.icon size={24} className="text-white" />
                  <span>
                    <span className="block font-medium">{a.title}</span>
                    <span className="block text-sm text-gray-500">{a.sub}</span>
                  </span>
                </span>
                <ArrowRight
                  size={18}
                  className="shrink-0 text-gray-500 transition-transform group-hover:translate-x-1 group-hover:text-white"
                />
              </motion.button>
            ))}
          </motion.div>

          <motion.a
            variants={fadeUp}
            initial="hidden"
            whileInView="show"
            viewport={viewport}
            href={floorplanFull}
            download="RH-CT.2124-floor-plans.webp"
            className="mt-4 flex items-center justify-center gap-2 rounded-2xl bg-white px-7 py-4 text-sm font-semibold text-black transition-transform hover:scale-[1.01] active:scale-95"
          >
            <Download size={18} />
            Download Floor Plan
          </motion.a>
        </motion.div>
      </div>
    </section>
  )
}
