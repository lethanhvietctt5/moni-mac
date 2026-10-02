import { m } from 'motion/react'
import { useState } from 'react'
import { notifications } from '../data/sample'
import { Notification } from './Notification'
import { Reveal, Section } from './Section'
import { ShareCard } from './ShareCard'

export function Alerts() {
  const [variant, setVariant] = useState<'light' | 'dark'>('light')

  return (
    <>
      <Section
        eyebrow="Alerts"
        title="Hear about it while it's happening."
        intro="When one app keeps the CPU busy, grows its memory fast, or hammers the disk, MoniMac sends a notification that says who and how much. Quit the app right from the banner, or open MoniMac on it. One alert per problem, not one a minute."
      >
        <div className="mt-12 grid grid-cols-1 items-center gap-10 sm:mt-16 lg:grid-cols-2">
          <div
            role="img"
            aria-label="Illustration: three MoniMac notifications. Xcode is using a lot of CPU, with Quit Xcode and Show buttons; Google Chrome memory is growing fast; heavy disk writes from Photos."
            className="relative overflow-hidden rounded-2xl border border-line p-5 sm:p-8"
            style={{ background: 'var(--wallpaper)' }}
          >
            <div className="flex flex-col items-end gap-3">
              {notifications.map((n, i) => (
                <m.div
                  key={n.title}
                  className="w-full max-w-[400px]"
                  initial={{ opacity: 0, x: 60 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true, amount: 0.6 }}
                  transition={{ type: 'spring', stiffness: 220, damping: 24, delay: i * 0.18 }}
                >
                  <Notification {...n} />
                </m.div>
              ))}
            </div>
          </div>
          <Reveal>
            <dl className="grid grid-cols-1 gap-6 sm:grid-cols-2">
              {[
                ['CPU', 'One app keeping most of a core busy for 2 minutes.'],
                ['Memory', 'An app growing by 1 GB within 10 minutes.'],
                ['Disk', 'More than 10 GB written in an hour.'],
                ['Network and Bluetooth', 'Sustained heavy traffic (off by default), and devices dropping below 20%.'],
              ].map(([title, body]) => (
                <div key={title} className="border-l-2 border-accent/60 pl-4">
                  <dt className="text-[16px] font-semibold text-ink">{title}</dt>
                  <dd className="mt-1 text-[15px] leading-relaxed text-ink-2">{body}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-6 text-[14px] text-ink-3">Defaults shown. Every rule can be turned off or given its own threshold in Settings.</p>
          </Reveal>
        </div>
      </Section>

      <Section
        eyebrow="Weekly card"
        title="Your week, on one card."
        intro="A 1200 × 630 summary of the last seven days: uptime, throttling, averages and peaks, and the app that did the most. Copy it or save it as an image, in light or dark."
        className="pt-0 sm:pt-0"
      >
        <Reveal className="mx-auto mt-10 max-w-4xl">
          <div className="mb-5 flex justify-center">
            <div role="group" aria-label="Card appearance" className="inline-flex rounded-xl border border-line bg-card p-1">
              {(['light', 'dark'] as const).map((v) => (
                <button
                  key={v}
                  type="button"
                  aria-pressed={variant === v}
                  onClick={() => setVariant(v)}
                  className={`rounded-lg px-5 py-1.5 text-[14px] font-medium capitalize transition-colors ${
                    variant === v ? 'bg-accent text-white' : 'text-ink-2 hover:text-ink'
                  }`}
                >
                  {v}
                </button>
              ))}
            </div>
          </div>
          <div role="img" aria-label={`Illustration: the weekly share card, ${variant} version, with sample data.`}>
            <ShareCard variant={variant} />
          </div>
        </Reveal>
      </Section>
    </>
  )
}
