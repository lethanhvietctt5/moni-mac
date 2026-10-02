import { ArrowDownUp, Cpu, HardDrive, History, Layers, LayoutGrid, MemoryStick } from 'lucide-react'
import { Container, Reveal, SectionHeader, Shot } from './ui'

const metrics = [
  { icon: Cpu, color: '#0a84ff', title: 'CPU', body: 'Per-core load across P and E cores, plus 1, 5 and 15-minute load average.' },
  { icon: MemoryStick, color: '#af52de', title: 'Memory', body: 'Pressure, swap and compression, so you know when it’s actually tight.' },
  { icon: Layers, color: '#ff9f0a', title: 'GPU', body: 'Utilization, and which apps are leaning on it.' },
  { icon: ArrowDownUp, color: '#30b0c7', title: 'Network', body: 'Live throughput up and down, plus 7 and 30-day totals.' },
  { icon: HardDrive, color: '#5e5ce6', title: 'Disk', body: 'Read and write speeds, a storage breakdown and SSD health.' },
  { icon: LayoutGrid, color: '#1d1d1f', title: 'Every app', body: 'CPU, memory, GPU, network, disk and power for each app.' },
]

export function MetricsSection() {
  return (
    <section id="metrics" className="overflow-hidden bg-white py-24 lg:py-32">
      <Container>
        <SectionHeader
          eyebrow={<span className="text-[13px] tracking-[1.5px]">SYSTEM METRICS</span>}
          title={
            <>
              Everything about your Mac.
              <br />
              One window.
            </>
          }
        >
          CPU, memory, GPU, network and disk, down to the app using them. Live numbers at a glance, with 30 days of
          history behind every one.
        </SectionHeader>
      </Container>

      {/* Up to 1440 px the window runs off the right edge, as in the design; wider, it ends with the
          design's frame and gets rounded corners. The list stays on the column. */}
      <div className="mx-auto mt-12 flex max-w-[1440px] flex-col gap-12 px-6 lg:mt-[72px] lg:flex-row lg:items-center lg:gap-[72px] lg:pr-0 lg:pl-[max(24px,calc((min(100vw,1440px)-1200px)/2))]">
        <Reveal className="lg:w-[400px] lg:shrink-0">
          <ul>
            {metrics.map(({ icon: Icon, color, title, body }) => (
              <li key={title} className="flex gap-4 border-b border-line py-[18px] last:border-b-0">
                <Icon className="mt-0.5 size-5 shrink-0" style={{ color }} strokeWidth={2} />
                <div className="flex flex-col gap-1">
                  <h3 className="text-[17px] font-semibold tracking-[-0.2px]">{title}</h3>
                  <p className="text-[15px]/[22px] text-ink-2">{body}</p>
                </div>
              </li>
            ))}
          </ul>
          <p className="flex items-center gap-2 border-t border-line pt-6 text-[14px] text-ink-2">
            <History className="size-4 text-ink-3" />
            30 days of history, kept on your Mac.
          </p>
        </Reveal>
        <Reveal className="min-w-0 lg:shrink-0" delay={0.1}>
          <Shot
            name="overview"
            width={848}
            height={700}
            className="w-full rounded-[20px] lg:w-[848px] lg:max-w-none lg:rounded-l-[24px] lg:rounded-r-none min-[1441px]:rounded-r-[24px]"
            alt="The MoniMac window on Overview: CPU, memory, GPU, disk and battery tiles with charts, and the busiest apps."
          />
        </Reveal>
      </div>
    </section>
  )
}
