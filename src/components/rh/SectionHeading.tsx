import { motion } from 'framer-motion'
import { fadeUp, viewport } from '../../lib/motion'

export default function SectionHeading({
  eyebrow,
  title,
  description,
  align = 'left',
}: {
  eyebrow: string
  title: string
  description?: string
  align?: 'left' | 'center'
}) {
  return (
    <motion.div
      variants={fadeUp}
      initial="hidden"
      whileInView="show"
      viewport={viewport}
      className={`max-w-3xl ${align === 'center' ? 'mx-auto text-center' : ''}`}
    >
      <p className="mb-4 text-[11px] uppercase tracking-eyebrow text-gray-400">
        {eyebrow}
      </p>
      <h2 className="text-balance text-4xl font-semibold tracking-luxe sm:text-5xl md:text-6xl">
        {title}
      </h2>
      {description && (
        <p className="mt-5 text-base leading-relaxed text-gray-400 sm:text-lg">
          {description}
        </p>
      )}
    </motion.div>
  )
}
