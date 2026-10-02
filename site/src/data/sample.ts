/**
 * Sample data for every mockup on the page, in one place so the numbers agree.
 *
 * It follows the Pencil designs, with their known inconsistencies settled once:
 * one Mac (M3 Pro, 18 GB), one battery level, CPU % in "System" mode on every
 * surface (the app applies one CPU mode everywhere), and a weekly card whose
 * uptime fits in a week.
 */

export const links = {
  repo: 'https://github.com/lethanhvietctt5/moni-mac',
  releases: 'https://github.com/lethanhvietctt5/moni-mac/releases',
  issues: 'https://github.com/lethanhvietctt5/moni-mac/issues',
  dmg: 'https://github.com/lethanhvietctt5/moni-mac/releases/latest/download/MoniMac.dmg',
} as const

export const release = {
  version: '0.1.0',
  minimumMacOS: '14.2',
} as const

export const installOneLiner =
  'curl -fsSL -o /tmp/MoniMac.dmg https://github.com/lethanhvietctt5/moni-mac/releases/latest/download/MoniMac.dmg && hdiutil attach -quiet -nobrowse -mountpoint /tmp/MoniMac /tmp/MoniMac.dmg && cp -R /tmp/MoniMac/MoniMac.app /Applications/ && hdiutil detach -quiet /tmp/MoniMac && open /Applications/MoniMac.app'

export const unquarantine = 'xattr -dr com.apple.quarantine /Applications/MoniMac.app'

export type Metric = 'cpu' | 'memory' | 'gpu' | 'network' | 'disk' | 'battery' | 'temp'

/** CSS color for each metric, from the app's palette tokens. */
export const metricColor: Record<Metric, string> = {
  cpu: 'var(--cpu)',
  memory: 'var(--memory)',
  gpu: 'var(--gpu)',
  network: 'var(--network)',
  disk: 'var(--disk)',
  battery: 'var(--battery)',
  temp: 'var(--temp)',
}

export const mac = {
  model: 'MacBook Pro',
  chip: 'M3 Pro',
  memoryGB: 18,
  cores: { performance: 6, efficiency: 6 },
  gpuCores: 18,
  subtitle: 'MacBook Pro · M3 Pro · 18 GB',
} as const

export const clock = 'Wed 1 Oct  9:41'

/** Live values the hook wobbles around. */
export const live = {
  cpu: { total: 32, user: 21, system: 11 },
  memory: { usedGB: 11.4 },
  gpu: { percent: 18 },
  network: { downMBps: 4.2, upKBps: 380 },
  disk: { readMBps: 48, writeMBps: 12 },
  temp: { cpuC: 58, fanRPM: 2140 },
  perCore: [72, 64, 51, 38, 22, 14, 46, 41, 33, 29, 18, 12],
} as const

export const battery = {
  percent: 86,
  state: 'Charging',
  fullIn: '1 h 12 min',
  adapter: '96 W',
  drawW: 14.2,
  systemW: 21.6,
  health: 92,
  designMah: '5,030',
  currentMah: '4,627',
  cycles: 214,
  ratedCycles: '1,000',
  tempC: 31.4,
} as const

export const disk = {
  volume: 'Macintosh HD · APFS · 1 TB SSD',
  freeGB: 312,
  totalGB: 994,
  writtenTodayGB: 38.4,
  ssdHealth: 98,
  lifetimeTB: 41,
  breakdown: [
    { label: 'Applications', size: '182 GB', hint: '214 apps', gb: 182, opacity: 1 },
    { label: 'Developer', size: '148 GB', hint: 'Xcode, simulators', gb: 148, opacity: 0.7 },
    { label: 'Documents', size: '214 GB', hint: 'Photos, projects', gb: 214, opacity: 0.42 },
    { label: 'macOS', size: '46 GB', hint: 'System volume', gb: 46, opacity: -1 },
    { label: 'Purgeable', size: '92 GB', hint: 'Caches, snapshots', gb: 92, opacity: -2 },
    { label: 'Free', size: '312 GB', hint: 'Available now', gb: 312, opacity: 0 },
  ],
} as const

