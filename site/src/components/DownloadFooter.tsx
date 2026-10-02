import { Download, Laptop, Tag } from 'lucide-react'
import { CHANGELOG_URL, DOWNLOAD_URL, MIN_MACOS, REPO_URL, VERSION } from '../site'
import { GithubIcon, Reveal } from './ui'

const footerLinks = [
  { label: 'Features', href: '#menu-bar' },
  { label: 'Changelog', href: CHANGELOG_URL },
  { label: 'GitHub', href: REPO_URL },
]

export function DownloadFooter() {
  return (
    <section id="download" className="bg-night px-6 pt-28 pb-12 lg:px-[120px] lg:pt-40">
      <Reveal className="mx-auto flex max-w-[760px] flex-col items-center gap-5 text-center">
        <p className="text-[13px] font-semibold tracking-[1.6px] text-snow-2">FREE &amp; OPEN SOURCE</p>
        <h2 className="text-[44px]/[48px] font-bold tracking-[-1.2px] text-snow sm:text-[64px]/[68px] sm:tracking-[-1.6px]">
          Your whole Mac,
          <br />
          one glance away.
        </h2>
        <p className="max-w-[600px] text-[18px]/[27px] text-snow-2 sm:text-[20px]/[29px]">
          MoniMac is free forever, built natively for Apple silicon, and lighter than the apps it keeps an eye on.
        </p>
        <div className="flex flex-col gap-3.5 pt-5 sm:flex-row">
          <a
            href={DOWNLOAD_URL}
            className="flex items-center justify-center gap-2.5 rounded-xl bg-accent px-7 py-4 text-[17px] font-semibold text-snow shadow-[0_8px_28px_#0a84ff33] transition-[filter,transform] hover:-translate-y-px hover:brightness-110"
          >
            <Download className="size-5" strokeWidth={2.25} />
            Download for macOS
          </a>
          <a
            href={REPO_URL}
            className="flex items-center justify-center gap-2.5 rounded-xl bg-night-raised px-6 py-4 text-[17px] font-semibold text-snow outline outline-night-line transition-[background-color] hover:bg-[#3a3a3c]"
          >
            <GithubIcon className="size-[18px]" />
            View on GitHub
          </a>
        </div>
        <ul className="flex flex-wrap justify-center gap-x-7 gap-y-2 pt-3 text-[14px] text-snow-2">
          <li className="flex items-center gap-2">
            <Tag className="size-[15px]" />
            Version {VERSION}
          </li>
          <li className="flex items-center gap-2">
            <Laptop className="size-[15px]" />
            {MIN_MACOS}
          </li>
        </ul>
      </Reveal>

      <footer className="mx-auto mt-28 flex max-w-[1200px] flex-col gap-8 lg:mt-36">
        <div className="h-px bg-night-line" />
        <div className="flex flex-col items-center gap-6 text-[14px] text-snow-2 sm:flex-row sm:justify-between">
          <span className="flex items-center gap-2 text-[16px] font-semibold tracking-[-0.2px] text-snow">
            <img src="/icon-256.webp" alt="" width={20} height={20} className="size-5" />
            MoniMac
          </span>
          <ul className="flex gap-8">
            {footerLinks.map((l) => (
              <li key={l.label}>
                <a href={l.href} className="transition-colors hover:text-snow">
                  {l.label}
                </a>
              </li>
            ))}
          </ul>
          <span>© 2026 MoniMac</span>
        </div>
      </footer>
    </section>
  )
}
