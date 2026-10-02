import { useState } from 'react'
import { useLiveTick } from '../hooks/useLiveTick'
import { CommandIcon, WarningIcon } from './icons'
import { MenuBar, MenuBarStrip, MenuItem, WarningItem, type MenuMetric, type MenuStyle } from './MenuBar'
import { Reveal, Section } from './Section'

const styles: Array<{ id: MenuStyle; label: string; hint: string }> = [
  { id: 'value', label: 'Value', hint: 'Compact numbers that keep their width' },
  { id: 'graph', label: 'Graph', hint: 'The last 60 seconds as a sparkline' },
  { id: 'both', label: 'Both', hint: 'Most information, most width' },
]

const metricLabels: Record<MenuMetric, string> = {
  cpu: 'CPU',
  memory: 'Memory',
  network: 'Network',
  gpu: 'GPU',
  temp: 'Temperature',
}
const order: MenuMetric[] = ['cpu', 'memory', 'network', 'gpu', 'temp']

export function MenuBarSection() {
  const [style, setStyle] = useState<MenuStyle>('both')
  const [enabled, setEnabled] = useState<Record<MenuMetric, boolean>>({ cpu: true, memory: true, network: true, gpu: false, temp: false })
  const [ref, tick] = useLiveTick<HTMLDivElement>(2000)
  const metrics = order.filter((m) => enabled[m])

  return (
    <Section
      eyebrow="Menu bar"
      title="Only what you want, where you want it."
      intro="Each metric is its own menu bar item. Turn on the ones you care about and pick how each one looks. Click any of them for the popover."
    >
      <div ref={ref} className="mt-12 grid grid-cols-1 gap-5 sm:mt-16 lg:grid-cols-2">
        <Reveal className="lg:col-span-2">
          <div className="bg-wallpaper overflow-hidden rounded-2xl border border-line">
            <MenuBar metrics={metrics} style={style} tick={tick} className="rounded-none" />
            <div className="flex flex-col gap-6 p-5 sm:flex-row sm:items-start sm:justify-between sm:p-7">
              <fieldset>
                <legend className="mb-2 text-[13px] font-semibold text-menubar-fg">Style</legend>
                <div className="inline-flex rounded-xl bg-black/10 p-1 backdrop-blur dark:bg-white/10">
                  {styles.map((s) => (
                    <button
                      key={s.id}
                      type="button"
                      aria-pressed={style === s.id}
                      onClick={() => setStyle(s.id)}
                      className={`rounded-lg px-4 py-1.5 text-[13px] font-medium transition-colors ${
                        style === s.id ? 'bg-white text-[#1d1d1f] shadow-sm' : 'text-menubar-fg hover:bg-white/20'
                      }`}
                    >
                      {s.label}
                    </button>
                  ))}
                </div>
                <p className="mt-2 text-[12.5px] text-menubar-fg/75">{styles.find((s) => s.id === style)?.hint}</p>
              </fieldset>
              <fieldset>
                <legend className="mb-2 text-[13px] font-semibold text-menubar-fg">Items</legend>
                <div className="flex flex-wrap gap-2">
                  {order.map((metric) => (
                    <button
                      key={metric}
                      type="button"
                      role="switch"
                      aria-checked={enabled[metric]}
                      onClick={() => setEnabled((e) => ({ ...e, [metric]: !e[metric] }))}
                      className={`flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[13px] font-medium transition-colors ${
                        enabled[metric]
                          ? 'border-transparent bg-white text-[#1d1d1f] shadow-sm'
                          : 'border-menubar-fg/25 text-menubar-fg hover:bg-white/15'
                      }`}
                    >
                      <span
                        className={`size-1.5 rounded-full ${enabled[metric] ? 'bg-success' : 'bg-menubar-fg/40'}`}
                        aria-hidden="true"
                      />
                      {metricLabels[metric]}
                    </button>
                  ))}
                </div>
              </fieldset>
            </div>
          </div>
        </Reveal>

        <Reveal>
          <div className="bg-wallpaper flex h-full flex-col overflow-hidden rounded-2xl border border-line">
            <MenuBarStrip>
              <WarningItem />
              <MenuItem metric="memory" style="both" tick={tick} />
            </MenuBarStrip>
            <div className="flex justify-end px-3 pt-2">
              <div className="flex max-w-[300px] gap-2.5 rounded-xl border border-black/5 bg-white/90 p-3 text-[#1d1d1f] shadow-lg backdrop-blur dark:border-white/10 dark:bg-[#2a2a2e]/90 dark:text-[#f5f5f7]">
                <WarningIcon size={17} className="mt-0.5 shrink-0 text-[#e08600] dark:text-[#ffb340]" />
                <div>
                  <div className="text-[13px] font-semibold">CPU above 90% for 2 min</div>
                  <div className="text-[12px] opacity-70">Xcode is using 71% · click for details</div>
                </div>
              </div>
            </div>
            <div className="mt-auto p-5 pt-6">
              <h3 className="text-[17px] font-semibold text-menubar-fg">A warning when it matters</h3>
              <p className="mt-1 text-[14px] leading-relaxed text-menubar-fg/80">
                When the system is under strain, the item turns into a warning badge. Hover or click it to see the cause.
              </p>
            </div>
          </div>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="bg-wallpaper flex h-full flex-col overflow-hidden rounded-2xl border border-line">
            <MenuBarStrip>
              <span className="rounded-[5px] bg-white/80 shadow-sm ring-1 ring-black/5 dark:bg-white/20">
                <MenuItem metric="memory" style="value" tick={tick} />
              </span>
              <span className="h-4 w-[2px] rounded bg-accent" aria-hidden="true" />
              <MenuItem metric="cpu" style="value" tick={tick} />
              <MenuItem metric="network" style="value" tick={tick} />
            </MenuBarStrip>
            <div className="flex justify-end px-3 pt-2">
              <div className="flex items-center gap-2.5 rounded-xl border border-black/5 bg-white/90 p-3 text-[13px] text-[#1d1d1f] shadow-lg dark:border-white/10 dark:bg-[#2a2a2e]/90 dark:text-[#f5f5f7]">
                <kbd className="flex size-7 items-center justify-center rounded-md border border-black/10 bg-white font-sans shadow-sm dark:border-white/15 dark:bg-white/10">
                  <CommandIcon size={14} />
                  <span className="sr-only">Command</span>
                </kbd>
                Hold ⌘ and drag
              </div>
            </div>
            <div className="mt-auto p-5 pt-6">
              <h3 className="text-[17px] font-semibold text-menubar-fg">Reorder like any menu bar icon</h3>
              <p className="mt-1 text-[14px] leading-relaxed text-menubar-fg/80">
                Hold ⌘ and drag a MoniMac item to move it, the same way you arrange any menu bar icon. Turn items on or
                off in Settings.
              </p>
            </div>
          </div>
        </Reveal>
      </div>
    </Section>
  )
}

