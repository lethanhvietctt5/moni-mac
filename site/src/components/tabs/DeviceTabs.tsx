import {
  battery,
  batteryAxis,
  batteryHistory,
  bluetooth,
  energy,
  metricColor,
  sound,
  tempHistory,
  thermal,
} from '../../data/sample'
import { fixed, wobble } from '../../lib/live'
import {
  FanIcon,
  GamepadIcon,
  HeadphonesIcon,
  InfoIcon,
  KeyboardIcon,
  MouseIcon,
  SpeakerIcon,
  SpeakerMuteIcon,
  TrackpadIcon,
} from '../icons'
import { AppGlyph, AppRow, Axis, Card, Meter, MetricLabel, RangePicker, SectionTitle } from '../ui'

type TabProps = { tick: number }

function Figure({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <Card>
      <div className="text-[12px] text-text-2">{label}</div>
      <div className="mt-1 text-[24px] font-semibold tracking-tight tabular-nums">{value}</div>
      <div className="truncate text-[11px] text-text-2">{note}</div>
    </Card>
  )
}

export function BatteryTab({ tick }: TabProps) {
  const draw = wobble(battery.drawW, 0.15, 40, tick)
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-[1.4fr_1fr_1fr_1fr_1fr] sm:items-stretch">
        <Card className="col-span-full sm:col-span-1">
          <MetricLabel metric="battery">Power Adapter · {battery.adapter}</MetricLabel>
          <div className="mt-1 text-[34px] leading-none font-semibold tracking-tight">{battery.percent}%</div>
          <Meter fraction={battery.percent / 100} color={metricColor.battery} className="mt-2.5 h-2" />
          <div className="mt-1.5 text-[11px] text-text-2">Full in {battery.fullIn}</div>
        </Card>
        <Figure label="Power Draw" value={`${fixed(draw)} W`} note={`System using ${battery.systemW} W`} />
        <Figure label="Health" value={`${battery.health}%`} note={`${battery.currentMah} of ${battery.designMah} mAh`} />
        <Figure label="Cycle Count" value={`${battery.cycles}`} note={`of ${battery.ratedCycles} rated`} />
        <Figure label="Temperature" value={`${battery.tempC} °C`} note="Within normal range" />
      </div>
      <div className="grid grid-cols-1 gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
            <SectionTitle>Charge Level</SectionTitle>
            <RangePicker />
          </div>
          <p className="mb-3 text-[11px] text-text-2">Plugged in 2 times · Avg drain 9.8 %/h on battery</p>
          <div className="flex h-28 items-end gap-[3px]" aria-hidden="true">
            {batteryHistory.map(([level, charging], i) => (
              <div
                key={i}
                className="flex-1 rounded-t-[2px]"
                style={{ height: `${level}%`, background: charging ? 'var(--battery)' : 'color-mix(in srgb, var(--battery) 40%, transparent)' }}
              />
            ))}
          </div>
          <Axis labels={batteryAxis} />
          <div className="mt-2 flex gap-4 text-[10.5px] text-text-2">
            <span className="flex items-center gap-1.5"><span className="size-2 rounded-[2px] bg-battery" />Charging</span>
            <span className="flex items-center gap-1.5"><span className="size-2 rounded-[2px] bg-battery/40" />On battery</span>
          </div>
        </Card>
        <div>
          <SectionTitle aside="Watts">Using Significant Energy</SectionTitle>
          {energy.map((app) => (
            <AppRow key={app.name} app={app} value={`${fixed(app.power ?? 0)} W`} fraction={(app.power ?? 0) / 5} color={metricColor.battery} />
          ))}
        </div>
      </div>
    </div>
  )
}

function Ring({ percent, label }: { percent: number; label: string }) {
  const r = 26
  const c = 2 * Math.PI * r
  const color = percent < 20 ? 'var(--danger)' : percent < 50 ? 'var(--warning)' : 'var(--battery)'
  return (
    <div className="flex flex-col items-center gap-1">
      <div className="relative size-16">
        <svg viewBox="0 0 64 64" className="size-16 -rotate-90" aria-hidden="true">
          <circle cx="32" cy="32" r={r} fill="none" stroke="var(--track)" strokeWidth="5" />
          <circle cx="32" cy="32" r={r} fill="none" stroke={color} strokeWidth="5" strokeLinecap="round" strokeDasharray={`${(percent / 100) * c} ${c}`} />
        </svg>
        <span className="absolute inset-0 flex items-center justify-center text-[14px] font-semibold">{percent}%</span>
      </div>
      <span className="text-[11px] text-text-2">{label}</span>
    </div>
  )
}

