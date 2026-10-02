import type { CSSProperties, ReactNode } from 'react'
import { metricColor, type Metric, type SampleApp } from '../data/sample'
import { clamp } from '../lib/live'
import { metricIcon } from '../lib/metricIcons'

/** Vertical bars scaled with transforms, so live updates don't trigger layout. */
export function Bars({
  values,
  max = 100,
  color,
  className = 'h-8',
  gap = 'gap-[3px]',
  radius = 'rounded-[2px]',
  minimum = 0.06,
}: {
  values: readonly number[]
  max?: number
  color: string
  className?: string
  gap?: string
  radius?: string
  minimum?: number
}) {
  return (
    <div className={`flex items-end ${gap} ${className}`} aria-hidden="true">
      {values.map((v, i) => (
        <div
          key={i}
          className={`bar-y h-full flex-1 ${radius}`}
          style={{ background: color, transform: `scaleY(${Math.max(minimum, clamp(v / max))})` }}
        />
      ))}
    </div>
  )
}

/** A horizontal track with a colored fill. */
export function Meter({
  fraction,
  color,
  className = 'h-1',
  track = 'bg-track',
}: {
  fraction: number
  color: string
  className?: string
  track?: string
}) {
  return (
    <div className={`relative overflow-hidden rounded-full ${track} ${className}`} aria-hidden="true">
      <div
        className="bar-x absolute inset-0 rounded-full"
        style={{ background: color, transform: `scaleX(${clamp(fraction)})` }}
      />
    </div>
  )
}

/** A generic rounded glyph standing in for an app icon (no real app icons). */
export function AppGlyph({ app, size = 28 }: { app: Pick<SampleApp, 'glyph' | 'tint'>; size?: number }) {
  return (
    <span
      aria-hidden="true"
      className="inline-flex shrink-0 items-center justify-center font-semibold text-white shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.12)]"
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.26,
        fontSize: size * 0.46,
        background: `linear-gradient(160deg, color-mix(in srgb, ${app.tint} 78%, white), ${app.tint})`,
      }}
    >
      {app.glyph}
    </span>
  )
}

/** Colored rounded square with a metric's icon, as in the popover rows. */
export function MetricBadge({ metric, size = 24 }: { metric: Metric; size?: number }) {
  const Icon = metricIcon[metric]
  return (
    <span
      aria-hidden="true"
      className="inline-flex shrink-0 items-center justify-center text-white"
      style={{ width: size, height: size, borderRadius: size * 0.27, background: metricColor[metric] }}
    >
      <Icon size={size * 0.62} strokeWidth={2} />
    </span>
  )
}

/** Small metric label with its icon, as on tiles and cards. */
export function MetricLabel({ metric, children }: { metric: Metric; children: ReactNode }) {
  const Icon = metricIcon[metric]
  return (
    <span className="flex items-center gap-1.5 text-[12px] font-medium text-text-2">
      <Icon size={13} style={{ color: metricColor[metric] }} />
      {children}
    </span>
  )
}

/** The window's 12H / 24H / 7D / 30D control, drawn as part of a picture. */
export function RangePicker({ options = ['12H', '24H', '7D', '30D'], selected = '24H' }: { options?: string[]; selected?: string }) {
  return (
    <span className="inline-flex rounded-md bg-track/70 p-0.5 text-[11px] font-medium text-text-2" aria-hidden="true">
      {options.map((o) => (
        <span
          key={o}
          className={`rounded-[5px] px-2 py-0.5 ${o === selected ? 'bg-surface-raised text-text shadow-sm' : ''}`}
        >
          {o}
        </span>
      ))}
    </span>
  )
}

export function Card({ children, className = '', style }: { children: ReactNode; className?: string; style?: CSSProperties }) {
  return (
    <div className={`rounded-xl border border-sep/70 bg-surface p-3.5 ${className}`} style={style}>
      {children}
    </div>
  )
}

/** A row in a "Top Apps by …" list. */
export function AppRow({
  app,
  value,
  fraction,
  color,
  detail,
}: {
  app: SampleApp
  value: string
  fraction: number
  color: string
  detail?: string
}) {
  return (
    <div className="flex items-center gap-3 py-1.5">
      <AppGlyph app={app} size={26} />
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2 text-[13px] text-text">
          <span className="truncate">{app.name}</span>
          {detail && <span className="truncate text-[11px] text-text-3">{detail}</span>}
        </div>
        <Meter fraction={fraction} color={color} className="mt-1 h-[3px]" />
      </div>
      <span className="w-16 shrink-0 text-right text-[13px] font-medium tabular-nums text-text">{value}</span>
    </div>
  )
}

export function SectionTitle({ children, aside }: { children: ReactNode; aside?: ReactNode }) {
  return (
    <div className="mb-2 flex items-baseline justify-between gap-3">
      <h4 className="text-[13px] font-semibold text-text">{children}</h4>
      {aside && <span className="truncate text-[11px] text-text-2">{aside}</span>}
    </div>
  )
}

/** A history chart's time axis. */
export function Axis({ labels }: { labels: readonly string[] }) {
  return (
    <div className="mt-1.5 flex justify-between text-[10px] text-text-3" aria-hidden="true">
      {labels.map((l) => (
        <span key={l}>{l}</span>
      ))}
    </div>
  )
}
