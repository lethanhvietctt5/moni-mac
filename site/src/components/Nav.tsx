import { Menu, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { CHANGELOG_URL, DOWNLOAD_URL, REPO_URL } from '../site'
import { GithubIcon } from './ui'

const links = [
  { label: 'Menu Bar', href: '#menu-bar' },
  { label: 'Metrics', href: '#metrics' },
  { label: 'Alerts', href: '#alerts' },
  { label: 'Developers', href: '#developers' },
  { label: 'Changelog', href: CHANGELOG_URL },
]

export function Nav() {
  const [open, setOpen] = useState(false)
  // Transparent over the hero; frosted once the page scrolls under it.
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 border-b transition-[background-color,border-color,backdrop-filter] duration-300 ${
        scrolled || open
          ? 'border-black/[0.06] bg-white/75 backdrop-blur-xl backdrop-saturate-150'
          : 'border-transparent bg-transparent'
      }`}
    >
      <nav className="mx-auto flex h-[72px] max-w-[1440px] items-center justify-between px-6 lg:px-16">
        <a href="#top" className="flex items-center gap-2.5 lg:w-[220px]" onClick={() => setOpen(false)}>
          <img src="/icon-256.webp" alt="" width={30} height={30} className="size-[30px]" />
          <span className="text-[18px] font-semibold tracking-[-0.3px]">MoniMac</span>
        </a>

        <ul className="hidden items-center gap-9 md:flex">
          {links.map((l) => (
            <li key={l.label}>
              <a href={l.href} className="text-[14px] font-medium text-ink-2 transition-colors hover:text-ink">
                {l.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="flex items-center justify-end gap-5 lg:w-[220px]">
          <a
            href={REPO_URL}
            className="hidden items-center gap-1.5 text-[14px] font-medium transition-opacity hover:opacity-70 sm:flex"
          >
            <GithubIcon />
            GitHub
          </a>
          <a
            href={DOWNLOAD_URL}
            className="rounded-lg bg-accent px-4 py-2 text-[14px] font-semibold text-white transition-[filter] hover:brightness-110"
          >
            Download
          </a>
          <button
            type="button"
            className="-mr-2 p-2 md:hidden"
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            onClick={() => setOpen(!open)}
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
      </nav>

      {open && (
        <ul className="flex flex-col gap-1 px-6 pb-5 md:hidden">
          {[...links, { label: 'GitHub', href: REPO_URL }].map((l) => (
            <li key={l.label}>
              <a
                href={l.href}
                className="block py-2 text-[16px] font-medium text-ink-2"
                onClick={() => setOpen(false)}
              >
                {l.label}
              </a>
            </li>
          ))}
        </ul>
      )}
    </header>
  )
}
