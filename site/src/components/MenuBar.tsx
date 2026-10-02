import { AnimatePresence, m } from 'motion/react'
import { clock } from '../data/sample'
import { fixed, series, wobble } from '../lib/live'
import { CpuIcon, GpuIcon, MemoryIcon, NetworkIcon, SlidersIcon, ThermometerIcon, WarningIcon, WifiIcon } from './icons'

export type MenuMetric = 'cpu' | 'memory' | 'network' | 'gpu' | 'temp'
export type MenuStyle = 'value' | 'graph' | 'both'

const icons = { cpu: CpuIcon, memory: MemoryIcon, network: NetworkIcon, gpu: GpuIcon, temp: ThermometerIcon }

/** The live value and 60-second sparkline for a menu bar item. */
function reading(metric: MenuMetric, tick: number): { text: string; spark: number[] } {
  switch (metric) {
    case 'cpu':
      return { text: `${Math.round(wobble(32, 0.3, 1, tick))}%`, spark: series(1, 12, tick, 15, 70) }
    case 'memory':
      return { text: `${fixed(wobble(11.4, 0.015, 2, tick))} GB`, spark: series(2, 12, tick, 60, 66) }
    case 'network':
      return { text: `${fixed(wobble(4.2, 0.35, 3, tick))} MB/s`, spark: series(3, 12, tick, 5, 90) }
    case 'gpu':
      return { text: `${Math.round(wobble(18, 0.35, 4, tick))}%`, spark: series(4, 12, tick, 5, 50) }
    case 'temp':
      return { text: `${Math.round(wobble(58, 0.04, 5, tick))}°C`, spark: series(5, 12, tick, 40, 60) }
  }
}

/** Widest text per metric, so values don't make the bar jitter. */
const minWidth: Record<MenuMetric, string> = {
  cpu: '2.6em',
  memory: '4.1em',
  network: '4.9em',
  gpu: '2.6em',
  temp: '2.8em',
}

function Spark({ values }: { values: number[] }) {
  return (
    <span className="flex h-[12px] items-end gap-[1.5px]" aria-hidden="true">
      {values.map((v, i) => (
        <span
          key={i}
          className="bar-y block h-full w-[2px] rounded-[0.5px] bg-current"
          style={{ transform: `scaleY(${Math.max(0.12, v / 100)})` }}
        />
      ))}
    </span>
  )
}

export function MenuItem({
  metric,
  style,
  tick,
  active = false,
  showIcon,
}: {
  metric: MenuMetric
  style: MenuStyle
  tick: number
  active?: boolean
  showIcon?: boolean
}) {
  const Icon = icons[metric]
  const { text, spark } = reading(metric, tick)
  const withIcon = showIcon ?? style !== 'both'
  return (
    <span
      className={`flex h-[22px] items-center gap-1.5 rounded-[5px] px-1.5 ${active ? 'bg-menubar-hl' : ''}`}
    >
      {withIcon && <Icon size={14} strokeWidth={2} />}
      {style !== 'value' && <Spark values={spark} />}
      {style !== 'graph' && (
        <span className="text-right tabular-nums" style={{ minWidth: minWidth[metric] }}>
          {text}
        </span>
      )}
    </span>
  )
}

/** The warning badge an item turns into when the system is under strain. */
export function WarningItem({ text = 'CPU 98%' }: { text?: string }) {
  return (
    <span className="flex h-[22px] items-center gap-1 rounded-[5px] bg-[#ffb340] px-1.5 font-semibold text-[#3a2600]">
      <WarningIcon size={13} strokeWidth={2.2} />
      {text}
    </span>
  )
}

/**
 * A macOS menu bar holding MoniMac items, followed by the system's own
 * Wi-Fi, Control Center, and clock. No Apple logo or other brand marks.
 */
export function MenuBar({
  metrics,
  style,
  tick,
  activeMetric,
  warning,
  className = '',
  compactClock = false,
}: {
  metrics: readonly MenuMetric[]
  style: MenuStyle
  tick: number
  activeMetric?: MenuMetric
  warning?: boolean
  className?: string
  compactClock?: boolean
}) {
  return (
    <div
      className={`flex h-[30px] items-center justify-end gap-1 overflow-hidden bg-menubar-bg px-2 text-[13px] font-medium text-menubar-fg backdrop-blur-xl ${className}`}
    >
      <AnimatePresence initial={false}>
        {metrics.map((metric) => (
          <m.span
            key={metric}
            initial={{ opacity: 0, width: 0 }}
            animate={{ opacity: 1, width: 'auto' }}
            exit={{ opacity: 0, width: 0 }}
            transition={{ duration: 0.3 }}
            className="flex shrink-0 overflow-hidden"
          >
            {warning && metric === 'cpu' ? (
              <WarningItem />
            ) : (
              <MenuItem metric={metric} style={style} tick={tick} active={metric === activeMetric} />
            )}
          </m.span>
        ))}
      </AnimatePresence>
      <span className="ml-1 hidden shrink-0 items-center gap-3 px-1.5 sm:flex" aria-hidden="true">
        <WifiIcon size={15} strokeWidth={2} />
        <SlidersIcon size={15} strokeWidth={2} />
      </span>
      <span className={`shrink-0 whitespace-pre px-1.5 tabular-nums ${compactClock ? 'hidden md:inline' : 'hidden sm:inline'}`}>
        {clock}
      </span>
    </div>
  )
}
