import type { ReactNode } from 'react'
import {
  battery,
  busiest,
  cpu,
  cpuHistory,
  disk,
  diskHistory,
  diskWritesToday,
  gpu,
  gpuHistory,
  historyAxis,
  live,
  mac,
  memory,
  metricColor,
  network,
  pressureHistory,
  processTotals,
  topCPU,
  topGPU,
  topMemory,
  topNetwork,
} from '../../data/sample'
import { fixed, series, wobble } from '../../lib/live'
import { LayersIcon } from '../icons'
import { AppRow, Axis, Bars, Card, Meter, MetricLabel, RangePicker, SectionTitle } from '../ui'

type TabProps = { tick: number }

function Tile({
  label,
  value,
  caption,
  children,
}: {
  label: ReactNode
  value: string
  caption: string
  children: ReactNode
}) {
  return (
    <Card className="flex min-w-0 flex-col">
      {label}
      <div className="mt-1.5 text-[24px] leading-none font-semibold tracking-tight tabular-nums">{value}</div>
      <div className="mt-3 mb-2.5">{children}</div>
      <div className="truncate text-[11px] text-text-2">{caption}</div>
    </Card>
  )
}

export function OverviewTab({ tick }: TabProps) {
  const c = wobble(live.cpu.total, 0.3, 1, tick)
  const m = wobble(live.memory.usedGB, 0.015, 2, tick)
  const g = wobble(live.gpu.percent, 0.35, 4, tick)
  const n = wobble(live.network.downMBps, 0.35, 3, tick)
  const t = wobble(live.temp.cpuC, 0.04, 5, tick)
  const w = wobble(live.disk.writeMBps, 0.5, 7, tick)
  const { split } = processTotals
  const total = split.app + split.agent + split.system

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-2.5 lg:grid-cols-4">
        <Tile label={<MetricLabel metric="cpu">CPU</MetricLabel>} value={`${Math.round(c)}%`} caption={`User ${Math.round(c * 0.66)}% · System ${Math.round(c * 0.34)}%`}>
          <Bars values={series(1, 16, tick, 15, 70)} color={metricColor.cpu} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="memory">Memory</MetricLabel>} value={`${fixed(m)} GB`} caption={`of ${mac.memoryGB} GB · Pressure normal`}>
          <Bars values={series(2, 16, tick, 78, 84)} color={metricColor.memory} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="gpu">GPU</MetricLabel>} value={`${Math.round(g)}%`} caption={`${gpu.memory} VRAM · 4 apps`}>
          <Bars values={series(4, 16, tick, 4, 55)} color={metricColor.gpu} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="network">Network</MetricLabel>} value={`${fixed(n + 0.38)} MB/s`} caption={`↓ ${fixed(n)} MB/s · ↑ 380 KB/s`}>
          <Bars values={series(3, 16, tick, 8, 90)} color={metricColor.network} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="disk">Disk</MetricLabel>} value={`${disk.freeGB} GB`} caption={`free of ${disk.totalGB} GB · W ${Math.round(w)} MB/s`}>
          <Bars values={series(7, 16, tick, 3, 60)} color={metricColor.disk} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="battery">Battery</MetricLabel>} value={`${battery.percent}%`} caption={`Charging · Full in ${battery.fullIn}`}>
          <Bars values={series(8, 16, tick, 80, 86)} color={metricColor.battery} className="h-7" />
        </Tile>
        <Tile label={<MetricLabel metric="temp">Temperature</MetricLabel>} value={`${Math.round(t)}°C`} caption="CPU die · Fans 2,140 rpm">
          <Bars values={series(5, 16, tick, 62, 78)} color={metricColor.temp} className="h-7" />
        </Tile>
        <Card className="flex min-w-0 flex-col">
          <span className="flex items-center gap-1.5 text-[12px] font-medium text-text-2">
            <LayersIcon size={13} />
            Processes
          </span>
          <div className="mt-1.5 text-[24px] leading-none font-semibold tracking-tight">{processTotals.apps} apps</div>
          <div className="mt-3 flex h-1.5 overflow-hidden rounded-full bg-track" aria-hidden="true">
            <div className="bg-cpu" style={{ width: `${(split.app / total) * 100}%` }} />
            <div className="bg-text-3/70" style={{ width: `${(split.agent / total) * 100}%` }} />
          </div>
          <div className="mt-1.5 flex justify-between text-[10px] text-text-2">
            <span>{split.app} apps</span>
            <span>{split.agent} agents</span>
            <span>{split.system} system</span>
          </div>
          <div className="mt-auto truncate pt-1 text-[11px] text-text-2">
            {processTotals.processes} processes · {processTotals.threads} threads
          </div>
        </Card>
      </div>

      <div>
        <SectionTitle aside={<span className="text-accent">Show All {processTotals.apps} Apps</span>}>Busiest Right Now</SectionTitle>
        <div className="grid gap-x-8 sm:grid-cols-2">
          {busiest.map((b) => (
            <AppRow key={b.app.name} app={b.app} value={b.label} fraction={b.fraction} color={metricColor[b.metric]} />
          ))}
        </div>
      </div>
    </div>
  )
}

