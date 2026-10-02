import { AnimatePresence, m, useInView, useReducedMotion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { groupedApps, processTotals, rawProcesses, type AppKind } from '../data/sample'
import { ChevronRightIcon } from './icons'
import { Reveal, Section } from './Section'
import { AppGlyph } from './ui'

const kindStyle: Record<AppKind, string> = {
  app: 'bg-cpu/15 text-cpu',
  agent: 'bg-memory/15 text-memory',
  system: 'bg-text-3/20 text-text-2',
}

const kinds: Array<{ kind: AppKind; count: number; label: string; detail: string; color: string }> = [
  { kind: 'app', count: processTotals.split.app, label: 'apps', detail: 'Anything with a Dock app among its processes.', color: 'var(--cpu)' },
  { kind: 'agent', count: processTotals.split.agent, label: 'agents', detail: 'Background helpers, menu bar extras, and daemons you installed.', color: 'var(--memory)' },
  { kind: 'system', count: processTotals.split.system, label: 'system', detail: 'Parts of macOS, or processes owned by another user.', color: 'var(--text-3)' },
]

const rowMotion = {
  initial: { opacity: 0, height: 0 },
  animate: { opacity: 1, height: 'auto' },
  exit: { opacity: 0, height: 0 },
}

function Switch({ on, onChange, label }: { on: boolean; onChange: (on: boolean) => void; label: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      onClick={() => onChange(!on)}
      className="flex items-center gap-2.5 rounded-full text-[13px] text-text"
    >
      <span className={`flex h-[22px] w-[38px] items-center rounded-full p-[2px] transition-colors ${on ? 'bg-success' : 'bg-track'}`}>
        <span className={`size-[18px] rounded-full bg-white shadow transition-transform ${on ? 'translate-x-4' : ''}`} />
      </span>
      {label}
    </button>
  )
}

export function Grouping() {
  const [grouped, setGrouped] = useState(false)
  const [touched, setTouched] = useState(false)
  const [expanded, setExpanded] = useState<string | null>('Google Chrome')
  const panelRef = useRef<HTMLDivElement>(null)
  const inView = useInView(panelRef, { once: true, amount: 0.5 })
  const reduced = useReducedMotion()

  // Group the list once it's in view, unless the visitor got there first.
  useEffect(() => {
    if (!inView || touched || reduced) return
    const timer = window.setTimeout(() => setGrouped(true), 1400)
    return () => window.clearTimeout(timer)
  }, [inView, touched, reduced])

  const total = processTotals.split.app + processTotals.split.agent + processTotals.split.system

  return (
    <Section
      eyebrow="Grouped by app"
      title={
        <>
          {processTotals.processes} processes.{' '}
          <span className="text-ink-3">{processTotals.apps} apps.</span>
        </>
      }
      intro="A modern Mac runs a thousand processes, most of them helpers with names you've never seen. MoniMac rolls every helper up into the app it works for, so the list reads like your Dock."
    >
      <div className="mt-12 grid grid-cols-1 items-start gap-10 sm:mt-16 lg:grid-cols-[1fr_1.25fr] lg:gap-14">
        <Reveal className="space-y-6 lg:pt-6">
          <div>
            <div className="flex h-3 gap-[3px] overflow-hidden rounded-full" aria-hidden="true">
              {kinds.map((k) => (
                <div key={k.kind} style={{ width: `${(k.count / total) * 100}%`, background: k.color }} />
              ))}
            </div>
            <p className="mt-2 text-[13px] text-ink-3">
              {processTotals.apps} groups: {processTotals.split.app} apps, {processTotals.split.agent} agents, {processTotals.split.system} system
            </p>
          </div>
          <dl className="space-y-4">
            {kinds.map((k) => (
              <div key={k.kind} className="flex gap-3">
                <span className="mt-1.5 size-2.5 shrink-0 rounded-full" style={{ background: k.color }} />
                <div>
                  <dt className="text-[15px] font-semibold text-ink">
                    {k.count} {k.label}
                  </dt>
                  <dd className="text-[15px] text-ink-2">{k.detail}</dd>
                </div>
              </div>
            ))}
          </dl>
          <p className="text-[15px] leading-relaxed text-ink-2">
            Expand any app to see which helper is heavy. Quitting always targets the app itself, never a stray helper, and
            asks before it does.
          </p>
        </Reveal>

        <Reveal>
          <div ref={panelRef} className="overflow-hidden rounded-[14px] border border-sep bg-win text-text shadow-[0_24px_70px_-24px_rgba(0,0,0,0.3)]">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-sep px-4 py-3">
              <div>
                <div className="text-[14px] font-semibold" aria-live="polite">
                  {grouped ? `${processTotals.apps} apps` : `${processTotals.processes} processes`}
                </div>
                <div className="text-[11.5px] text-text-2">{grouped ? 'Sorted by CPU' : 'One row per process'}</div>
              </div>
              <Switch
                on={grouped}
                label="Group processes by app"
                onChange={(on) => {
                  setTouched(true)
                  setGrouped(on)
                }}
              />
            </div>
            <div className="h-[420px] overflow-hidden px-2 py-1.5">
              <AnimatePresence mode="wait" initial={false}>
                {grouped ? (
                  <m.ul key="grouped" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
                    {groupedApps.map((g, i) => {
                      const open = expanded === g.app.name
                      const helperCount = g.helpers.reduce((n, h) => n + h.count, 0)
                      return (
                        <m.li
                          key={g.app.name}
                          {...rowMotion}
                          transition={{ duration: 0.35, delay: i * 0.06, ease: [0.22, 1, 0.36, 1] }}
                          className="overflow-hidden"
                        >
                          <button
                            type="button"
                            aria-expanded={open}
                            onClick={() => setExpanded(open ? null : g.app.name)}
                            className="flex w-full items-center gap-2.5 rounded-lg px-2 py-2 text-left hover:bg-surface"
                          >
                            <ChevronRightIcon size={13} className={`shrink-0 text-text-3 transition-transform ${open ? 'rotate-90' : ''}`} />
                            <AppGlyph app={g.app} size={26} />
                            <span className="min-w-0 flex-1 truncate text-[13.5px] font-medium">{g.app.name}</span>
                            <span className={`hidden rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase min-[400px]:inline ${kindStyle[g.kind]}`}>
                              {g.kind}
                            </span>
                            <span className="w-14 text-right text-[12px] text-text-2 tabular-nums">{helperCount} procs</span>
                            <span className="w-12 text-right text-[13px] font-semibold tabular-nums">{g.cpu}</span>
                          </button>
                          <AnimatePresence initial={false}>
                            {open && (
                              <m.ul {...rowMotion} transition={{ duration: 0.25 }} className="overflow-hidden">
                                {g.helpers.map((h) => (
                                  <li key={h.name} className="flex items-center gap-2.5 py-1.5 pr-2 pl-9 text-[12px] text-text-2 sm:pl-[62px]">
                                    <span className="min-w-0 flex-1 sm:truncate">{h.name}</span>
                                    <span className="w-14 text-right tabular-nums">{h.count}</span>
                                    <span className="w-12 text-right tabular-nums">{h.cpu}</span>
                                  </li>
                                ))}
                              </m.ul>
                            )}
                          </AnimatePresence>
                        </m.li>
                      )
                    })}
                    <m.li
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ delay: 0.4 }}
                      className="px-2 pt-2 text-[11.5px] text-text-3"
                    >
                      Showing 5 of {processTotals.apps} apps · {processTotals.processes} processes grouped
                    </m.li>
                  </m.ul>
                ) : (
                  <m.ul key="raw" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
                    {rawProcesses.slice(0, 15).map((p, i) => (
                      <m.li
                        key={p.pid}
                        initial={{ opacity: 1, height: 'auto' }}
                        exit={{ opacity: 0, height: 0 }}
                        transition={{ duration: 0.25, delay: i * 0.015 }}
                        className="flex items-center gap-3 overflow-hidden rounded px-2 py-[5px] font-mono text-[11.5px] odd:bg-surface"
                      >
                        <span className="w-10 shrink-0 text-right text-text-3 tabular-nums">{p.pid}</span>
                        <span className="min-w-0 flex-1 truncate">{p.name}</span>
                        <span className="w-10 text-right text-text-2 tabular-nums">{p.cpu}</span>
                      </m.li>
                    ))}
                    <li className="px-2 pt-1.5 font-mono text-[11.5px] text-text-3">… and 1,033 more</li>
                  </m.ul>
                )}
              </AnimatePresence>
            </div>
          </div>
        </Reveal>
      </div>
    </Section>
  )
}
