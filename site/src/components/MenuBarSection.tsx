import { ArrowDownUp, ArrowUpRight, Command, Cpu, MemoryStick, SlidersHorizontal, TriangleAlert, Wifi } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'
import { formatGB, formatPercent, formatRate, useReadings } from '../live'
import type { Readings } from '../live'
import { REPO_LABEL, REPO_URL, VERSION } from '../site'
import { Container, Reveal, SectionHeader, Shot, StoryPoint } from './ui'

/** A 60-second sparkline as MoniMac draws it in the menu bar: ten 2 pt bars, 14 pt tall. */
function Spark({ bars }: { bars: number[] }) {
  return (
    <span className="flex h-[14px] items-end gap-px" aria-hidden="true">
      {bars.map((b, i) => (
        <span
          key={i}
          className="w-[2px] rounded-[0.5px] bg-ink transition-[height] duration-500 ease-out"
          style={{ height: `${Math.max(2, Math.round(b * 14))}px` }}
        />
      ))}
    </span>
  )
}

function Item({ icon: Icon, bars, value, className = '' }: { icon?: LucideIcon; bars?: number[]; value?: string; className?: string }) {
  return (
    <span className={`flex items-center gap-[5px] rounded px-1.5 py-0.5 ${className}`}>
      {Icon && <Icon className="size-[13px]" strokeWidth={2.25} />}
      {bars && <Spark bars={bars} />}
      {value && <span className="text-[12px] font-semibold whitespace-nowrap tabular-nums">{value}</span>}
    </span>
  )
}

/** Wi-Fi, Control Center, and the clock: the system's items, right of MoniMac's. */
function SystemItems() {
  return (
    <>
      <span className="hidden px-1.5 sm:block">
        <Wifi className="size-[13px]" strokeWidth={2.25} />
      </span>
      <span className="hidden px-1.5 sm:block">
        <SlidersHorizontal className="size-[13px]" strokeWidth={2.25} />
      </span>
      <span className="hidden text-[12px] font-medium whitespace-nowrap sm:block">Wed 1 Oct 9:41</span>
    </>
  )
}

function Strip({ children, blur = true }: { children: ReactNode; blur?: boolean }) {
  return (
    <div
      className={`flex h-7 w-full items-center justify-end gap-3.5 rounded-lg bg-white/45 px-3.5 text-ink ${
        blur ? 'backdrop-blur-[10px]' : ''
      }`}
    >
      {children}
      <SystemItems />
    </div>
  )
}

function Variant({ label, desc, children }: { label: string; desc: string; children: ReactNode }) {
  return (
    <div className="flex w-full flex-col gap-2">
      <p className="flex flex-wrap gap-x-2 text-[12px] text-ink">
        <span className="font-bold">{label}</span>
        <span className="text-ink/60">{desc}</span>
      </p>
      {children}
    </div>
  )
}

function Variants({ r }: { r: Readings }) {
  const cpu = formatPercent(r.cpu)
  const memory = formatGB(r.memory)
  const gpu = formatPercent(r.gpu)
  return (
    <>
      <Variant label="Value only" desc="Compact numbers, monospaced feel">
        <Strip>
          <Item icon={Cpu} value={cpu} />
          <Item icon={MemoryStick} value={memory} />
          <Item icon={ArrowDownUp} value={formatRate(r.network)} />
        </Strip>
      </Variant>

      <Variant label="Graph only" desc="Last 60 seconds as a sparkline">
        <Strip>
          <Item icon={Cpu} bars={r.cpuBars} />
          <Item icon={MemoryStick} bars={r.memoryBars} />
          <Item icon={ArrowDownUp} bars={r.networkBars} />
        </Strip>
      </Variant>

      <Variant label="Value + graph" desc="Most information, most width">
        <Strip>
          <Item bars={r.cpuBars} value={cpu} />
          <Item bars={r.memoryBars} value={memory} />
          <Item bars={r.gpuBars} value={gpu} />
        </Strip>
      </Variant>

      <Variant label="Warning state" desc="Under system strain, the item becomes a warning sign">
        <div className="relative pb-[48px]">
          <Strip>
            <span className="relative">
              <Item icon={TriangleAlert} value="CPU 98%" className="bg-[#ffb340]" />
              <span className="absolute top-[calc(100%+12px)] left-0 flex items-center gap-2 rounded-lg bg-white/90 px-2.5 py-2 whitespace-nowrap shadow-[0_4px_12px_#00000026]">
                <TriangleAlert className="size-3.5 text-[#ff9f0a]" strokeWidth={2.25} />
                <span className="flex flex-col gap-px text-left">
                  <span className="text-[12px] font-semibold">CPU above 90% for 2 min</span>
                  <span className="text-[11px] text-ink-2">Xcode is using 412% · click for details</span>
                </span>
              </span>
            </span>
            <Item bars={r.memoryBars} value={memory} />
            <Item bars={r.gpuBars} value={gpu} />
          </Strip>
        </div>
      </Variant>

      <Variant label="Reorder" desc="Items move like any system menu extra">
        <Strip blur={false}>
          <Item
            icon={MemoryStick}
            value={memory}
            className="animate-[nudge_2.4s_ease-in-out_infinite] bg-white/80 opacity-90 shadow-[0_3px_8px_#00000033] motion-reduce:animate-none"
          />
          <span className="h-4 w-[2px] animate-pulse rounded-[1px] bg-accent motion-reduce:animate-none" />
          <Item icon={Cpu} value={cpu} />
          <Item icon={ArrowDownUp} value={formatRate(r.network)} />
        </Strip>
        <div className="flex items-center gap-2.5 rounded-[10px] bg-white/70 px-3 py-2.5">
          <span className="flex h-6 w-[26px] shrink-0 items-center justify-center rounded-[5px] bg-white outline outline-black/15">
            <Command className="size-[13px]" strokeWidth={2.25} />
          </span>
          <span className="text-[12px]/[17px] text-ink">
            Hold ⌘ Command and drag any MoniMac item to reorder it. Drag it off the menu bar to hide it.
          </span>
        </div>
      </Variant>
    </>
  )
}

