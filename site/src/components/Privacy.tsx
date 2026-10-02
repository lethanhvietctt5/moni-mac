import { HandIcon, LockIcon, ShieldIcon } from './icons'
import { Reveal, Section } from './Section'

const cards = [
  {
    icon: LockIcon,
    title: 'Everything stays on your Mac',
    body: 'History lives in a local database on your Mac. There is no account and no analytics. The only network request MoniMac makes is the update check against GitHub.',
  },
  {
    icon: ShieldIcon,
    title: 'No admin rights, no helper',
    body: 'MoniMac reads what macOS already exposes to your user. It never asks for your password, installs no privileged helper, and never writes to the hardware controller.',
  },
  {
    icon: HandIcon,
    title: 'Permissions only when you need them',
    body: 'Location (for the Wi-Fi name), notifications, and audio capture (for per-app volume) are asked for the first time you use a feature that needs them, never at launch.',
  },
]

export function Privacy() {
  return (
    <Section
      id="privacy"
      eyebrow="Privacy"
      title="Your Mac's business stays your business."
      intro="A system monitor sees a lot. MoniMac keeps all of it on your machine."
    >
      <div className="mt-12 grid grid-cols-1 gap-4 sm:mt-16 md:grid-cols-3">
        {cards.map(({ icon: Icon, title, body }, i) => (
          <Reveal key={title} delay={i * 0.08} className="rounded-2xl border border-line bg-card p-6">
            <span className="flex size-10 items-center justify-center rounded-xl bg-success/12 text-success">
              <Icon size={20} />
            </span>
            <h3 className="mt-4 text-[18px] font-semibold text-ink">{title}</h3>
            <p className="mt-2 text-[15px] leading-relaxed text-ink-2">{body}</p>
          </Reveal>
        ))}
      </div>
      <Reveal>
        <p className="mt-8 text-center text-[14px] text-ink-3">This website is the same: no trackers, no analytics, no cookies, and nothing loaded from other servers.</p>
      </Reveal>
    </Section>
  )
}