function Stat({ label, value, note, dot }: { label: string; value: string; note: string; dot?: string }) {
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-1.5 text-[11px] text-text-2">
        {dot && <span className="size-1.5 rounded-full" style={{ background: dot }} />}
        {label}
      </div>
      <div className="mt-0.5 text-[20px] font-semibold tracking-tight tabular-nums">{value}</div>
      <div className="truncate text-[10.5px] text-text-3">{note}</div>
    </div>
  )
}

export function CPUTab({ tick }: TabProps) {
  const total = wobble(live.cpu.total, 0.3, 1, tick)
  const user = total * 0.66
  const system = total - user
  const cores = live.perCore.map((v, i) => Math.min(98, wobble(v, 0.35, 20 + i, tick)))

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-x-5 gap-y-4 sm:grid-cols-3 lg:grid-cols-6">
        <div className="col-span-2 sm:col-span-3 lg:col-span-1">
          <div className="flex items-baseline gap-1.5">
            <span className="text-[34px] leading-none font-semibold tracking-tight tabular-nums">{Math.round(total)}%</span>
            <span className="text-[12px] text-text-2">in use</span>
          </div>
          <div className="mt-2 flex h-1.5 overflow-hidden rounded-full bg-track" aria-hidden="true">
            <div className="bg-cpu" style={{ width: `${user}%` }} />
            <div className="bg-cpu/50" style={{ width: `${system}%` }} />
          </div>
        </div>
        <Stat label="User" value={`${Math.round(user)}%`} note="Apps & services" dot="var(--cpu)" />
        <Stat label="System" value={`${Math.round(system)}%`} note="macOS kernel" dot="color-mix(in srgb, var(--cpu) 50%, transparent)" />
        <Stat label="Idle" value={`${Math.round(100 - total)}%`} note={`${fixed(((100 - total) / 100) * 12)} of 12 cores`} />
        <Stat label="Load Average" value={fixed(cpu.load.one, 2)} note={`5m ${cpu.load.five} · 15m ${cpu.load.fifteen}`} />
        <Stat label="Threads" value={cpu.threads} note={`${cpu.processes} processes`} />
      </div>

      <Card className="bg-transparent">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <SectionTitle aside={cpu.peak}>History</SectionTitle>
          <RangePicker />
        </div>
        <div className="flex h-36 items-end gap-[3px]" aria-hidden="true">
          {cpuHistory.map(([u, s], i) => (
            <div key={i} className="flex h-full flex-1 flex-col justify-end">
              <div className="rounded-t-[2px] bg-cpu/45" style={{ height: `${s}%` }} />
              <div className="bg-cpu" style={{ height: `${u}%` }} />
            </div>
          ))}
        </div>
        <Axis labels={historyAxis} />
      </Card>

      <div className="grid gap-5 md:grid-cols-2">
        <div>
          <SectionTitle aside="6 performance · 6 efficiency">Per-Core Load</SectionTitle>
          <div className="flex h-28 gap-[5px]" aria-hidden="true">
            {cores.map((v, i) => (
              <div key={i} className="flex flex-1 flex-col items-center gap-1">
                <div className="relative w-full flex-1 overflow-hidden rounded-[3px] bg-track">
                  <div
                    className="bar-y absolute inset-0"
                    style={{ background: i < 6 ? 'var(--cpu)' : 'color-mix(in srgb, var(--cpu) 60%, transparent)', transform: `scaleY(${v / 100})` }}
                  />
                </div>
                <span className="text-[9.5px] text-text-3">{i < 6 ? `P${i + 1}` : `E${i - 5}`}</span>
              </div>
            ))}
          </div>
        </div>
        <div>
          <SectionTitle aside={<span className="text-accent">Show All</span>}>Top Apps by CPU</SectionTitle>
          {topCPU.map((app, i) => {
            const v = wobble(app.cpu, 0.18, 30 + i, tick)
            return <AppRow key={app.name} app={app} value={`${fixed(v)}%`} fraction={v / 14} color={metricColor.cpu} />
          })}
        </div>
      </div>
    </div>
  )
}

