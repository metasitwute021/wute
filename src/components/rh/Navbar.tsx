import { useEffect, useState } from 'react'
import { Menu, X } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { MODEL } from '../../data/houseData'

const LINKS = [
  { label: 'Overview', href: '#overview' },
  { label: 'Floor Plans', href: '#floorplans' },
  { label: 'Exterior', href: '#exterior' },
  { label: 'Interior', href: '#interior' },
  { label: 'Specifications', href: '#specs' },
  { label: 'Gallery', href: '#gallery' },
]

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <>
      <motion.nav
        initial={{ y: -80, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
        className={`fixed top-0 inset-x-0 z-[100] transition-colors duration-500 ${
          scrolled ? 'glass' : 'bg-transparent'
        }`}
      >
        <div className="mx-auto max-w-[1400px] px-5 sm:px-8 h-16 sm:h-20 flex items-center justify-between">
          <a href="#top" className="flex items-baseline gap-2 group">
            <span className="text-lg sm:text-xl font-semibold tracking-luxe">
              {MODEL.code}
            </span>
            <span className="hidden sm:inline text-[10px] tracking-eyebrow text-gray-400 uppercase">
              Residence
            </span>
          </a>

          <div className="hidden lg:flex items-center gap-1">
            {LINKS.map((l) => (
              <a
                key={l.href}
                href={l.href}
                className="px-4 py-2 text-sm text-gray-300 hover:text-white transition-colors"
              >
                {l.label}
              </a>
            ))}
          </div>

          <div className="flex items-center gap-3">
            <a
              href="#contact"
              className="hidden sm:inline-flex items-center rounded-full bg-white text-black text-sm font-semibold px-5 py-2.5 hover:bg-gray-200 transition-colors"
            >
              Enquire
            </a>
            <button
              className="lg:hidden p-2 -mr-2"
              aria-label="Menu"
              onClick={() => setOpen((v) => !v)}
            >
              {open ? <X size={22} /> : <Menu size={22} />}
            </button>
          </div>
        </div>
      </motion.nav>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[99] lg:hidden glass-strong pt-20"
          >
            <div className="flex flex-col px-6 py-6 gap-1">
              {LINKS.map((l, i) => (
                <motion.a
                  key={l.href}
                  href={l.href}
                  onClick={() => setOpen(false)}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.05 * i }}
                  className="py-4 text-2xl font-light tracking-luxe border-b border-white/10"
                >
                  {l.label}
                </motion.a>
              ))}
              <a
                href="#contact"
                onClick={() => setOpen(false)}
                className="mt-6 inline-flex justify-center rounded-full bg-white text-black font-semibold py-3.5"
              >
                Enquire
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  )
}
