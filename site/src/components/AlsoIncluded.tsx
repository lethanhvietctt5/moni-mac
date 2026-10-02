import {
  BatteryIcon,
  CpuIcon,
  HeadphonesIcon,
  HistoryIcon,
  PowerIcon,
  RefreshIcon,
  SpeakerIcon,
  ThermometerIcon,
  UnitsIcon,
  XCircleIcon,
} from './icons'
import { Reveal, Section } from './Section'

const features = [
  { icon: SpeakerIcon, color: 'var(--accent)', title: 'Per-app volume', body: 'Turn one app down or mute it, and duck the rest during calls.' },
  { icon: HeadphonesIcon, color: 'var(--network)', title: 'Bluetooth batteries', body: 'AirPods left, right, and case, plus keyboards, mice, and trackpads.' },
  { icon: ThermometerIcon, color: 'var(--temp)', title: 'Temperatures and fans', body: 'Every sensor and fan speed. Read-only: macOS stays in charge of the fans.' },
  { icon: BatteryIcon, color: 'var(--battery)', title: 'Battery health', body: 'Health against design capacity, cycle count, temperature, and power draw.' },
  { icon: HistoryIcon, color: 'var(--disk)', title: 'History from 12H to 30D', body: 'Peaks with the time and the app behind them, stored on your Mac.' },
  { icon: XCircleIcon, color: 'var(--danger)', title: 'Quit with confirmation', body: 'See what an app is running before you quit it, with Force Quit as a last resort.' },
  { icon: UnitsIcon, color: 'var(--gpu)', title: '°C or °F, MB/s or Mbps', body: 'Units that match what you’re used to, everywhere.' },
  { icon: CpuIcon, color: 'var(--cpu)', title: 'System or per-core CPU', body: '0–100% of the whole chip, or up to 100% per core. One setting for every surface.' },
  { icon: PowerIcon, color: 'var(--memory)', title: 'Launch at login', body: 'Start monitoring when your Mac does.' },
  { icon: RefreshIcon, color: 'var(--accent)', title: 'Check for Updates', body: 'New versions install from inside the app, verified before they run.' },
]

export function AlsoIncluded() {
  return (
    <Section eyebrow="Also included" title="The details add up." className="bg-page-alt">
      <ul className="mt-12 grid grid-cols-1 gap-px overflow-hidden rounded-2xl border border-line bg-line sm:mt-14 sm:grid-cols-2 lg:grid-cols-5">
        {features.map(({ icon: Icon, color, title, body }, i) => (
          <li key={title} className="bg-card">
            <Reveal delay={(i % 5) * 0.05} className="h-full p-5">
              <span
                className="flex size-9 items-center justify-center rounded-xl"
                style={{ color, background: `color-mix(in srgb, ${color} 14%, transparent)` }}
              >
                <Icon size={18} />
              </span>
              <h3 className="mt-3.5 text-[15px] font-semibold text-ink">{title}</h3>
              <p className="mt-1 text-[14px] leading-relaxed text-ink-2">{body}</p>
            </Reveal>
          </li>
        ))}
      </ul>
    </Section>
  )
}
