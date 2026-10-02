import { AnimatePresence, m } from 'motion/react'
import { useRef, type ComponentType, type KeyboardEvent, type ReactNode, type SVGProps } from 'react'
import { bluetooth, cpu, disk, gpu, mac, memory, network, projects, release, sound, thermal } from '../data/sample'
import {
  BatteryIcon,
  BluetoothIcon,
  CpuIcon,
  DiskIcon,
  FolderCodeIcon,
  GearIcon,
  GpuIcon,
  GridIcon,
  ListIcon,
  MemoryIcon,
  NetworkIcon,
  ShareIcon,
  SpeakerIcon,
  ThermometerIcon,
} from './icons'
import { BatteryTab, BluetoothTab, SoundTab, TemperatureTab } from './tabs/DeviceTabs'
import { CPUTab, DiskTab, GPUTab, MemoryTab, NetworkTab, OverviewTab } from './tabs/MonitorTabs'
import { ProjectsView } from './tabs/ProjectsView'
import { SettingsTab } from './tabs/SettingsTab'

type Icon = ComponentType<SVGProps<SVGSVGElement> & { size?: number }>

interface WindowTab {
  id: string
  label: string
  group: 'Monitor' | 'Devices' | 'Developer' | 'Settings'
  icon: Icon
  subtitle: string
  render: (tick: number) => ReactNode
}

const windowTabs: WindowTab[] = [
  { id: 'overview', label: 'Overview', group: 'Monitor', icon: GridIcon, subtitle: mac.subtitle, render: (t) => <OverviewTab tick={t} /> },
  { id: 'cpu', label: 'CPU', group: 'Monitor', icon: CpuIcon, subtitle: cpu.name, render: (t) => <CPUTab tick={t} /> },
  { id: 'memory', label: 'Memory', group: 'Monitor', icon: MemoryIcon, subtitle: memory.type, render: (t) => <MemoryTab tick={t} /> },
  { id: 'gpu', label: 'GPU', group: 'Monitor', icon: GpuIcon, subtitle: gpu.name, render: (t) => <GPUTab tick={t} /> },
  { id: 'network', label: 'Network', group: 'Monitor', icon: NetworkIcon, subtitle: network.link, render: (t) => <NetworkTab tick={t} /> },
  { id: 'disk', label: 'Disk', group: 'Monitor', icon: DiskIcon, subtitle: disk.volume, render: (t) => <DiskTab tick={t} /> },
  { id: 'battery', label: 'Battery', group: 'Devices', icon: BatteryIcon, subtitle: 'Charging · 1 h 12 min until full', render: (t) => <BatteryTab tick={t} /> },
  { id: 'bluetooth', label: 'Bluetooth', group: 'Devices', icon: BluetoothIcon, subtitle: `${bluetooth.devices.filter((d) => d.connected).length + 1} devices connected`, render: () => <BluetoothTab /> },
  { id: 'sound', label: 'Sound', group: 'Devices', icon: SpeakerIcon, subtitle: sound.summary, render: () => <SoundTab /> },
  { id: 'temperature', label: 'Temperature & Fans', group: 'Devices', icon: ThermometerIcon, subtitle: `Thermal state: ${thermal.state} · 2 fans`, render: (t) => <TemperatureTab tick={t} /> },
  { id: 'projects', label: 'Projects', group: 'Developer', icon: FolderCodeIcon, subtitle: projects.summary, render: () => <ProjectsView /> },
  { id: 'settings', label: 'Settings', group: 'Settings', icon: GearIcon, subtitle: `MoniMac ${release.version}`, render: () => <SettingsTab /> },
]

const groups = ['Monitor', 'Devices', 'Developer'] as const

/**
 * A recreation of MoniMac's main window: sidebar tabs, a toolbar, and the
 * selected tab's content. The sidebar is a keyboard-operable tab list
 * (arrow keys, Home, End); on narrow screens it becomes a scrolling strip.
 */
