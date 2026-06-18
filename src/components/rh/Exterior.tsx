import { motion } from 'framer-motion'
import SectionHeading from './SectionHeading'
import { fadeUp, stagger, viewport } from '../../lib/motion'
import facade from '../../assets/exterior-facade.webp'
import balcony from '../../assets/exterior-balcony.webp'
import entrance from '../../assets/exterior-entrance.webp'
import garden from '../../assets/exterior-garden.webp'

const SHOTS = [
  { img: facade, title: 'Front Facade', note: 'Hip-roof massing in Prestige Horizon tile' },
  { img: entrance, title: 'Entrance & Carport', note: 'Covered two-car arrival court' },
  { img: balcony, title: 'Upper Terraces', note: 'Stacked balconies & timber screens' },
  { img: garden, title: 'Garden Elevation', note: 'Full-height glazing to the lawn' },
]

export default function Exterior() {
  return (
    <section id="exterior" className="border-t border-white/10">
      <div className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Exterior"
          title="A sculpted silhouette"
          description="Crisp white volumes are anchored by a charcoal base and a low hip roof — a contemporary composition that reads as effortlessly as it lives."
        />

        <motion.div
          variants={stagger}
          initial="hidden"
          whileInView="show"
          viewport={viewport}
          className="mt-14 grid gap-4 sm:mt-20 sm:grid-cols-2"
        >
          {SHOTS.map((s, i) => (
            <motion.figure
              key={s.title}
              variants={fadeUp}
              className={`group relative overflow-hidden rounded-3xl border border-white/12 ${
                i === 0 ? 'sm:col-span-2' : ''
              }`}
            >
              <img
                src={s.img}
                alt={s.title}
                className="aspect-[16/10] w-full object-cover transition-transform duration-[1.2s] ease-out group-hover:scale-105"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent" />
              <figcaption className="absolute bottom-0 left-0 p-6">
                <div className="text-lg font-medium tracking-luxe">{s.title}</div>
                <div className="text-sm text-gray-300">{s.note}</div>
              </figcaption>
            </motion.figure>
          ))}
        </motion.div>
      </div>
    </section>
  )
}