function Legend({
  items,
  color,
}: {
  items: ReadonlyArray<{ label: string; size: string; hint: string; opacity: number }>
  color: string
}) {
  return (
    <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
      {items.map((s) => (
        <div key={s.label} className="min-w-0">
          <div className="flex items-center gap-1.5 text-[11px] text-text-2">
            <span className="size-2 rounded-[2px]" style={{ background: swatch(color, s.opacity) }} />
            {s.label}
          </div>
          <div className="text-[14px] font-semibold tabular-nums">{s.size}</div>
          <div className="truncate text-[10.5px] text-text-3">{s.hint}</div>
        </div>
      ))}
    </div>
  )
}

/** Segment fill: metric color at an opacity; 0 is the track, negatives are grays. */
function swatch(color: string, opacity: number): string {
  if (opacity === 0) return 'var(--track)'
  if (opacity === -1) return 'color-mix(in srgb, var(--text-3) 90%, transparent)'
  if (opacity === -2) return 'color-mix(in srgb, var(--text-3) 45%, transparent)'
  return `color-mix(in srgb, ${color} ${opacity * 100}%, transparent)`
}

function SegmentBar({
  items,
  color,
}: {
  items: ReadonlyArray<{ label: string; opacity: number; gb: number }>
  color: string
}) {
  const total = items.reduce((sum, s) => sum + s.gb, 0)
  return (
    <div className="flex h-5 gap-[2px] overflow-hidden rounded-md" aria-hidden="true">
      {items.map((s) => (
        <div key={s.label} style={{ width: `${(s.gb / total) * 100}%`, background: swatch(color, s.opacity) }} />
      ))}
    </div>
  )
}

