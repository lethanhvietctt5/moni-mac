import { links } from '../data/sample'
import { DownloadIcon } from './icons'

export function Footer() {
  return (
    <footer className="scheme-dark bg-[#07080c] text-ink">
      <div className="relative isolate overflow-hidden px-4 py-20 text-center sm:px-6">
        <div aria-hidden="true" className="absolute inset-x-0 top-0 -z-10 mx-auto h-72 max-w-3xl rounded-full bg-[radial-gradient(closest-side,rgba(46,155,255,0.28),transparent)] blur-2xl" />
        <img src="/icon-256.webp" alt="" width={72} height={72} className="mx-auto size-[72px]" />
        <p className="mt-6 text-[30px] font-semibold tracking-tight text-balance sm:text-[40px]">Know what your Mac is up to.</p>
        <a
          href={links.dmg}
          className="mt-7 inline-flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-[16px] font-medium text-white transition hover:bg-[#2a95ff]"
        >
          <DownloadIcon size={18} strokeWidth={2.2} />
          Download for Mac
        </a>
      </div>
      <div className="border-t border-white/[0.08]">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-5 px-4 py-8 text-[14px] sm:flex-row sm:px-6">
          <a href="#top" className="flex items-center gap-2 font-semibold">
            <img src="/icon-256.webp" alt="" width={22} height={22} className="size-[22px]" />
            MoniMac
          </a>
          <nav aria-label="Footer" className="sm:ml-auto">
            <ul className="flex flex-wrap justify-center gap-x-6 gap-y-2 text-ink-2">
              <li><a href={links.repo} className="hover:text-ink">GitHub</a></li>
              <li><a href={links.releases} className="hover:text-ink">Releases</a></li>
              <li><a href={links.issues} className="hover:text-ink">Report an issue</a></li>
            </ul>
          </nav>
          <span className="text-ink-3 sm:ml-6">Made for macOS</span>
        </div>
      </div>
    </footer>
  )
}