const deviceIcons = { keyboard: KeyboardIcon, trackpad: TrackpadIcon, mouse: MouseIcon, gamepad: GamepadIcon }

export function BluetoothTab() {
  const { airpods, devices } = bluetooth
  return (
    <div className="space-y-5">
      <Card className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center">
        <div className="flex items-center gap-4">
          <span className="flex size-16 shrink-0 items-center justify-center rounded-2xl border border-sep bg-surface-raised text-text">
            <HeadphonesIcon size={30} strokeWidth={1.6} />
          </span>
          <div className="min-w-0">
            <div className="text-[17px] font-semibold">{airpods.name}</div>
            <div className="mt-0.5 flex items-center gap-1.5 text-[12px] text-text-2">
              <span className="size-1.5 rounded-full bg-success" />
              {airpods.status}
            </div>
            <div className="mt-0.5 text-[11px] text-text-3">{airpods.detail}</div>
          </div>
        </div>
        <div className="flex justify-around gap-3 sm:ml-auto sm:justify-end">
          <Ring percent={airpods.left} label="Left" />
          <Ring percent={airpods.right} label="Right" />
          <Ring percent={airpods.case} label="Case" />
        </div>
      </Card>
      <div>
        <SectionTitle aside={<span className="text-accent">Open Bluetooth Settings…</span>}>Other Devices</SectionTitle>
        <div className="divide-y divide-sep overflow-hidden rounded-xl border border-sep">
          {devices.map((d) => {
            const Icon = deviceIcons[d.icon]
            const low = d.percent < 20
            return (
              <div key={d.name} className={`flex items-center gap-3 px-3.5 py-2.5 ${d.connected ? '' : 'opacity-60'}`}>
                <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-surface text-text-2">
                  <Icon size={17} />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[13px] font-medium">{d.name}</div>
                  <div className="truncate text-[11px] text-text-2">
                    {d.kind} · {d.connected ? 'Connected' : 'Not connected'}
                  </div>
                </div>
                <span className={`hidden text-[11px] sm:inline ${low ? 'text-danger' : 'text-text-2'}`}>{d.hint}</span>
                <span className="relative h-3 w-7 rounded-[3px] border border-text-3/60 p-[1.5px]" aria-hidden="true">
                  <span
                    className="block h-full rounded-[1.5px]"
                    style={{ width: `${d.percent}%`, background: !d.connected ? 'var(--text-3)' : low ? 'var(--danger)' : 'var(--battery)' }}
                  />
                </span>
                <span className="w-9 text-right text-[13px] font-semibold tabular-nums">{d.percent}%</span>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

export function SoundTab() {
  return (
    <div className="space-y-5">
      <Card className="flex items-center gap-4">
        <span className="flex size-10 items-center justify-center rounded-xl bg-accent text-white">
          <SpeakerIcon size={20} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="text-[14px] font-semibold">{sound.output}</div>
          <div className="text-[11px] text-text-2">Output · {sound.sampleRate} · System volume</div>
          <Meter fraction={sound.systemVolume / 100} color="var(--accent)" className="mt-2 h-1.5 max-w-sm" />
        </div>
        <span className="text-[15px] font-semibold tabular-nums">{sound.systemVolume}%</span>
      </Card>
      <div>
        <SectionTitle aside={<span className="text-accent">Reset All to 100%</span>}>Per-App Volume</SectionTitle>
        <div className="divide-y divide-sep overflow-hidden rounded-xl border border-sep">
          {sound.apps.map(({ app, state, volume }) => {
            const muted = state === 'Muted'
            return (
              <div key={app.name} className="flex items-center gap-3 px-3.5 py-2.5">
                <AppGlyph app={app} size={26} />
                <div className="w-28 min-w-0 shrink-0 sm:w-36">
                  <div className="truncate text-[13px]">{app.name}</div>
                  <div className={`text-[11px] ${state === 'Playing' ? 'text-success' : muted ? 'text-danger' : 'text-text-3'}`}>{state}</div>
                </div>
                <div className="relative flex-1">
                  <Meter fraction={muted ? 0 : volume / 100} color="var(--accent)" className="h-1.5" />
                  {!muted && (
                    <span
                      className="absolute top-1/2 size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border border-sep bg-white shadow"
                      style={{ left: `${volume}%` }}
                      aria-hidden="true"
                    />
                  )}
                </div>
                <span className="w-10 text-right text-[12px] tabular-nums text-text-2">{muted ? '—' : `${volume}%`}</span>
                <span className={muted ? 'text-danger' : 'text-text-3'}>
                  {muted ? <SpeakerMuteIcon size={16} /> : <SpeakerIcon size={16} />}
                </span>
              </div>
            )
          })}
        </div>
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Toggle title="Duck background apps" detail="Lower other apps by 50% while a call is active" on />
        <Toggle title="Mute new apps by default" detail="Apps that start playing for the first time stay muted" />
      </div>
    </div>
  )
}

function Toggle({ title, detail, on = false }: { title: string; detail: string; on?: boolean }) {
  return (
    <Card className="flex items-center gap-3">
      <div className="min-w-0 flex-1">
        <div className="text-[13px] font-medium">{title}</div>
        <div className="text-[11px] text-text-2">{detail}</div>
      </div>
      <span className={`flex h-[22px] w-[38px] shrink-0 items-center rounded-full p-[2px] ${on ? 'justify-end bg-success' : 'bg-track'}`} aria-hidden="true">
        <span className="size-[18px] rounded-full bg-white shadow" />
      </span>
    </Card>
  )
}

function Gauge({ value }: { value: number }) {
  return (
    <div className="relative mt-2.5 h-1.5 rounded-full bg-[linear-gradient(90deg,#40c8e0,#34c759_35%,#ffd60a_60%,#ff9f0a_78%,#ff453a)]" aria-hidden="true">
      <span className="absolute top-1/2 h-3.5 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-text shadow" style={{ left: `${(value / 105) * 100}%` }} />
    </div>
  )
}

export function TemperatureTab({ tick }: TabProps) {
  const cpuTemp = Math.round(wobble(thermal.cards[0].value, 0.04, 5, tick))
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {thermal.cards.map((card, i) => {
          const value = i === 0 ? cpuTemp : card.value
          return (
            <Card key={card.label}>
              <MetricLabel metric="temp">{card.label}</MetricLabel>
              <div className="mt-1 text-[28px] leading-none font-semibold tabular-nums">
                {value}
                <span className="align-top text-[13px] font-medium text-text-2">°C</span>
              </div>
              <Gauge value={value} />
              <div className="mt-2 text-[11px] text-text-2">{card.note}</div>
            </Card>
          )
        })}
      </div>
      <div className="grid grid-cols-1 gap-5 md:grid-cols-[1.4fr_1fr]">
        <Card className="bg-transparent">
          <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
            <SectionTitle>CPU Temperature</SectionTitle>
            <RangePicker />
          </div>
          <p className="mb-3 truncate text-[11px] text-text-2">{thermal.summary}</p>
          <div className="flex h-32 items-end gap-[3px]" aria-hidden="true">
            {tempHistory.map((t, i) => (
              <div
                key={i}
                className="flex-1 rounded-t-[2px]"
                style={{ height: `${((t - 30) / 55) * 100}%`, background: t >= 75 ? 'var(--temp)' : t >= 60 ? 'var(--gpu)' : 'var(--network)' }}
              />
            ))}
          </div>
          <Axis labels={['10:00', '16:00', '22:00', '04:00', 'Now']} />
        </Card>
        <Card>
          <div className="mb-2 flex items-baseline justify-between">
            <span className="text-[13px] font-semibold">Fans</span>
            <span className="text-[11px] text-text-2">Managed by macOS</span>
          </div>
          {thermal.fans.map((fan, i) => {
            const rpm = Math.round(wobble(fan.rpm, 0.03, 50 + i, tick) / 10) * 10
            return (
              <div key={fan.name} className="border-b border-sep py-2.5 last:border-0">
                <div className="flex items-center gap-2.5">
                  <FanIcon size={22} className="text-network" />
                  <div className="flex-1">
                    <div className="text-[11px] text-text-2">{fan.name}</div>
                    <div className="text-[18px] font-semibold tabular-nums">
                      {rpm.toLocaleString('en-US')} <span className="text-[10px] font-medium text-text-2">RPM</span>
                    </div>
                  </div>
                  <span className="text-[12px] font-semibold text-network tabular-nums">{Math.round((rpm / fan.max) * 100)}%</span>
                </div>
                <Meter fraction={rpm / fan.max} color="var(--network)" className="mt-1.5 h-1" />
              </div>
            )
          })}
          <p className="mt-2 flex gap-1.5 rounded-lg bg-track/60 p-2 text-[11px] text-text-2">
            <InfoIcon size={14} className="mt-px shrink-0" />
            Read-only. MoniMac shows fan speeds but doesn't control them.
          </p>
        </Card>
      </div>
      <div className="grid grid-cols-1 gap-x-6 sm:grid-cols-3">
        {thermal.sensors.map(([name, value]) => (
          <div key={name} className="flex justify-between border-b border-sep py-1.5 text-[12px]">
            <span className="text-text-2">{name}</span>
            <span className="font-semibold tabular-nums">{value}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
