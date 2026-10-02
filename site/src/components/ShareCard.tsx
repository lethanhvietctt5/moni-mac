import { cardPalettes, mac, weekly } from '../data/sample'
import { useFitWidth } from '../hooks/useFitWidth'
import { metricIcon } from '../lib/metricIcons'
import { LaptopIcon } from './icons'

const WIDTH = 1200
const HEIGHT = 630

/**
 * The weekly share card at its real 1200 × 630 size, scaled to fit.
 * Like the app, it uses fixed light and dark palettes rather than the page's.
 */
export function ShareCard({ variant }: { variant: 'light' | 'dark' }) {
  const [ref, scale] = useFitWidth<HTMLDivElement>(WIDTH)
  const p = cardPalettes[variant]

  return (
    <div ref={ref} className="w-full">
      <div
        className="relative overflow-hidden rounded-[18px] shadow-[0_30px_80px_-24px_rgba(0,0,0,0.4)]"
        style={{ height: HEIGHT * scale, outline: `1px solid ${p.stroke}` }}
      >
        <div
          className="absolute top-0 left-0 origin-top-left"
          style={{ width: WIDTH, height: HEIGHT, transform: `scale(${scale})`, background: p.background, color: p.textPrimary, transition: 'background 300ms, color 300ms' }}
        >
          <div className="flex h-full flex-col px-14 pt-12 pb-11">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3.5">
                <img src="/icon-256.webp" alt="" width={44} height={44} className="size-11" />
                <span className="text-[24px] font-semibold tracking-tight">MoniMac</span>
              </div>
              <span className="flex items-center gap-2 text-[16px]" style={{ color: p.textSecondary }}>
                <LaptopIcon size={18} />
                {mac.subtitle}
              </span>
            </div>
            <div className="mt-14 text-[14px] font-semibold tracking-[0.08em]" style={{ color: p.accent }}>
              {weekly.range}
            </div>
            <div className="mt-3 text-[60px] leading-none font-bold tracking-[-0.02em]">{weekly.headline}</div>
            <p className="mt-5 max-w-[640px] text-[19px] leading-snug" style={{ color: p.textSecondary }}>
              {weekly.summary}
            </p>
            <div className="mt-auto grid grid-cols-5 gap-4">
              {weekly.stats.map((s) => {
                const Icon = metricIcon[s.metric]
                const color = p.metrics[s.metric]
                return (
                  <div key={s.label} className="rounded-2xl p-4" style={{ background: p.tile, outline: `1px solid ${p.stroke}` }}>
                    <div className="flex items-center gap-1.5 text-[13px] font-medium" style={{ color: p.textSecondary }}>
                      <Icon size={14} style={{ color }} />
                      {s.label}
                    </div>
                    <div className="mt-1.5 text-[28px] font-semibold tracking-tight">{s.value}</div>
                    <div className="mt-2.5 flex h-7 items-end gap-[3px]">
                      {s.spark.map((v, i) => (
                        <div key={i} className="flex-1 rounded-[2px]" style={{ height: `${v}%`, background: color }} />
                      ))}
                    </div>
                    <div className="mt-2 text-[12px]" style={{ color: p.textSecondary }}>
                      {s.caption}
                    </div>
                  </div>
                )
              })}
            </div>
            <div className="mt-9 flex items-center justify-between text-[15px]">
              <span style={{ color: p.textSecondary }}>{weekly.busiest}</span>
              <span style={{ color: p.textTertiary }}>github.com/lethanhvietctt5/moni-mac</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
