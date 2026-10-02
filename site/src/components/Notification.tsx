import { metricColor, type Metric, type SampleApp } from '../data/sample'
import { metricIcon } from '../lib/metricIcons'
import { AppGlyph } from './ui'

/** A macOS notification banner from MoniMac. */
export function Notification({
  title,
  body,
  chip,
  metric,
  app,
  actions,
}: {
  title: string
  body: string
  chip: string
  metric: Metric
  app: SampleApp
  actions?: readonly string[]
}) {
  const Icon = metricIcon[metric]
  return (
    <div className="w-full max-w-[400px] overflow-hidden rounded-[18px] border border-black/5 bg-white/85 text-[#1d1d1f] shadow-[0_12px_40px_-12px_rgba(0,0,0,0.35)] backdrop-blur-2xl dark:border-white/10 dark:bg-[#2c2c30]/85 dark:text-[#f5f5f7]">
      <div className="flex gap-3 p-3.5">
        <img src="/icon-256.webp" alt="" width={36} height={36} className="size-9 shrink-0" />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-2">
            <span className="text-[13.5px] leading-snug font-semibold">{title}</span>
            <span className="shrink-0 text-[11.5px] opacity-50">now</span>
          </div>
          <p className="mt-0.5 text-[12.5px] leading-snug opacity-80">{body}</p>
          <span
            className="mt-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11.5px] font-semibold"
            style={{ color: metricColor[metric], background: `color-mix(in srgb, ${metricColor[metric]} 14%, transparent)` }}
          >
            <Icon size={12} strokeWidth={2.2} />
            {chip}
          </span>
        </div>
        <AppGlyph app={app} size={36} />
      </div>
      {actions && (
        <div className="grid grid-cols-2 border-t border-black/5 text-[13px] font-medium dark:border-white/10" aria-hidden="true">
          <span className="py-2.5 text-center text-[#e5484d]">{actions[0]}</span>
          <span className="border-l border-black/5 py-2.5 text-center text-accent dark:border-white/10">{actions[1]}</span>
        </div>
      )}
    </div>
  )
}