export function AppWindow({
  selected,
  onSelect,
  tick,
}: {
  selected: string
  onSelect: (id: string) => void
  tick: number
}) {
  const tabRefs = useRef<Record<string, HTMLButtonElement | null>>({})
  const current = windowTabs.find((t) => t.id === selected) ?? windowTabs[0]

  const focusTab = (index: number) => {
    const tab = windowTabs[(index + windowTabs.length) % windowTabs.length]
    onSelect(tab.id)
    tabRefs.current[tab.id]?.focus()
  }

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const index = windowTabs.findIndex((t) => t.id === selected)
    const keys: Record<string, () => void> = {
      ArrowDown: () => focusTab(index + 1),
      ArrowRight: () => focusTab(index + 1),
      ArrowUp: () => focusTab(index - 1),
      ArrowLeft: () => focusTab(index - 1),
      Home: () => focusTab(0),
      End: () => focusTab(windowTabs.length - 1),
    }
    const action = keys[event.key]
    if (action) {
      event.preventDefault()
      action()
    }
  }

  const tabButton = (tab: WindowTab) => {
    const isSelected = tab.id === selected
    const TabIcon = tab.icon
    return (
      <button
        key={tab.id}
        ref={(el) => {
          tabRefs.current[tab.id] = el
        }}
        type="button"
        role="tab"
        id={`tab-${tab.id}`}
        aria-selected={isSelected}
        aria-controls="window-panel"
        tabIndex={isSelected ? 0 : -1}
        onClick={() => onSelect(tab.id)}
        className={`flex shrink-0 items-center gap-2 rounded-md px-2.5 py-[5px] text-left text-[13px] whitespace-nowrap transition-colors md:w-full ${
          isSelected ? 'bg-accent text-white' : 'text-text hover:bg-black/5 dark:hover:bg-white/5'
        }`}
      >
        <TabIcon size={15} className={isSelected ? 'text-white' : 'text-accent'} />
        {tab.label}
      </button>
    )
  }

  return (
    <div className="overflow-hidden rounded-[14px] border border-sep bg-win text-text shadow-[0_30px_80px_-20px_rgba(0,0,0,0.35)] md:flex md:h-[700px]">
      {/* Sidebar */}
      <div className="flex flex-col border-b border-sep bg-sidebar md:w-[212px] md:shrink-0 md:border-r md:border-b-0">
        <div className="flex gap-2 px-4 pt-3.5 pb-2 md:pb-4" aria-hidden="true">
          <span className="size-3 rounded-full bg-[#ff5f57]" />
          <span className="size-3 rounded-full bg-[#febc2e]" />
          <span className="size-3 rounded-full bg-[#28c840]" />
        </div>
        <div
          role="tablist"
          aria-label="MoniMac window tabs"
          aria-orientation="vertical"
          onKeyDown={onKeyDown}
          className="flex gap-1 overflow-x-auto px-2 pb-2 md:flex-1 md:flex-col md:gap-0.5 md:overflow-visible md:px-2.5"
        >
          {groups.map((group) => (
            <div key={group} role="presentation" className="flex gap-1 md:mb-2 md:flex-col md:gap-0.5">
              <span role="presentation" className="hidden px-2.5 pt-1 pb-1 text-[11px] font-medium text-text-3 md:block">
                {group}
              </span>
              {windowTabs.filter((t) => t.group === group).map(tabButton)}
            </div>
          ))}
          <div role="presentation" className="flex md:mt-auto md:mb-1 md:flex-col">
            {windowTabs.filter((t) => t.group === 'Settings').map(tabButton)}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="flex items-center gap-3 border-b border-sep px-5 py-3">
          <div className="min-w-0">
            <div className="text-[15px] font-semibold">{current.label}</div>
            <div className="truncate text-[11.5px] text-text-2">{current.subtitle}</div>
          </div>
          <div className="ml-auto flex shrink-0 items-center gap-1 text-text-2" aria-hidden="true">
            <span className="rounded-md bg-track/70 p-1.5"><GridIcon size={14} /></span>
            <span className="p-1.5"><ListIcon size={14} /></span>
            <span className="p-1.5"><ShareIcon size={14} /></span>
          </div>
        </div>
        <div
          id="window-panel"
          role="tabpanel"
          aria-labelledby={`tab-${current.id}`}
          tabIndex={0}
          className="relative flex-1 overflow-y-auto p-4 sm:p-5"
        >
          <AnimatePresence mode="wait" initial={false}>
            <m.div
              key={current.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18, ease: 'easeOut' }}
            >
              {current.render(tick)}
            </m.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  )
}