export const memory = {
  type: '18 GB unified memory',
  pressure: 'Normal',
  pressurePercent: 24,
  swapUsed: '512 MB',
  swapFile: '2 GB',
  compression: '2.6×',
  compressionDetail: '5.9 GB → 2.3 GB',
  segments: [
    { label: 'App Memory', size: '6.8 GB', hint: 'Used by 61 apps', gb: 6.8, opacity: 1 },
    { label: 'Wired', size: '2.3 GB', hint: "Kernel, can't page out", gb: 2.3, opacity: 0.7 },
    { label: 'Compressed', size: '2.3 GB', hint: 'Saved 3.6 GB', gb: 2.3, opacity: 0.45 },
    { label: 'Cached Files', size: '4.9 GB', hint: 'Reclaimable', gb: 4.9, opacity: 0.22 },
    { label: 'Free', size: '1.7 GB', hint: 'Available now', gb: 1.7, opacity: 0 },
  ],
} as const

export const network = {
  link: 'Wi-Fi 6E · Studio-5G · 1.2 Gb/s link',
  downloaded: '3.8 GB',
  uploaded: '612 MB',
  since: '08:42',
  week: { down: '85.5 GB', up: '9.8 GB', days: ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Today'], downGB: [11.2, 14.8, 6.1, 4.9, 18.4, 21.6, 8.5], upGB: [1.1, 1.9, 0.6, 0.4, 2.2, 2.6, 1.0] },
} as const

export const gpu = {
  name: 'Apple M3 Pro · 18-core GPU',
  memory: '2.1 GB',
  tiler: 6,
  avg24h: 14,
  peak24h: 91,
  peakWhen: 'Final Cut Pro export · 14:12',
} as const

export const cpu = {
  name: 'Apple M3 Pro · 12 cores (6P + 6E)',
  load: { one: 3.42, five: 2.91, fifteen: 2.66 },
  threads: '4,212',
  processes: '1,048',
  peak: 'Peak 87% at 14:12',
} as const

/** 24 hourly buckets, oldest first (user %, system %). */
export const cpuHistory: Array<[number, number]> = [
  [17, 6], [19, 6], [16, 5], [22, 7], [27, 8], [24, 7], [18, 6], [15, 5], [14, 4], [15, 4], [19, 6], [27, 9],
  [36, 12], [33, 11], [28, 9], [27, 8], [34, 11], [50, 17], [64, 23], [61, 22], [44, 14], [35, 12], [30, 10], [32, 11],
]
export const historyAxis = ['15:00', '21:00', '03:00', '09:00', 'Now'] as const

/** Memory pressure history (0–100), used with Low/Med/High bands. */
export const pressureHistory = [
  18, 20, 19, 22, 24, 26, 25, 22, 20, 18, 17, 19, 23, 30, 41, 58, 64, 52, 38, 30, 27, 25, 24, 24,
]
export const gpuHistory = [8, 10, 9, 12, 14, 11, 9, 7, 6, 6, 8, 12, 18, 24, 22, 38, 72, 91, 54, 22, 16, 14, 16, 18]
export const diskHistory: Array<[number, number]> = [
  [12, 6], [20, 9], [14, 8], [9, 4], [42, 30], [18, 9], [8, 4], [6, 3], [5, 2], [7, 3], [11, 6], [16, 8],
  [24, 14], [95, 40], [30, 18], [22, 12], [18, 10], [26, 22], [34, 28], [20, 12], [15, 8], [12, 6], [16, 9], [14, 7],
]
/** Battery charge %, and whether the adapter was connected, per bucket. */
export const batteryHistory: Array<[number, boolean]> = [
  [62, false], [55, false], [48, false], [41, false], [58, true], [74, true], [88, true], [96, true], [100, true],
  [100, true], [93, false], [85, false], [77, false], [70, false], [63, false], [56, false], [49, false], [44, false],
  [52, true], [63, true], [71, true], [78, true], [83, true], [86, true],
]
export const batteryAxis = ['10:00', '16:00', '22:00', '04:00', 'Now'] as const
/** CPU temperature °C, hourly. */
export const tempHistory = [
  52, 51, 50, 54, 63, 70, 77, 81, 72, 64, 60, 58, 55, 52, 49, 47, 46, 46, 45, 47, 50, 54, 57, 58,
]

export type AppKind = 'app' | 'agent' | 'system'

export interface SampleApp {
  name: string
  /** Initials for the generic rounded glyph (no real app icons). */
  glyph: string
  /** Glyph background. */
  tint: string
  processes: number
  cpu: number
  memory: string
  memoryMB: number
  gpu?: number
  network?: string
  disk?: string
  power?: number
}

const tints = {
  blue: '#0a84ff',
  green: '#34a853',
  graphite: '#48484a',
  teal: '#30b0c7',
  orange: '#ff9f0a',
  indigo: '#5e5ce6',
  purple: '#8e44ad',
  pink: '#ff375f',
  gray: '#8e8e93',
  red: '#e5484d',
}

export const apps: Record<string, SampleApp> = {
  xcode: { name: 'Xcode', glyph: 'X', tint: tints.blue, processes: 7, cpu: 12.4, memory: '980 MB', memoryMB: 980, gpu: 0.2, network: '12 KB/s', disk: '1.8 MB/s', power: 3.4 },
  chrome: { name: 'Google Chrome', glyph: 'G', tint: tints.green, processes: 23, cpu: 5.1, memory: '1.9 GB', memoryMB: 1900, gpu: 0.3, network: '64 KB/s', disk: '0.4 MB/s', power: 4.8 },
  slack: { name: 'Slack', glyph: 'S', tint: tints.purple, processes: 6, cpu: 3.2, memory: '480 MB', memoryMB: 480, gpu: 0.1, network: '220 KB/s', power: 1.3 },
  windowServer: { name: 'WindowServer', glyph: 'W', tint: tints.gray, processes: 1, cpu: 2.6, memory: '420 MB', memoryMB: 420, gpu: 3.1 },
  timeMachine: { name: 'Time Machine', glyph: 'T', tint: tints.indigo, processes: 4, cpu: 2.1, memory: '160 MB', memoryMB: 160, disk: '9.4 MB/s' },
  safari: { name: 'Safari', glyph: 'S', tint: tints.blue, processes: 9, cpu: 1.9, memory: '360 MB', memoryMB: 360, gpu: 1.2, network: '3.2 MB/s' },
  docker: { name: 'Docker', glyph: 'D', tint: tints.blue, processes: 11, cpu: 1.6, memory: '1.2 GB', memoryMB: 1200, network: '20 KB/s', power: 0.7 },
  finalCut: { name: 'Final Cut Pro', glyph: 'F', tint: tints.graphite, processes: 3, cpu: 1.4, memory: '540 MB', memoryMB: 540, gpu: 12.4, power: 2.6 },
  spotify: { name: 'Spotify', glyph: 'S', tint: tints.green, processes: 4, cpu: 1.1, memory: '240 MB', memoryMB: 240, gpu: 0.1, network: '540 KB/s', power: 0.8 },
  figma: { name: 'Figma', glyph: 'F', tint: tints.graphite, processes: 5, cpu: 0.9, memory: '410 MB', memoryMB: 410, gpu: 0.8 },
  photos: { name: 'Photos', glyph: 'P', tint: tints.orange, processes: 3, cpu: 0.7, memory: '620 MB', memoryMB: 620, gpu: 0.4 },
  mail: { name: 'Mail', glyph: 'M', tint: tints.blue, processes: 2, cpu: 0.4, memory: '210 MB', memoryMB: 210, network: '140 KB/s', power: 0.3 },
  messages: { name: 'Messages', glyph: 'M', tint: tints.green, processes: 2, cpu: 0.3, memory: '180 MB', memoryMB: 180, network: '60 KB/s' },
  music: { name: 'Music', glyph: 'M', tint: tints.pink, processes: 3, cpu: 0.4, memory: '190 MB', memoryMB: 190 },
  zoom: { name: 'Zoom', glyph: 'Z', tint: tints.blue, processes: 4, cpu: 2.0, memory: '310 MB', memoryMB: 310 },
}

/** Overview › Busiest Right Now: each app's dominant resource. */
export const busiest: Array<{ app: SampleApp; label: string; metric: Metric; fraction: number }> = [
  { app: apps.xcode, label: '12% CPU', metric: 'cpu', fraction: 0.58 },
  { app: apps.docker, label: '1.2 GB', metric: 'memory', fraction: 0.28 },
  { app: apps.chrome, label: '1.9 GB', metric: 'memory', fraction: 0.42 },
  { app: apps.timeMachine, label: '9.4 MB/s', metric: 'disk', fraction: 0.68 },
  { app: apps.finalCut, label: '12% GPU', metric: 'gpu', fraction: 0.48 },
  { app: apps.slack, label: '3% CPU', metric: 'cpu', fraction: 0.14 },
  { app: apps.safari, label: '3.2 MB/s', metric: 'network', fraction: 0.52 },
  { app: apps.spotify, label: '540 KB/s', metric: 'network', fraction: 0.12 },
  { app: apps.photos, label: '620 MB', metric: 'memory', fraction: 0.15 },
  { app: apps.windowServer, label: '3% CPU', metric: 'cpu', fraction: 0.13 },
]

/** Popover › Busiest Right Now (CPU, System mode). */
export const popoverBusiest = [apps.xcode, apps.chrome, apps.slack, apps.figma, apps.music]

export const topCPU = [apps.xcode, apps.chrome, apps.slack, apps.windowServer, apps.spotify]
export const topMemory = [apps.chrome, apps.docker, apps.xcode, apps.photos, apps.slack]
export const topGPU = [apps.finalCut, apps.windowServer, apps.safari, apps.figma, apps.photos]
export const topNetwork = [apps.safari, apps.spotify, apps.slack, apps.mail, apps.messages]
export const diskWritesToday = [
  { app: apps.timeMachine, amount: '14.2 GB', gb: 14.2 },
  { app: apps.xcode, amount: '9.8 GB', gb: 9.8 },
  { app: apps.docker, amount: '6.1 GB', gb: 6.1 },
  { app: apps.photos, amount: '3.4 GB', gb: 3.4 },
  { app: apps.chrome, amount: '2.2 GB', gb: 2.2 },
]
export const energy = [apps.chrome, apps.xcode, apps.finalCut, apps.slack, apps.spotify]

export const processTotals = {
  apps: 61,
  processes: '1,048',
  threads: '4,212',
  split: { app: 38, agent: 17, system: 6 },
} as const

/** The raw, ungrouped list on the "Grouped by app" section (a slice of 1,048). */
export const rawProcesses: Array<{ pid: number; name: string; cpu: string; group: string }> = [
  { pid: 812, name: 'Google Chrome Helper (Renderer)', cpu: '0.9', group: 'chrome' },
  { pid: 64, name: 'kernel_task', cpu: '1.2', group: 'system' },
  { pid: 2231, name: 'Xcode', cpu: '6.8', group: 'xcode' },
  { pid: 815, name: 'Google Chrome Helper (Renderer)', cpu: '0.4', group: 'chrome' },
  { pid: 397, name: 'WindowServer', cpu: '2.6', group: 'system' },
  { pid: 2240, name: 'SourceKitService', cpu: '3.1', group: 'xcode' },
  { pid: 819, name: 'Google Chrome Helper (GPU)', cpu: '1.1', group: 'chrome' },
  { pid: 1502, name: 'Slack Helper (Renderer)', cpu: '1.8', group: 'slack' },
  { pid: 501, name: 'mds_stores', cpu: '0.6', group: 'system' },
  { pid: 823, name: 'Google Chrome Helper (Renderer)', cpu: '0.7', group: 'chrome' },
  { pid: 2251, name: 'XCBBuildService', cpu: '1.4', group: 'xcode' },
  { pid: 1498, name: 'Slack', cpu: '0.9', group: 'slack' },
  { pid: 811, name: 'Google Chrome', cpu: '0.8', group: 'chrome' },
  { pid: 3302, name: 'com.docker.backend', cpu: '0.9', group: 'docker' },
  { pid: 827, name: 'Google Chrome Helper (Renderer)', cpu: '0.3', group: 'chrome' },
  { pid: 1505, name: 'Slack Helper (GPU)', cpu: '0.5', group: 'slack' },
  { pid: 3310, name: 'com.docker.virtualization', cpu: '0.7', group: 'docker' },
  { pid: 830, name: 'Google Chrome Helper (Renderer)', cpu: '0.2', group: 'chrome' },
]

/** The grouped view: each app with the helpers it rolls up. */
export const groupedApps: Array<{ app: SampleApp; kind: AppKind; cpu: string; helpers: Array<{ name: string; count: number; cpu: string }> }> = [
  {
    app: apps.xcode, kind: 'app', cpu: '12.4%',
    helpers: [
      { name: 'Xcode', count: 1, cpu: '6.8%' },
      { name: 'SourceKitService', count: 1, cpu: '3.1%' },
      { name: 'XCBBuildService', count: 1, cpu: '1.4%' },
      { name: 'Xcode + 4 helpers', count: 4, cpu: '1.1%' },
    ],
  },
  {
    app: apps.chrome, kind: 'app', cpu: '5.1%',
    helpers: [
      { name: 'Google Chrome Helper (Renderer) ×14', count: 14, cpu: '3.2%' },
      { name: 'Google Chrome Helper (GPU)', count: 1, cpu: '1.1%' },
      { name: 'Google Chrome + 7 helpers', count: 8, cpu: '0.8%' },
    ],
  },
  {
    app: apps.slack, kind: 'app', cpu: '3.2%',
    helpers: [
      { name: 'Slack Helper (Renderer) ×3', count: 3, cpu: '1.8%' },
      { name: 'Slack + 2 helpers', count: 3, cpu: '1.4%' },
    ],
  },
  {
    app: apps.docker, kind: 'agent', cpu: '1.6%',
    helpers: [
      { name: 'com.docker.backend', count: 1, cpu: '0.9%' },
      { name: 'com.docker.virtualization + 9', count: 10, cpu: '0.7%' },
    ],
  },
  {
    app: apps.windowServer, kind: 'system', cpu: '2.6%',
    helpers: [{ name: 'WindowServer', count: 1, cpu: '2.6%' }],
  },
]

export const bluetooth = {
  airpods: {
    name: "Maya's AirPods Pro",
    status: 'Connected · Playing audio from Spotify',
    detail: 'Noise Cancellation on · Approx. 4 h 20 min listening left',
    left: 82,
    right: 78,
    case: 41,
  },
  devices: [
    { name: 'Magic Keyboard', kind: 'Keyboard', connected: true, hint: 'Charged 6 days ago', percent: 64, icon: 'keyboard' as const },
    { name: 'Magic Trackpad', kind: 'Trackpad', connected: true, hint: 'Low — charge soon', percent: 14, icon: 'trackpad' as const },
    { name: 'MX Master 3S', kind: 'Mouse', connected: true, hint: 'Est. 58 days left', percent: 91, icon: 'mouse' as const },
    { name: 'Wireless Controller', kind: 'Game Controller', connected: false, hint: 'Last seen yesterday, 22:42', percent: 37, icon: 'gamepad' as const },
  ],
} as const

export const sound = {
  summary: '3 apps playing · 2 silent · 1 muted',
  output: 'MacBook Pro Speakers',
  sampleRate: '48 kHz',
  systemVolume: 68,
  apps: [
    { app: apps.spotify, state: 'Playing', volume: 82 },
    { app: apps.chrome, state: 'Playing', volume: 54 },
    { app: apps.zoom, state: 'Playing', volume: 100 },
    { app: apps.music, state: 'Silent', volume: 70 },
    { app: apps.slack, state: 'Muted', volume: 0 },
    { app: apps.safari, state: 'Silent', volume: 100 },
  ],
} as const

export const thermal = {
  state: 'Nominal',
  cards: [
    { label: 'CPU', value: 58, note: 'Peak 81° today' },
    { label: 'GPU', value: 54, note: 'Peak 73° today' },
    { label: 'SSD', value: 41, note: 'Normal' },
    { label: 'Battery', value: 31, note: 'Normal' },
  ],
  fans: [
    { name: 'Left Fan', rpm: 2140, min: 1200, max: 6550 },
    { name: 'Right Fan', rpm: 2180, min: 1200, max: 6550 },
  ],
  sensors: [
    ['CPU Performance Cores', '62 °C'],
    ['CPU Efficiency Cores', '52 °C'],
    ['GPU Cluster', '54 °C'],
    ['Memory', '47 °C'],
    ['Airflow Left', '38 °C'],
    ['Palm Rest', '29 °C'],
    ['Power Supply', '44 °C'],
    ['Wireless Module', '40 °C'],
    ['Ambient', '24 °C'],
  ],
  summary: 'Avg 52 °C · Peak 81 °C at 14:14 during Xcode build',
} as const

export type ServerActivity = 'active' | 'recent' | 'idle'

export interface DevServer {
  command: string
  type: string
  port?: number
  uptime: string
  memory: string
  activity: string
  state: ServerActivity
  docker?: boolean
}

export interface Project {
  name: string
  path: string
  branch: string
  memory: string
  servers: DevServer[]
  stale?: boolean
}

export const projects: { summary: string; banner: { title: string; body: string }; list: Project[] } = {
  summary: '8 dev servers across 3 projects · 2.9 GB',
  banner: {
    title: '2 servers have been idle for days',
    body: 'old-landing has had no requests since Sep 27 and is holding 1.1 GB of memory and ports 5173, 4000.',
  },
  list: [
    {
      name: 'acme-web', path: '~/Developer/acme-web', branch: 'main', memory: '1.3 GB',
      servers: [
        { command: 'next dev', type: 'Next.js', port: 3000, uptime: '3 h 12 m', memory: '742 MB', activity: 'Active · now', state: 'active' },
        { command: 'storybook dev', type: 'Storybook', port: 6006, uptime: '3 h 10 m', memory: '418 MB', activity: 'Idle 26 min', state: 'recent' },
        { command: 'tailwindcss --watch', type: 'Watcher', uptime: '3 h 12 m', memory: '96 MB', activity: 'Active · now', state: 'active' },
      ],
    },
    {
      name: 'api-gateway', path: '~/Developer/api-gateway', branch: 'feat/auth', memory: '540 MB',
      servers: [
        { command: 'uvicorn app:main --reload', type: 'FastAPI', port: 8000, uptime: '1 d 4 h', memory: '188 MB', activity: 'Active · 2 min', state: 'active' },
        { command: 'postgres:16', type: 'Docker', port: 5432, uptime: '6 d 2 h', memory: '264 MB', activity: 'Active · 2 min', state: 'active', docker: true },
        { command: 'redis:7-alpine', type: 'Docker', port: 6379, uptime: '6 d 2 h', memory: '88 MB', activity: 'Idle 3 h', state: 'recent', docker: true },
      ],
    },
    {
      name: 'old-landing', path: '~/Developer/old-landing', branch: 'main', memory: '1.1 GB', stale: true,
      servers: [
        { command: 'vite', type: 'Vite', port: 5173, uptime: '4 d 9 h', memory: '862 MB', activity: 'Idle 4 days', state: 'idle' },
        { command: 'json-server db.json', type: 'Mock API', port: 4000, uptime: '9 d 1 h', memory: '214 MB', activity: 'Idle 9 days', state: 'idle' },
      ],
    },
  ],
}

export const notifications = [
  {
    title: 'Xcode is using a lot of CPU',
    body: '34.2% for the last 2 minutes. Your Mac may feel slower and run warmer.',
    chip: '34.2%',
    metric: 'cpu' as Metric,
    app: apps.xcode,
    actions: ['Quit Xcode', 'Show'],
  },
  {
    title: 'Google Chrome memory is growing fast',
    body: '+2.1 GB within 10 minutes, now 6.8 GB. A steady climb can mean a memory leak.',
    chip: '+2.1 GB',
    metric: 'memory' as Metric,
    app: apps.chrome,
  },
  {
    title: 'Heavy disk writes from Photos',
    body: '12.4 GB written in the last hour. Heavy writing wears out an SSD over time.',
    chip: '24 MB/s',
    metric: 'disk' as Metric,
    app: apps.photos,
  },
]

export const weekly = {
  range: 'LAST 7 DAYS · 24 SEP – 1 OCT 2026',
  headline: 'Busy week, cool head.',
  summary: '142 hours of uptime, zero thermal throttling, and Xcode doing most of the heavy lifting.',
  busiest: 'Busiest app: Xcode',
  stats: [
    { label: 'CPU', metric: 'cpu' as Metric, value: '32%', caption: 'avg · peak 94%', spark: [34, 42, 30, 52, 60, 44, 38, 58, 70, 48, 40, 64, 72, 50, 46, 62] },
    { label: 'Memory', metric: 'memory' as Metric, value: '11.4 GB', caption: 'of 18 GB · pressure low', spark: [60, 62, 61, 63, 64, 66, 65, 67, 68, 66, 67, 69, 70, 69, 70, 71] },
    { label: 'GPU', metric: 'gpu' as Metric, value: '18%', caption: 'avg · peak 71%', spark: [10, 12, 14, 22, 30, 16, 12, 10, 22, 34, 46, 26, 16, 12, 10, 14] },
    { label: 'Network', metric: 'network' as Metric, value: '48 GB', caption: 'down · 6.2 GB up', spark: [20, 26, 18, 44, 30, 36, 56, 24, 22, 38, 30, 50, 26, 40, 24, 32] },
    { label: 'Battery', metric: 'battery' as Metric, value: '92%', caption: 'health · 214 cycles', spark: [80, 76, 70, 62, 58, 74, 68, 60, 82, 76, 70, 60, 80, 74, 66, 70] },
  ],
}

/** The weekly card's fixed palettes (App/Sources/ShareCardView.swift). */
export const cardPalettes = {
  light: {
    background: '#ffffff', textPrimary: '#1d1d1f', textSecondary: '#6e6e73', textTertiary: '#aeaeb2',
    tile: '#f7f7f9', stroke: '#e5e5ea', accent: '#0a84ff',
    metrics: { cpu: '#0a84ff', memory: '#af52de', gpu: '#ff9f0a', network: '#30b0c7', battery: '#34c759', disk: '#5e5ce6', temp: '#ff453a' } as Record<Metric, string>,
  },
  dark: {
    background: '#1e1e20', textPrimary: '#f5f5f7', textSecondary: '#a1a1a6', textTertiary: '#6c6c70',
    tile: '#2c2c2e', stroke: '#3a3a3c', accent: '#0a84ff',
    metrics: { cpu: '#409cff', memory: '#bf5af2', gpu: '#ffb340', network: '#40c8e0', battery: '#30d158', disk: '#7d7aff', temp: '#ff6961' } as Record<Metric, string>,
  },
} as const
