import { links } from '../data/sample'
import { GitHubIcon, LeafIcon } from './icons'
import { Reveal, Section } from './Section'

export function OpenSource() {
  return (
    <Section eyebrow="Free and open source" title="No price tag. No catch." className="bg-page-alt">
      <div className="mt-12 grid grid-cols-1 gap-4 sm:mt-16 md:grid-cols-2">
        <Reveal className="relative overflow-hidden rounded-3xl border border-line bg-card p-7 sm:p-9">
          <div aria-hidden="true" className="absolute -top-24 -right-24 size-64 rounded-full bg-[radial-gradient(closest-side,rgba(10,132,255,0.22),transparent)]" />
          <div className="text-[13px] font-semibold tracking-wide text-accent uppercase">Free</div>
          <div className="mt-2 text-[52px] leading-none font-semibold tracking-tight text-ink">$0</div>
          <p className="mt-4 text-[16px] leading-relaxed text-ink-2">
            No payment, no license key, no trial, no account. The full source is on GitHub: read it, build it yourself, or
            open an issue.
          </p>
          <a
            href={links.repo}
            className="mt-6 inline-flex items-center gap-2 rounded-full border border-line px-4 py-2 text-[14px] font-medium text-ink transition-colors hover:bg-ink/5"
          >
            <GitHubIcon size={16} />
            Browse the source
          </a>
        </Reveal>
        <Reveal delay={0.08} className="relative overflow-hidden rounded-3xl border border-line bg-card p-7 sm:p-9">
          <div aria-hidden="true" className="absolute -top-24 -right-24 size-64 rounded-full bg-[radial-gradient(closest-side,rgba(52,199,89,0.2),transparent)]" />
          <div className="flex items-center gap-1.5 text-[13px] font-semibold tracking-wide text-success uppercase">
            <LeafIcon size={15} />
            Light
          </div>
          <div className="mt-2 text-[52px] leading-none font-semibold tracking-tight text-ink">
            &lt;1<span className="text-[32px]">% CPU</span>
          </div>
          <p className="mt-4 text-[16px] leading-relaxed text-ink-2">
            Built to stay under about 1% CPU at a 2-second refresh with the popover closed. A monitor shouldn't be the thing
            slowing your Mac down. Each reading is refreshed only as often as it changes.
          </p>
        </Reveal>
      </div>
    </Section>
  )
}
