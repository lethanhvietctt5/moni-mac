import { battery, disk, mac, metricColor, popoverBusiest, type Metric } from '../data/sample'
import { fixed, liveValue, wobble } from '../lib/live'
import { GearIcon, WindowIcon } from './icons'
import { AppGlyph, Meter, MetricBadge } from './ui'

const tabs = ['Overview', 'CPU', 'Memory', 'GPU', 'Network', 'Disk', 'Battery']

/** The popover's Overview tab, with simulated live values. */
export function Popover({ tick, className = '' }: { tick: number; className?: string }) {
  const cpu = liveValue('cpuPercent', tick)
  const memory = liveValue('memoryGB', tick)
  const gpu = liveValue('gpuPercent', tick)
  const down = liveValue('networkDownMBps', tick)
  const up = liveValue('networkUpKBps', tick) / 1000
  const temp = liveValue('cpuTempC', tick)
  const usedDisk = disk.totalGB - disk.freeGB

  const rows: Array<{ metric: Metric; label: string; value: string; fraction: number }> = [
    { metric: 'cpu', label: 'CPU', value: `${Math.round(cpu)}%`, fraction: cpu / 100 },
    { metric: 'memory', label: 'Memory', value: `${fixed(memory)} / ${mac.memoryGB} GB`, fraction: memory / mac.memoryGB },
    { metric: 'gpu', label: 'GPU', value: `${Math.round(gpu)}%`, fraction: gpu / 100 },
    { metric: 'network', label: 'Network', value: `↓${fixed(down)}  ↑${fixed(up)} MB/s`, fraction: down / 10 },
    { metric: 'disk', label: 'Disk', value: `${usedDisk} / ${disk.totalGB} GB`, fraction: usedDisk / disk.totalGB },
    { metric: 'battery', label: 'Battery', value: `${battery.percent}% · charging`, fraction: battery.percent / 100 },
    { metric: 'temp', label: 'Temperature', value: `${Math.round(temp)} °C`, fraction: temp / 105 },
  ]
  const busiestCPU = popoverBusiest.map((app, i) => ({
    app,
    cpu: i === 0 ? wobble(app.cpu, 0.2, 10, tick) : wobble(app.cpu, 0.15, 11 + i, tick),
  }))

  return (
    <div
      className={`w-[340px] max-w-full overflow-hidden rounded-[14px] border border-sep/80 bg-win/90 text-text shadow-[0_24px_60px_-12px_rgba(0,0,0,0.45)] backdrop-blur-2xl ${className}`}
    >
      <div className="flex items-center justify-between px-4 pt-3 pb-2.5">
        <span className="text-[14px] font-semibold">MoniMac</span>
        <span className="flex gap-2.5 text-text-2" aria-hidden="true">
          <WindowIcon size={15} />
          <GearIcon size={15} />
        </span>
      </div>
      <div className="mx-3 flex overflow-hidden rounded-[7px] bg-track/70 p-0.5 text-[11px]" aria-hidden="true">
        {tabs.map((t, i) => (
          <span
            key={t}
            className={`flex-1 rounded-[5px] py-[3px] text-center ${i === 0 ? 'bg-surface-raised font-medium shadow-sm' : 'text-text-2'} ${i > 4 ? 'hidden min-[380px]:block' : ''}`}
          >
            {t}
          </span>
        ))}
      </div>

      <ul className="space-y-2.5 px-4 pt-3.5 pb-3">
        {rows.map((r) => (
          <li key={r.metric} className="flex items-center gap-3">
            <MetricBadge metric={r.metric} size={22} />
            <div className="w-[110px] shrink-0">
              <div className="text-[12.5px] leading-tight">{r.label}</div>
              <Meter fraction={r.fraction} color={metricColor[r.metric]} className="mt-1 h-[3px]" />
            </div>
            <span className="ml-auto text-right text-[12.5px] font-medium whitespace-pre tabular-nums">{r.value}</span>
          </li>
        ))}
      </ul>

      <div className="mx-4 border-t border-sep" />
      <div className="px-4 pt-3 pb-2">
        <div className="mb-1.5 flex items-baseline justify-between">
          <span className="text-[12.5px] font-semibold">Busiest Right Now</span>
          <span className="text-[12px] text-accent">Open MoniMac</span>
        </div>
        <ul className="space-y-1.5">
          {busiestCPU.map(({ app, cpu: value }) => (
            <li key={app.name} className="flex items-center gap-2.5">
              <AppGlyph app={app} size={24} />
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline gap-1.5 text-[12.5px]">
                  <span className="truncate">{app.name}</span>
                  <span className="shrink-0 text-[10.5px] text-text-3">{app.processes} processes</span>
                </div>
                <Meter fraction={value / 14} color="var(--cpu)" className="mt-1 h-[3px]" />
              </div>
              <span className="w-11 text-right text-[12.5px] font-medium tabular-nums">{fixed(value)}%</span>
            </li>
          ))}
        </ul>
      </div>
      <div className="flex items-center justify-between border-t border-sep/70 px-4 py-2 text-[11px] text-text-2">
        <span className="flex items-center gap-1.5">
          <span className="live-dot size-1.5 rounded-full bg-success" />
          Live · uptime 3d 4h
        </span>
        <span>Quit MoniMac</span>
      </div>
    </div>
  )
}
