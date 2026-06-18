import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { TransformWrapper, TransformComponent } from 'react-zoom-pan-pinch'
import { ZoomIn, ZoomOut, Maximize2 } from 'lucide-react'
import SectionHeading from './SectionHeading'
import { fadeUp, viewport } from '../../lib/motion'
import {
  GROUND_ROOMS,
  SECOND_ROOMS,
  THIRD_ROOMS,
  roomArea,
  type Room,
} from '../../data/houseData'
import groundImg from '../../assets/floor-ground.webp'
import secondImg from '../../assets/floor-second.webp'
import thirdImg from '../../assets/floor-third.webp'

const FLOORS = [
  { id: 'ground', label: 'Ground Floor', img: groundImg, rooms: GROUND_ROOMS },
  { id: 'second', label: 'Second Floor', img: secondImg, rooms: SECOND_ROOMS },
  { id: 'third', label: 'Third Floor', img: thirdImg, rooms: THIRD_ROOMS },
]

export default function FloorPlans() {
  const [active, setActive] = useState(0)
  const [hovered, setHovered] = useState<string | null>(null)
  const floor = FLOORS[active]
  const floorArea = floor.rooms.reduce((s, r) => s + roomArea(r), 0)

  return (
    <section id="floorplans" className="border-t border-white/10 bg-black">
      <div className="mx-auto max-w-[1400px] px-5 py-24 sm:px-8 sm:py-32">
        <SectionHeading
          eyebrow="Architecture"
          title="Interactive floor plans"
          description="Pinch, scroll or use the controls to zoom into any level. Hover a room to highlight it — every name and dimension is taken from the construction drawings."
        />

        {/* Tabs */}
        <div className="mt-12 flex flex-wrap gap-2">
          {FLOORS.map((f, i) => (
            <button
              key={f.id}
              onClick={() => {
                setActive(i)
                setHovered(null)
              }}
              className={`rounded-full border px-5 py-2.5 text-sm font-medium transition-all ${
                i === active
                  ? 'border-white bg-white text-black'
                  : 'border-white/20 text-gray-300 hover:border-white/50 hover:text-white'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>

        <div className="mt-8 grid gap-8 lg:grid-cols-[1.5fr_1fr]">
          {/* Zoomable plan */}
          <AnimatePresence mode="wait">
            <motion.div
              key={floor.id}
              initial={{ opacity: 0, scale: 0.99 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
              className="relative overflow-hidden rounded-3xl border border-white/15 bg-white"
            >
              <TransformWrapper
                initialScale={1}
                minScale={1}
                maxScale={5}
                doubleClick={{ mode: 'zoomIn' }}
                wheel={{ step: 0.15 }}
              >
                {({ zoomIn, zoomOut, resetTransform }) => (
                  <>
                    <div className="absolute right-3 top-3 z-20 flex flex-col gap-2">
                      {[
                        { icon: ZoomIn, fn: () => zoomIn(), label: 'Zoom in' },
                        { icon: ZoomOut, fn: () => zoomOut(), label: 'Zoom out' },
                        { icon: Maximize2, fn: () => resetTransform(), label: 'Reset' },
                      ].map(({ icon: Icon, fn, label }) => (
                        <button
                          key={label}
                          onClick={fn}
                          aria-label={label}
                          className="grid h-9 w-9 place-items-center rounded-full bg-black/80 text-white backdrop-blur transition-colors hover:bg-black"
                        >
                          <Icon size={16} />
                        </button>
                      ))}
                    </div>
                    <TransformComponent
                      wrapperStyle={{ width: '100%', height: '100%' }}
                      contentStyle={{ width: '100%' }}
                    >
                      <img
                        src={floor.img}
                        alt={`${floor.label} plan`}
                        className="w-full select-none"
                        draggable={false}
                      />
                    </TransformComponent>
                  </>
                )}
              </TransformWrapper>
              <div className="pointer-events-none absolute bottom-3 left-3 rounded-full bg-black/80 px-3 py-1 text-[11px] uppercase tracking-eyebrow text-white">
                {floor.label}
              </div>
            </motion.div>
          </AnimatePresence>

          {/* Room schedule */}
          <motion.div
            variants={fadeUp}
            initial="hidden"
            whileInView="show"
            viewport={viewport}
          >
            <div className="flex items-baseline justify-between border-b border-white/15 pb-4">
              <h3 className="text-lg font-medium">Room Schedule</h3>
              <span className="text-sm text-gray-400">
                {floor.rooms.length} spaces · {floorArea.toFixed(1)} m²
              </span>
            </div>
            <ul className="mt-2 max-h-[460px] overflow-auto pr-1">
              {floor.rooms.map((r: Room) => (
                <li
                  key={r.name}
                  onMouseEnter={() => setHovered(r.name)}
                  onMouseLeave={() => setHovered(null)}
                  className={`flex items-center justify-between rounded-xl border px-4 py-3 transition-all ${
                    hovered === r.name
                      ? 'border-white/40 bg-white/[0.06]'
                      : 'border-transparent'
                  }`}
                >
                  <div>
                    <div className="text-sm font-medium text-white">{r.name}</div>
                    <div className="text-xs text-gray-500">
                      {r.w} × {r.l} m{r.note ? ` · ${r.note}` : ''}
                    </div>
                  </div>
                  <div className="text-sm tabular-nums text-gray-300">
                    {roomArea(r).toFixed(2)} m²
                  </div>
                </li>
              ))}
            </ul>
          </motion.div>
        </div>
      </div>
    </section>
  )
}
