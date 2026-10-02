import { AnimatePresence, m } from 'motion/react'
import { useEffect, useState } from 'react'
import { links } from '../data/sample'
import { CloseIcon, DownloadIcon, GitHubIcon, MenuIcon } from './icons'

const sections = [
  { href: '#features', label: 'Features' },
  { href: '#developers', label: 'Developers' },
  { href: '#privacy', label: 'Privacy' },
  { href: '#install', label: 'Install' },
  { href: '#faq', label: 'FAQ' },
]

export function Nav() {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  return (
    <header className="scheme-dark sticky top-0 z-50 border-b border-white/[0.08] bg-[#0c0c10]/75 text-ink backdrop-blur-xl backdrop-saturate-150">
      <nav aria-label="Main" className="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4 sm:px-6">
        <a href="#top" className="flex items-center gap-2 font-semibold tracking-tight">
          <img src="/icon-256.webp" alt="" width={28} height={28} className="size-7" />
          <span>MoniMac</span>
        </a>

        <ul className="ml-6 hidden items-center gap-1 text-[14px] text-ink-2 md:flex">
          {sections.map((s) => (
            <li key={s.href}>
              <a href={s.href} className="rounded-md px-3 py-1.5 transition-colors hover:text-ink">
                {s.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="ml-auto flex items-center gap-2">
          <a
            href={links.repo}
            className="flex size-9 items-center justify-center rounded-lg text-ink-2 transition-colors hover:bg-white/10 hover:text-ink"
            aria-label="MoniMac on GitHub"
          >
            <GitHubIcon size={19} />
          </a>
          <a
            href={links.dmg}
            className="hidden items-center gap-1.5 rounded-full bg-accent px-4 py-1.5 text-[14px] font-medium text-white transition-colors hover:bg-[#2a95ff] sm:flex"
          >
            <DownloadIcon size={15} strokeWidth={2.2} />
            Download
          </a>
          <button
            type="button"
            className="flex size-9 items-center justify-center rounded-lg text-ink-2 hover:bg-white/10 hover:text-ink md:hidden"
            aria-expanded={open}
            aria-controls="mobile-menu"
            aria-label={open ? 'Close menu' : 'Open menu'}
            onClick={() => setOpen((o) => !o)}
          >
            {open ? <CloseIcon size={20} /> : <MenuIcon size={20} />}
          </button>
        </div>
      </nav>

      <AnimatePresence initial={false}>
        {open && (
          <m.div
            id="mobile-menu"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.22 }}
            className="overflow-hidden border-t border-white/[0.08] md:hidden"
          >
            <ul className="space-y-1 px-4 py-3">
              {sections.map((s) => (
                <li key={s.href}>
                  <a
                    href={s.href}
                    onClick={() => setOpen(false)}
                    className="block rounded-lg px-3 py-2.5 text-[15px] text-ink-2 hover:bg-white/5 hover:text-ink"
                  >
                    {s.label}
                  </a>
                </li>
              ))}
              <li className="pt-2">
                <a
                  href={links.dmg}
                  className="flex items-center justify-center gap-2 rounded-xl bg-accent px-4 py-3 text-[15px] font-medium text-white"
                >
                  <DownloadIcon size={16} strokeWidth={2.2} />
                  Download for Mac
                </a>
              </li>
            </ul>
          </m.div>
        )}
      </AnimatePresence>
    </header>
  )
}
