import { Eye, Layers, RotateCcw } from 'lucide-react'
import { Container, Reveal, SectionHeader, Shot } from './ui'

// The four rules and their defaults, as AlertRules.swift defines them.
const rules = [
  { color: '#409cff', signal: 'CPU', rule: 'One app stays above your threshold for 2 minutes' },
  { color: '#bf5af2', signal: 'Memory', rule: 'An app grows fast — +1 GB in 10 minutes may be a leak' },
  { color: '#7d7aff', signal: 'Disk', rule: 'Sustained heavy writes to your drive' },
  { color: '#40c8e0', signal: 'Network', rule: 'Heavy uploads running in the background' },
]

const quitPoints = [
  { icon: Layers, text: 'Helpers are included, so nothing lingers' },
  { icon: Eye, text: 'See exactly what will close, and what it frees' },
  { icon: RotateCcw, text: 'Asks apps to quit normally so you can save' },
]

function Step({ number, label }: { number: string; label: string }) {
  return (
    <p className="text-[14px] font-medium tracking-[0.4px] text-snow-3">
      {number}&nbsp;&nbsp;{label}
    </p>
  )
}

export function AlertsSection() {
  return (
    <section id="alerts" className="bg-night py-24 lg:py-36">
      <Container className="flex flex-col gap-20 lg:gap-28">
        <SectionHeader dark eyebrow="Smart Alerts" title="Hear from your Mac before it slows down.">
          MoniMac watches quietly in the menu bar and only speaks up when something is actually wrong — and when it
          does, the fix is one click away.
        </SectionHeader>

        <div className="flex flex-col gap-12 lg:flex-row lg:items-center lg:gap-16">
          <Reveal className="flex flex-1 flex-col gap-4">
            <Step number="01" label="Notice" />
            <h3 className="text-[28px]/[34px] font-semibold tracking-[-0.6px] text-snow sm:text-[32px]/[38px]">
              Four signals, measured over time — not spikes.
            </h3>
            <p className="text-[17px]/[26px] text-snow-2">
              A single busy second isn't a problem. MoniMac waits until a pattern holds, so the alerts you get are the
              ones worth reading.
            </p>
            <ul className="pt-4">
              {rules.map(({ color, signal, rule }) => (
                <li
                  key={signal}
                  className="flex items-center gap-4 border-t border-night-line py-4 text-[15px] last:border-b"
                >
                  <span className="size-2 shrink-0 rounded-full" style={{ background: color }} />
                  <span className="w-[72px] shrink-0 font-semibold text-snow sm:w-[88px]">{signal}</span>
                  <span className="text-snow-2">{rule}</span>
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal className="lg:w-[560px] lg:shrink-0" delay={0.1}>
            <Shot
              name="alerts"
              width={560}
              height={547}
              className="w-full rounded-xl"
              alt="Four MoniMac notifications: Xcode using a lot of CPU, Google Chrome memory growing fast, heavy disk writes from Photos, and Dropbox uploading heavily."
            />
          </Reveal>
        </div>

        <div className="flex flex-col gap-12 lg:flex-row lg:items-center lg:gap-16">
          <Reveal className="flex flex-1 flex-col gap-4">
            <Step number="02" label="Act" />
            <h3 className="text-[28px]/[34px] font-semibold tracking-[-0.6px] text-snow sm:text-[32px]/[38px]">
              Quit the app — and everything it left running.
            </h3>
            <p className="text-[17px]/[26px] text-snow-2">
              Act right from the notification. Before anything closes, a confirmation sheet lists the app and every
              helper process, with the CPU and memory each one is using.
            </p>
            <ul className="flex flex-col gap-3.5 pt-4">
              {quitPoints.map(({ icon: Icon, text }) => (
                <li key={text} className="flex items-center gap-3 text-[15px] text-snow">
                  <Icon className="size-[18px] shrink-0 text-snow-2" />
                  {text}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal className="lg:w-[640px] lg:shrink-0" delay={0.1}>
            <Shot
              name="quit-sheet"
              width={641}
              height={481}
              className="w-full rounded-xl"
              alt="MoniMac's quit sheet over the Processes list: it lists the app and each helper process with its CPU and memory, with Cancel and Quit buttons."
            />
          </Reveal>
        </div>
      </Container>
    </section>
  )
}
