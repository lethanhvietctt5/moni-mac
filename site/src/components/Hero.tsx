import { Download } from 'lucide-react'
import { motion } from 'motion/react'
import { DOWNLOAD_URL, MIN_MACOS, REPO_URL, VERSION } from '../site'
import { GithubIcon } from './ui'

const ease = [0.22, 1, 0.36, 1] as const

export function Hero() {
  const rise = (delay: number) => ({
    initial: { opacity: 0, y: 20 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.8, delay, ease },
  })

  return (
    <section id="top" className="overflow-x-clip bg-gradient-to-b from-white to-sidebar">
      <div className="flex flex-col items-center gap-7 px-6 pt-[136px] text-center sm:pt-[160px]">
        <motion.a
          {...rise(0)}
          href={`${REPO_URL}/releases`}
          className="flex items-center gap-2 rounded-full bg-white py-1.5 pr-3.5 pl-2.5 text-[14px] font-medium text-ink-2 outline outline-line transition-colors hover:text-ink"
        >
          <span className="relative flex size-2">
            <span className="absolute inset-0 animate-ping rounded-full bg-[#34c759] opacity-60 motion-reduce:hidden" />
            <span className="relative size-2 rounded-full bg-[#34c759]" />
          </span>
          Free &amp; open source · v{VERSION}
        </motion.a>

        <motion.h1
          {...rise(0.08)}
          className="max-w-[960px] text-[44px]/[48px] font-bold tracking-[-1.4px] text-balance sm:text-[60px]/[64px] sm:tracking-[-2px] lg:text-[76px]/[79px] lg:tracking-[-2.6px]"
        >
          Never wonder why your Mac is slow again.
        </motion.h1>

        <motion.p {...rise(0.16)} className="max-w-[640px] text-[18px]/[28px] text-ink-2 sm:text-[20px]/[30px]">
          MoniMac is a free system monitor for macOS. It keeps CPU, memory, network, battery and temperature one
          glance away in your menu bar — and tells you the moment an app starts dragging your Mac down.
        </motion.p>

        <motion.div {...rise(0.24)} className="flex flex-col items-center gap-7">
          <div className="flex flex-col gap-3.5 pt-2 sm:flex-row">
            <a
              href={DOWNLOAD_URL}
              className="flex items-center justify-center gap-2.5 rounded-xl bg-accent px-7 py-4 text-[17px] font-semibold text-white shadow-[0_8px_24px_#0a84ff40] transition-[filter,transform] hover:-translate-y-px hover:brightness-110"
            >
              <Download className="size-5" strokeWidth={2.25} />
              Download for macOS
            </a>
            <a
              href={REPO_URL}
              className="flex items-center justify-center gap-2.5 rounded-xl bg-white px-6 py-4 text-[17px] font-semibold outline outline-line transition-[background-color] hover:bg-mist"
            >
              <GithubIcon className="size-[18px]" />
              View on GitHub
            </a>
          </div>
          <p className="text-[14px] text-ink-3">
            Native for Apple silicon · {MIN_MACOS} · Under 10 MB
          </p>
        </motion.div>
      </div>

      {/* The scene image carries its shadow in a 120 pt margin on every side (9.375% of the
          1280 pt scene), so negative margins put the scene itself on the column. */}
      <div className="px-6 pt-14 pb-16 sm:px-10 lg:px-20 lg:pt-[72px] lg:pb-24">
        <motion.div
          className="mx-auto max-w-[1280px]"
          initial={{ opacity: 0, y: 48, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 1.1, delay: 0.35, ease }}
        >
          <img
            src="/shots/hero.webp"
            alt="MoniMac in the macOS menu bar: CPU 32%, memory 11.2 GB and network 2.4 MB/s, with the popover open over the Overview window."
            width={1520}
            height={940}
            fetchPriority="high"
            draggable={false}
            className="-mx-[9.375%] -my-[9.375%] block h-auto w-[118.75%] max-w-none select-none"
          />
        </motion.div>
      </div>
    </section>
  )
}
