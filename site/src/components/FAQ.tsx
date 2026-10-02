import type { ReactNode } from 'react'
import { links } from '../data/sample'
import { ChevronDownIcon } from './icons'
import { Reveal, Section } from './Section'

const faqs: Array<{ q: string; a: ReactNode }> = [
  {
    q: 'Is it really free?',
    a: (
      <>
        Yes. There's no price, no license key, no trial, and no paid tier. The source is on{' '}
        <a href={links.repo} className="text-accent underline-offset-2 hover:underline">
          GitHub
        </a>
        , and you can build it yourself.
      </>
    ),
  },
  {
    q: 'Why is there a Terminal step?',
    a: 'MoniMac isn’t notarized by Apple, because notarization requires a paid Apple developer account. macOS blocks un-notarized apps downloaded in a browser. The one-line install avoids that by downloading with curl; if you download the DMG by hand, the xattr command removes the “downloaded from the internet” flag once.',
  },
  {
    q: 'Will it slow my Mac down?',
    a: 'It’s built to stay under about 1% CPU at a 2-second refresh with the popover closed. Each reading is refreshed only as often as it changes, and the slow jobs (like measuring what fills your disk) run in the background every few hours. You can also pick a 5-second refresh.',
  },
  {
    q: 'Does it need admin rights or a helper?',
    a: 'No. MoniMac never asks for your password and installs no privileged helper. It only reads what macOS already lets your user account see.',
  },
  {
    q: 'Does it run on Intel Macs?',
    a: `No. MoniMac is built for Apple silicon (M1 and later) and needs macOS 14.2 or later.`,
  },
  {
    q: 'Can it control my fans?',
    a: 'No. Temperatures and fan speeds are read-only. MoniMac never writes to the hardware controller, so macOS stays fully in charge of cooling.',
  },
  {
    q: 'How do updates work?',
    a: 'Choose Check for Updates… in Settings, or let MoniMac check automatically. Each update is verified against the project’s signing key before it installs, and there’s no Terminal step. The check goes to GitHub, and it’s the only network request MoniMac makes.',
  },
  {
    q: 'How is it different from Activity Monitor?',
    a: 'Activity Monitor is great for a snapshot of processes. MoniMac lives in the menu bar, keeps history so you can see what happened ten minutes or ten days ago, rolls helper processes up into their apps, warns you when an app runs away, and adds battery health, Bluetooth batteries, temperatures, per-app volume, and your dev servers.',
  },
  {
    q: 'Where is my data stored?',
    a: 'In a local database in ~/Library/Application Support/MoniMac on your Mac. Nothing is uploaded, and there’s no account. Choose how many days of history to keep (7, 30, or 90) in Settings.',
  },
]

export function FAQ() {
  return (
    <Section id="faq" eyebrow="FAQ" title="Questions, answered." className="bg-page-alt">
      <Reveal className="mx-auto mt-12 max-w-3xl">
        <div className="divide-y divide-line overflow-hidden rounded-2xl border border-line bg-card">
          {faqs.map(({ q, a }) => (
            <details key={q} className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 text-[16px] font-medium text-ink transition-colors hover:bg-ink/[0.03] sm:px-6 [&::-webkit-details-marker]:hidden">
                {q}
                <ChevronDownIcon size={18} className="shrink-0 text-ink-3 transition-transform duration-200 group-open:rotate-180" />
              </summary>
              <div className="px-5 pb-5 text-[15px] leading-relaxed text-ink-2 sm:px-6">{a}</div>
            </details>
          ))}
        </div>
      </Reveal>
    </Section>
  )
}