export function MenuBarSection() {
  const [ref, readings] = useReadings<HTMLDivElement>()
  return (
    <section id="menu-bar" className="bg-white py-24 lg:pt-[136px] lg:pb-[152px]">
      <Container className="flex flex-col gap-16 lg:gap-[104px]">
        <SectionHeader eyebrow="In the menu bar" title="Every metric gets its own place in the menu bar.">
          CPU, memory, network, GPU and temperature can each live up there on their own. Keep the ones you care
          about, in the style that suits you, and leave the rest out.
        </SectionHeader>

        <div className="flex flex-col gap-12 lg:flex-row lg:items-center lg:gap-[72px]">
          <Reveal className="lg:w-[360px] lg:shrink-0">
            <StoryPoint number="01" title="Three ways to read it">
              Value only for compact numbers. Graph only for a 60‑second sparkline. Or value and graph together when
              you want both.
            </StoryPoint>
            <StoryPoint number="02" title="Speaks up under strain">
              When a metric runs hot, its item turns into a warning sign. Hover for the cause, click to find the app
              behind it.
            </StoryPoint>
            <StoryPoint number="03" title="Arrange it like any menu extra">
              Hold ⌘ and drag to reorder. Drag an item off the bar to hide it.
            </StoryPoint>
          </Reveal>
          <Reveal className="min-w-0 flex-1" delay={0.1}>
            <div ref={ref} className="wallpaper flex flex-col gap-[26px] rounded-[20px] p-5 sm:p-10">
              <Variants r={readings} />
            </div>
          </Reveal>
        </div>

        <div className="flex flex-col gap-12 lg:flex-row lg:items-center lg:gap-[72px]">
          <Reveal className="min-w-0 flex-1">
            <Shot
              name="popovers"
              width={768}
              height={780}
              className="w-full rounded-[20px]"
              alt="Two MoniMac popovers under the menu bar: the CPU tab with per-core load and history, and the Overview tab with every metric and the busiest apps."
            />
          </Reveal>
          <Reveal className="lg:w-[360px] lg:shrink-0" delay={0.1}>
            <StoryPoint number="04" title="One click, the whole picture">
              Click any MoniMac item and a popover opens with every metric at once, plus the apps working hardest
              right now.
            </StoryPoint>
            <StoryPoint number="05" title="Drill in without leaving">
              Tabs take you straight to CPU, memory, GPU, network, disk and battery, with live history, per‑core load
              and the top apps.
            </StoryPoint>
            <div className="flex flex-col gap-1.5 border-t border-line pt-6 text-[15px]">
              <span className="text-ink-2">Free and open source · v{VERSION}</span>
              <a href={REPO_URL} className="flex items-center gap-1.5 font-medium text-accent hover:underline">
                {REPO_LABEL}
                <ArrowUpRight className="size-[15px]" />
              </a>
            </div>
          </Reveal>
        </div>
      </Container>
    </section>
  )
}
