import { BatteryMedium, Bluetooth, SquareTerminal, Thermometer, Volume2 } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'
import { Container, Reveal, Shot } from './ui'

/** A device tile: title and blurb, then a crop of that tab's window running off the bottom. */
function Tile({
  icon: Icon,
  color,
  title,
  children,
  shot,
  wide,
  alt,
  delay,
}: {
  icon: LucideIcon
  color: string
  title: string
  children: ReactNode
  shot: string
  wide: boolean
  alt: string
  delay?: number
}) {
  return (
    <Reveal delay={delay} className={`min-w-0 ${wide ? 'lg:flex-1' : 'lg:w-[420px] lg:shrink-0'}`}>
      <div className="flex h-full flex-col gap-8 overflow-hidden rounded-3xl bg-mist px-6 pt-10 sm:px-11 lg:h-[560px]">
        <div className="flex flex-col gap-2.5">
          <h3 className="flex items-center gap-2.5 text-[22px] font-semibold tracking-[-0.3px]">
            <Icon className="size-[22px]" style={{ color }} />
            {title}
          </h3>
          <p className="max-w-[480px] text-[16px]/[24px] text-ink-2">{children}</p>
        </div>
        <Shot
          name={shot}
          width={wide ? 672 : 332}
          height={wide ? 403 : 379}
          alt={alt}
          className="mt-auto w-full lg:mt-0"
        />
      </div>
    </Reveal>
  )
}

const stacks = ['Next.js', 'Vite', 'Docker', 'FastAPI']

export function DevicesSection() {
  return (
    <section id="devices" className="bg-white pt-24 lg:pt-40">
      <Container className="flex flex-col gap-12 lg:gap-[72px]">
        <Reveal className="flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
          <div className="flex max-w-[720px] flex-col gap-5">
            <p className="text-[15px] font-semibold text-ink-2">Devices &amp; Developer</p>
            <h2 className="text-[36px]/[40px] font-semibold tracking-[-1px] sm:text-[44px]/[48px] lg:text-[52px]/[56px] lg:tracking-[-1.4px]">
              Everything around your Mac. And everything running on it.
            </h2>
          </div>
          <p className="text-[17px]/[26px] text-ink-2 lg:w-[440px] lg:shrink-0">
            MoniMac goes past CPU and memory. It watches your battery's health, the AirPods in your ears, every app's
            volume and the fans you never hear — then goes one step further for developers.
          </p>
        </Reveal>

        <div className="flex flex-col gap-5">
          <div className="flex flex-col gap-5 lg:flex-row">
            <Tile
              icon={Bluetooth}
              color="#5e5ce6"
              title="Bluetooth"
              shot="bluetooth"
              wide={false}
              alt="MoniMac's Bluetooth tab: AirPods Pro with left, right and case battery rings."
            >
              AirPods left, right and case, keyboard, trackpad and mouse. A heads-up before anything dies.
            </Tile>
            <Tile
              icon={BatteryMedium}
              color="#34c759"
              title="Battery"
              shot="battery"
              wide
              delay={0.08}
              alt="MoniMac's Battery tab: charge, health, cycle count and power draw."
            >
              Charge, health, cycle count and live power draw — plus which apps are draining it.
            </Tile>
          </div>
          <div className="flex flex-col gap-5 lg:flex-row">
            <Tile
              icon={Volume2}
              color="#af52de"
              title="Sound"
              shot="sound"
              wide
              alt="MoniMac's Sound tab: output device and a volume slider for each app."
            >
              Set the volume of each app on its own, and mute the one that keeps chiming.
            </Tile>
            <Tile
              icon={Thermometer}
              color="#ff453a"
              title="Temperature & Fans"
              shot="temperature"
              wide={false}
              delay={0.08}
              alt="MoniMac's Temperature & Fans tab: sensor temperatures and fan speeds."
            >
              Sensor temperatures and fan speeds, read-only — so you know why it's warm without touching a thing.
            </Tile>
          </div>
        </div>
      </Container>

      <div id="developers" className="mt-24 overflow-hidden bg-mist pt-20 lg:mt-[120px] lg:pt-[120px]">
        <Container className="flex flex-col gap-12 lg:gap-16">
          <Reveal className="flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
            <div className="flex max-w-[600px] flex-col gap-5">
              <p className="flex items-center gap-2 text-[15px] font-semibold text-ink-2">
                <SquareTerminal className="size-[18px]" />
                For developers · Projects
              </p>
              <h2 className="text-[34px]/[38px] font-semibold tracking-[-1px] sm:text-[48px]/[53px] sm:tracking-[-1.2px]">
                That dev server from last week? Still running.
              </h2>
            </div>
            <div className="flex flex-col gap-6 lg:w-[470px] lg:shrink-0">
              <p className="text-[17px]/[26px] text-ink-2">
                Projects finds every local dev server, groups them by repo, and shows port, uptime and memory side by
                side. Servers idle for days get flagged — stop them in one click.
              </p>
              <ul className="flex flex-wrap gap-2 text-[14px]">
                {stacks.map((s) => (
                  <li key={s} className="rounded-full bg-white px-3 py-1.5 font-medium outline outline-line">
                    {s}
                  </li>
                ))}
                <li className="rounded-full px-3 py-1.5 text-ink-2 outline outline-line">and more</li>
              </ul>
            </div>
          </Reveal>
          <Reveal delay={0.1}>
            <Shot
              name="projects"
              width={1200}
              height={600}
              className="w-full"
              alt="MoniMac's Projects tab: local dev servers grouped by repository, with port, uptime, memory and an idle warning."
            />
          </Reveal>
        </Container>
      </div>
    </section>
  )
}
