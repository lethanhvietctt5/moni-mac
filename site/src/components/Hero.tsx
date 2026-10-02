import { m } from 'motion/react'
import { links, release } from '../data/sample'
import { useLiveTick } from '../hooks/useLiveTick'
import { DownloadIcon, GitHubIcon } from './icons'
import { MenuBar } from './MenuBar'
import { Popover } from './Popover'

const ease = [0.22, 1, 0.36, 1] as const

export function Hero() {
  const [ref, tick] = useLiveTick<HTMLDivElement>(2000)

  return (
    <section id="top" aria-labelledby="hero-title" className="scheme-dark relative isolate overflow-hidden bg-[#07080c] text-ink">
      {/* Soft glow in the icon's blues */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute top-[-18%] left-1/2 h-[720px] w-[1100px] max-w-[180vw] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(46,155,255,0.38),rgba(29,91,255,0.16)_55%,transparent)] blur-2xl" />
        <div className="absolute top-[38%] left-[12%] h-[420px] w-[520px] rounded-full bg-[radial-gradient(closest-side,rgba(94,225,255,0.14),transparent)] blur-2xl" />
        <div className="absolute top-[30%] right-[6%] h-[460px] w-[560px] rounded-full bg-[radial-gradient(closest-side,rgba(64,76,255,0.18),transparent)] blur-2xl" />
        <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-b from-transparent to-[#07080c]" />
      </div>

      <div className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 sm:pt-38 sm:pb-28">
        <m.div
          className="mx-auto max-w-3xl text-center"
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease }}
        >
          <img
            src="/icon-256.webp"
            alt="MoniMac app icon"
            width={112}
            height={112}
            className="mx-auto mb-7 size-24 drop-shadow-[0_18px_40px_rgba(30,110,255,0.55)] sm:size-28"
          />
          <h1 id="hero-title" className="text-[42px] leading-[1.04] font-semibold tracking-[-0.025em] text-balance sm:text-[64px] lg:text-[72px]">
            See what your Mac is{' '}
            <span className="bg-gradient-to-r from-[#5ee1ff] via-[#3d9bff] to-[#6f7bff] bg-clip-text text-transparent">really doing.</span>
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-[18px] leading-relaxed text-pretty text-ink-2 sm:text-[20px]">
            MoniMac is a free, open-source system monitor that lives in your menu bar and opens into a full window,
            with history to scroll back through and every number broken down by app.
          </p>
          <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <a
              href={links.dmg}
              className="flex w-full items-center justify-center gap-2 rounded-full bg-accent px-6 py-3 text-[16px] font-medium text-white shadow-[0_8px_30px_-6px_rgba(10,132,255,0.7)] transition hover:bg-[#2a95ff] sm:w-auto"
            >
              <DownloadIcon size={18} strokeWidth={2.2} />
              Download for Mac
            </a>
            <a
              href={links.repo}
              className="flex w-full items-center justify-center gap-2 rounded-full border border-white/15 bg-white/[0.06] px-6 py-3 text-[16px] font-medium text-ink transition hover:bg-white/10 sm:w-auto"
            >
              <GitHubIcon size={18} />
              View on GitHub
            </a>
          </div>
          <p className="mt-4 text-[13px] text-ink-3">
            Free · v{release.version} · macOS {release.minimumMacOS}+ · Apple silicon
          </p>
        </m.div>

        {/* A desktop with MoniMac in the menu bar and its popover open */}
        <m.div
          ref={ref}
          className="relative mx-auto mt-14 max-w-5xl sm:mt-20"
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 0.15, ease }}
        >
          <div
            role="img"
            aria-label="Illustration: the macOS menu bar with MoniMac showing CPU, memory, and network, and its popover listing every metric and the busiest apps. Values are simulated."
            className="bg-wallpaper relative h-[600px] overflow-hidden rounded-[18px] border border-white/10 shadow-[0_40px_120px_-30px_rgba(20,90,255,0.55)] sm:h-[620px]"
          >
            <MenuBar metrics={['cpu', 'memory', 'network']} style="both" tick={tick} activeMetric="cpu" className="pr-3" compactClock />
            <m.div
              className="absolute top-[38px] right-1/2 translate-x-1/2 origin-top md:right-[300px] md:translate-x-0"
              initial={{ opacity: 0, scale: 0.92, y: -10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              transition={{ type: 'spring', stiffness: 260, damping: 22, delay: 0.9 }}
            >
              <Popover tick={tick} className="w-[340px] max-w-[calc(100vw-56px)]" />
            </m.div>
          </div>
        </m.div>
      </div>
    </section>
  )
}