export function MemoryTab({ tick }: TabProps) {
  const used = wobble(live.memory.usedGB, 0.015, 2, tick)
  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-[1.3fr_1fr_1fr_1fr]">
        <div>
          <div className="flex items-baseline gap-1.5">
            <span className="text-[34px] leading-none font-semibold tracking-tight tabular-nums">{fixed(used)}</span>
            <span className="text-[12px] text-text-2">GB of {mac.memoryGB} GB used</span>
          </div>
          <Meter fraction={used / mac.memoryGB} color={metricColor.memory} className="mt-2 h-1.5" />
        </div>
        <Stat label="Memory Pressure" value={memory.pressure} note={`${memory.pressurePercent}% · no throttling`} dot="var(--success)" />
        <Stat label="Swap Used" value={memory.swapUsed} note={`of ${memory.swapFile} swap file`} />
        <Stat label="Compression" value={memory.compression} note={memory.compressionDetail} />
      </div>
      <div>
        <SegmentBar items={memory.segments} color={metricColor.memory} />
        <Legend items={memory.segments} color={metricColor.memory} />
      </div>
      <div className="grid gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <SectionTitle>Memory Pressure</SectionTitle>
            <RangePicker />
          </div>
          <div className="flex h-28 items-end gap-[3px]" aria-hidden="true">
            {pressureHistory.map((v, i) => (
              <div
                key={i}
                className="flex-1 rounded-t-[2px]"
                style={{ height: `${v}%`, background: v > 60 ? 'var(--danger)' : v > 40 ? 'var(--warning)' : 'var(--success)' }}
              />
            ))}
          </div>
          <Axis labels={historyAxis} />
        </Card>
        <div>
          <SectionTitle aside={<span className="text-accent">Show All</span>}>Top Apps by Memory</SectionTitle>
          {topMemory.map((app) => (
            <AppRow key={app.name} app={app} value={app.memory} fraction={app.memoryMB / 2000} color={metricColor.memory} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function GPUTab({ tick }: TabProps) {
  const util = wobble(live.gpu.percent, 0.35, 4, tick)
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card>
          <MetricLabel metric="gpu">Utilization</MetricLabel>
          <div className="mt-1 text-[26px] font-semibold tabular-nums">{Math.round(util)}%</div>
          <div className="text-[11px] text-text-2">Renderer {Math.round(util)}% · Tiler {gpu.tiler}%</div>
        </Card>
        <Card>
          <MetricLabel metric="gpu">GPU Memory</MetricLabel>
          <div className="mt-1 text-[26px] font-semibold">{gpu.memory}</div>
          <div className="text-[11px] text-text-2">Shared from {mac.memoryGB} GB unified</div>
        </Card>
        <Card>
          <span className="text-[12px] text-text-2">Average · 24H</span>
          <div className="mt-1 text-[26px] font-semibold">{gpu.avg24h}%</div>
          <div className="text-[11px] text-text-2">3 pts lower than yesterday</div>
        </Card>
        <Card>
          <span className="text-[12px] text-text-2">Peak · 24H</span>
          <div className="mt-1 text-[26px] font-semibold">{gpu.peak24h}%</div>
          <div className="truncate text-[11px] text-text-2">{gpu.peakWhen}</div>
        </Card>
      </div>
      <div className="grid gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <SectionTitle aside={`Avg ${gpu.avg24h}% · Peak ${gpu.peak24h}%`}>Utilization History</SectionTitle>
            <RangePicker />
          </div>
          <Bars values={gpuHistory} color={metricColor.gpu} className="h-32" />
          <Axis labels={historyAxis} />
        </Card>
        <div>
          <SectionTitle aside={<span className="text-accent">Show All</span>}>Top Apps by GPU</SectionTitle>
          {topGPU.map((app) => (
            <AppRow key={app.name} app={app} value={`${fixed(app.gpu ?? 0)}%`} fraction={(app.gpu ?? 0) / 14} color={metricColor.gpu} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function NetworkTab({ tick }: TabProps) {
  const down = wobble(live.network.downMBps, 0.35, 3, tick)
  const up = wobble(live.network.upKBps, 0.3, 6, tick)
  const maxDay = Math.max(...network.week.downGB)
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Stat label="↓ Download" value={`${fixed(down)} MB/s`} note="Live" dot="var(--network)" />
        <Stat label="↑ Upload" value={`${Math.round(up)} KB/s`} note="Live" dot="color-mix(in srgb, var(--network) 50%, transparent)" />
        <Stat label="Downloaded" value={network.downloaded} note={`This session · since ${network.since}`} />
        <Stat label="Uploaded" value={network.uploaded} note="This session" />
      </div>
      <Card className="bg-transparent">
        <SectionTitle aside="Last 60 seconds">Live Throughput</SectionTitle>
        <div className="relative h-28" aria-hidden="true">
          <Bars values={series(3, 40, tick, 10, 95)} color={metricColor.network} className="absolute inset-0" gap="gap-[2px]" />
          <Bars
            values={series(6, 40, tick, 2, 22)}
            color="color-mix(in srgb, var(--network) 45%, transparent)"
            className="absolute inset-0"
            gap="gap-[2px]"
          />
        </div>
      </Card>
      <div className="grid gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <SectionTitle aside={`↓ ${network.week.down} · ↑ ${network.week.up}`}>Last 7 Days</SectionTitle>
          <div className="flex h-28 items-end gap-3" aria-hidden="true">
            {network.week.downGB.map((d, i) => (
              <div key={i} className="flex h-full flex-1 items-end gap-[3px]">
                <div className="flex-1 rounded-t-[3px] bg-network" style={{ height: `${(d / maxDay) * 100}%` }} />
                <div className="flex-1 rounded-t-[3px] bg-network/45" style={{ height: `${(network.week.upGB[i] / maxDay) * 100}%` }} />
              </div>
            ))}
          </div>
          <Axis labels={network.week.days} />
        </Card>
        <div>
          <SectionTitle aside={<span className="text-accent">Show All</span>}>Top Apps by Network</SectionTitle>
          {topNetwork.map((app, i) => (
            <AppRow key={app.name} app={app} value={app.network ?? ''} fraction={[0.8, 0.3, 0.18, 0.12, 0.06][i]} color={metricColor.network} />
          ))}
        </div>
      </div>
    </div>
  )
}

export function DiskTab({ tick }: TabProps) {
  const read = wobble(live.disk.readMBps, 0.5, 9, tick)
  const write = wobble(live.disk.writeMBps, 0.5, 7, tick)
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="col-span-2 lg:col-span-1">
          <div className="flex items-baseline gap-1.5">
            <span className="text-[34px] leading-none font-semibold tracking-tight">{disk.freeGB}</span>
            <span className="text-[12px] text-text-2">GB free of {disk.totalGB} GB</span>
          </div>
          <Meter fraction={1 - disk.freeGB / disk.totalGB} color={metricColor.disk} className="mt-2 h-1.5" />
        </div>
        <Stat label="Read" value={`${Math.round(read)} MB/s`} note="Peak 1.9 GB/s today" dot="var(--disk)" />
        <Stat label="Write" value={`${Math.round(write)} MB/s`} note="Peak 840 MB/s today" dot="color-mix(in srgb, var(--disk) 45%, transparent)" />
        <Stat label="Written Today" value={`${disk.writtenTodayGB} GB`} note={`SSD health ${disk.ssdHealth}% · ${disk.lifetimeTB} TB lifetime`} />
      </div>
      <div>
        <SegmentBar items={disk.breakdown} color={metricColor.disk} />
        <Legend items={disk.breakdown} color={metricColor.disk} />
      </div>
      <div className="grid gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <SectionTitle>Read &amp; Write</SectionTitle>
            <RangePicker />
          </div>
          <div className="flex h-28 items-end gap-[3px]" aria-hidden="true">
            {diskHistory.map(([r, w], i) => (
              <div key={i} className="flex h-full flex-1 flex-col justify-end gap-[1px]">
                <div className="rounded-t-[2px] bg-disk" style={{ height: `${r * 0.6}%` }} />
                <div className="bg-disk/45" style={{ height: `${w * 0.4}%` }} />
              </div>
            ))}
          </div>
          <Axis labels={historyAxis} />
        </Card>
        <div>
          <SectionTitle aside={<span className="text-accent">Show All</span>}>Disk Writes Today</SectionTitle>
          {diskWritesToday.map((d) => (
            <AppRow key={d.app.name} app={d.app} value={d.amount} fraction={d.gb / 15} color={metricColor.disk} />
          ))}
        </div>
      </div>
    </div>
  )
}

