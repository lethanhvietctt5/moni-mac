import { installOneLiner, links, release, unquarantine } from '../data/sample'
import { CodeBlock } from './CodeBlock'
import { DownloadIcon, RefreshIcon, TerminalIcon } from './icons'
import { Reveal, Section } from './Section'

export function Install() {
  return (
    <Section
      id="install"
      eyebrow="Install"
      title="One line in Terminal."
      intro={`Paste this into Terminal. It downloads the latest release from GitHub, copies MoniMac to Applications, and opens it. Requires macOS ${release.minimumMacOS} or later on Apple silicon.`}
    >
      <div className="mx-auto mt-12 max-w-3xl space-y-10 sm:mt-14">
        <Reveal>
          <div className="mb-3 flex items-center gap-2 text-[15px] font-semibold text-ink">
            <TerminalIcon size={18} className="text-accent" />
            Install with Terminal
          </div>
          <CodeBlock label="Terminal" code={installOneLiner} />
          <p className="mt-3 text-[14px] leading-relaxed text-ink-3">
            It only talks to GitHub Releases. Files downloaded with <code className="font-mono text-[13px]">curl</code>{' '}
            aren't flagged as quarantined, so macOS opens the app without a warning.
          </p>
        </Reveal>

        <Reveal>
          <div className="mb-3 flex items-center gap-2 text-[15px] font-semibold text-ink">
            <DownloadIcon size={18} className="text-accent" />
            Or install by hand
          </div>
          <ol className="space-y-3 text-[15px] leading-relaxed text-ink-2">
            {[
              <>
                <a href={links.dmg} className="font-medium text-accent underline-offset-2 hover:underline">
                  Download MoniMac.dmg
                </a>{' '}
                from GitHub Releases and open it.
              </>,
              <>Drag MoniMac onto the Applications folder.</>,
              <>Run this once in Terminal, then open MoniMac:</>,
            ].map((step, i) => (
              <li key={i} className="flex gap-3">
                <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-accent/12 text-[13px] font-semibold text-accent">
                  {i + 1}
                </span>
                <span>{step}</span>
              </li>
            ))}
          </ol>
          <div className="mt-3 sm:pl-9">
            <CodeBlock label="Terminal" code={unquarantine} />
          </div>
          <p className="mt-3 text-[14px] leading-relaxed text-ink-3 sm:pl-9">
            MoniMac isn't notarized by Apple, so macOS blocks a copy downloaded in a browser until you remove the
            "downloaded from the internet" flag. That's what the command does.
          </p>
        </Reveal>

        <Reveal>
          <div className="flex gap-3 rounded-2xl border border-line bg-card p-5">
            <RefreshIcon size={20} className="mt-0.5 shrink-0 text-success" />
            <div>
              <div className="text-[15px] font-semibold text-ink">Updates take one click</div>
              <p className="mt-1 text-[15px] leading-relaxed text-ink-2">
                Choose <strong className="font-semibold text-ink">Check for Updates…</strong> in Settings, or let MoniMac check
                on its own. Updates are signature-checked and install without any Terminal step.
              </p>
            </div>
          </div>
        </Reveal>
      </div>
    </Section>
  )
}
