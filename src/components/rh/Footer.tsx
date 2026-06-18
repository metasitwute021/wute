import { MODEL } from '../../data/houseData'

export default function Footer() {
  return (
    <footer className="border-t border-white/10">
      <div className="mx-auto flex max-w-[1400px] flex-col gap-6 px-5 py-12 sm:flex-row sm:items-center sm:justify-between sm:px-8">
        <div>
          <div className="text-lg font-semibold tracking-luxe">{MODEL.code}</div>
          <div className="text-sm text-gray-500">
            {MODEL.builder} · {MODEL.standard} standard
          </div>
        </div>
        <p className="max-w-md text-xs leading-relaxed text-gray-600">
          Renderings and 3D imagery are for illustration. Colours, materials and
          finishes follow the signed contract documents. Specification effective{' '}
          {MODEL.effective}.
        </p>
        <div className="text-xs text-gray-600">
          © {new Date().getFullYear()} {MODEL.builder}
        </div>
      </div>
    </footer>
  )
}
