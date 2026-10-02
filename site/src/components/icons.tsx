import type { ReactNode, SVGProps } from 'react'

type IconProps = SVGProps<SVGSVGElement> & { size?: number }

/** Line icons in the spirit of SF Symbols, drawn on a 24 × 24 grid. */
function Icon({ size = 16, children, ...rest }: IconProps & { children: ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {children}
    </svg>
  )
}

export const CpuIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="6" y="6" width="12" height="12" rx="2" />
    <rect x="9.5" y="9.5" width="5" height="5" rx="1" />
    <path d="M9 2.5V6M15 2.5V6M9 18v3.5M15 18v3.5M2.5 9H6M2.5 15H6M18 9h3.5M18 15h3.5" />
  </Icon>
)
export const MemoryIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="2.5" y="7" width="19" height="9" rx="1.5" />
    <path d="M6 10.5v2M9.5 10.5v2M13 10.5v2M16.5 10.5v2M5 16v2.5M9 16v2.5M15 16v2.5M19 16v2.5" />
  </Icon>
)
export const GpuIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="5" y="3" width="14" height="18" rx="2.5" />
    <path d="M9 7.5h6M9 12h6M9 16.5h6" />
  </Icon>
)
export const NetworkIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 20V4M4 8l4-4 4 4M16 4v16M12 16l4 4 4-4" />
  </Icon>
)
export const DiskIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 14l2.6-7.2A2 2 0 0 1 7.5 5.5h9a2 2 0 0 1 1.9 1.3L21 14" />
    <rect x="3" y="14" width="18" height="5.5" rx="1.8" />
    <path d="M7 16.8h.01M10 16.8h.01" />
  </Icon>
)
export const BatteryIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="2.5" y="7" width="17" height="10" rx="2.5" />
    <path d="M22 10.5v3" />
    <path d="M6 10v4M9 10v4M12 10v4" />
  </Icon>
)
export const ThermometerIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M10 13.5V5a2 2 0 1 1 4 0v8.5a4 4 0 1 1-4 0Z" />
    <path d="M12 9v7" />
  </Icon>
)
export const LayersIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3l9 4.5-9 4.5-9-4.5L12 3Z" />
    <path d="M3 12l9 4.5 9-4.5M3 16.5L12 21l9-4.5" />
  </Icon>
)
export const BluetoothIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 7l10 10-5 4.5V2.5L17 7 7 17" />
  </Icon>
)
export const SpeakerIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4v-5Z" />
    <path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" />
  </Icon>
)
export const SpeakerMuteIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4v-5Z" />
    <path d="M16 9.5l5 5M21 9.5l-5 5" />
  </Icon>
)
export const FolderIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7.5Z" />
  </Icon>
)
export const FolderCodeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7.5Z" />
    <path d="M10 11l-2 2 2 2M14 11l2 2-2 2" />
  </Icon>
)
export const GearIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z" />
  </Icon>
)
export const GridIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="4" y="4" width="6.5" height="6.5" rx="1.5" />
    <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5" />
    <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5" />
    <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5" />
  </Icon>
)
export const ListIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01" />
  </Icon>
)
export const ShareIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3v12M8 7l4-4 4 4" />
    <path d="M8 11H6.5A1.5 1.5 0 0 0 5 12.5v6A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5v-6a1.5 1.5 0 0 0-1.5-1.5H16" />
  </Icon>
)
export const DownloadIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14" />
  </Icon>
)
export const CopyIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2" />
    <path d="M15.5 8.5V6A2 2 0 0 0 13.5 4H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5" />
  </Icon>
)
export const CheckIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M5 12.5l4.5 4.5L19 7.5" />
  </Icon>
)
export const WarningIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M10.3 4.2L2.8 17.5A2 2 0 0 0 4.5 20.5h15a2 2 0 0 0 1.7-3L13.7 4.2a2 2 0 0 0-3.4 0Z" />
    <path d="M12 9.5v4M12 17h.01" />
  </Icon>
)
export const BranchIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="6.5" cy="5.5" r="2" />
    <circle cx="6.5" cy="18.5" r="2" />
    <circle cx="17.5" cy="7.5" r="2" />
    <path d="M6.5 7.5v9M17.5 9.5c0 4-5 3.5-9.6 7.4" />
  </Icon>
)
export const StopIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="7" y="7" width="10" height="10" rx="1.5" />
  </Icon>
)
export const ArrowUpRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 17L17 7M9 7h8v8" />
  </Icon>
)
export const BellIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16Z" />
    <path d="M10 20.5a2 2 0 0 0 4 0" />
  </Icon>
)
export const LockIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="5" y="10.5" width="14" height="10" rx="2" />
    <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
  </Icon>
)
export const ShieldIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.3-7.5 9.5-4.3-1.2-7.5-4.9-7.5-9.5V6L12 3Z" />
    <path d="M9 12l2.2 2.2L15.5 10" />
  </Icon>
)
export const HandIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 12V5.5a1.5 1.5 0 0 1 3 0V11M11 10.5V4a1.5 1.5 0 0 1 3 0v6.5M14 10.5V5.5a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-.5a6 6 0 0 1-4.6-2.2L2.8 16a1.6 1.6 0 0 1 2.4-2.1L8 16" />
  </Icon>
)
export const WifiIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01" />
  </Icon>
)
export const SlidersIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 7h9M17 7h3M4 17h3M11 17h9" />
    <circle cx="15" cy="7" r="2" />
    <circle cx="9" cy="17" r="2" />
  </Icon>
)
export const HeadphonesIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 15v-3a8 8 0 0 1 16 0v3" />
    <rect x="3.5" y="14" width="4" height="6.5" rx="1.6" />
    <rect x="16.5" y="14" width="4" height="6.5" rx="1.6" />
  </Icon>
)
export const KeyboardIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="2.5" y="6" width="19" height="12" rx="2" />
    <path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M8 14.5h8" />
  </Icon>
)
export const TrackpadIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 4.5l11 6.5-5 1.3L9.8 17 6 4.5Z" />
  </Icon>
)
export const MouseIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="6.5" y="3" width="11" height="18" rx="5.5" />
    <path d="M12 7v3" />
  </Icon>
)
export const GamepadIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 7.5h10a4.5 4.5 0 0 1 4.4 5.4l-.8 4a2.5 2.5 0 0 1-4.3 1.2L14.5 16h-5l-1.8 2.1a2.5 2.5 0 0 1-4.3-1.2l-.8-4A4.5 4.5 0 0 1 7 7.5Z" />
    <path d="M8 10.5v3M6.5 12h3M15.5 11h.01M17 13h.01" />
  </Icon>
)
export const FanIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="1.6" />
    <path d="M12 10.4C10 7 10.5 3.5 13 3.5c2.4 0 2.6 3.5-1 6.9ZM13.6 12c3.4-2 6.9-1.5 6.9 1 0 2.4-3.5 2.6-6.9-1ZM12 13.6c2 3.4 1.5 6.9-1 6.9-2.4 0-2.6-3.5 1-6.9ZM10.4 12C7 14 3.5 13.5 3.5 11c0-2.4 3.5-2.6 6.9 1Z" />
  </Icon>
)
export const HistoryIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 12a8.5 8.5 0 1 0 2.5-6L3.5 8.5" />
    <path d="M3.5 4v4.5H8M12 7.5V12l3 2" />
  </Icon>
)
export const XCircleIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M9 9l6 6M15 9l-6 6" />
  </Icon>
)
export const GaugeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4.2 17a8.5 8.5 0 1 1 15.6 0" />
    <path d="M12 13.5l4-5" />
    <circle cx="12" cy="13.5" r="1.2" />
  </Icon>
)
export const PowerIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5v8M7 6.5a7.5 7.5 0 1 0 10 0" />
  </Icon>
)
export const RefreshIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M20 11.5A8 8 0 0 0 6 6.6L4 8.5M4 4v4.5h4.5M4 12.5a8 8 0 0 0 14 4.9l2-1.9M20 20v-4.5h-4.5" />
  </Icon>
)
export const InfoIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 11v5M12 8h.01" />
  </Icon>
)
export const CommandIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9 9V6.5A2.5 2.5 0 1 0 6.5 9H9Zm0 0h6m-6 0v6m6-6V6.5A2.5 2.5 0 1 1 17.5 9H15Zm0 0v6m0 0h-6m6 0v2.5a2.5 2.5 0 1 0 2.5-2.5H15Zm-6 0v2.5A2.5 2.5 0 1 1 6.5 15H9Z" />
  </Icon>
)
export const ChevronDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 9.5l6 6 6-6" />
  </Icon>
)
export const ChevronRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9.5 6l6 6-6 6" />
  </Icon>
)
export const MenuIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Icon>
)
export const CloseIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 6l12 12M18 6L6 18" />
  </Icon>
)
export const LeafIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M5 19c0-8 5-13.5 15-14-0.5 10-6 15-14 15" />
    <path d="M5 19c3-4 6-6.5 9.5-8" />
  </Icon>
)
export const CodeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8.5 7.5L4 12l4.5 4.5M15.5 7.5L20 12l-4.5 4.5M13.5 5l-3 14" />
  </Icon>
)
export const TerminalIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
    <path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5" />
  </Icon>
)
export const LaptopIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="4.5" y="5" width="15" height="10.5" rx="1.5" />
    <path d="M2.5 19h19" />
  </Icon>
)
export const BoxIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3Z" />
    <path d="M4 7.5l8 4.5 8-4.5M12 12v9" />
  </Icon>
)
export const HexagonIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5l7.4 4.25v8.5L12 20.5l-7.4-4.25v-8.5L12 3.5Z" />
  </Icon>
)
export const SparkleIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9L12 3.5ZM18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2Z" />
  </Icon>
)
export const PlugIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9 3.5v4M15 3.5v4M6.5 7.5h11v3a5.5 5.5 0 0 1-11 0v-3ZM12 16v4.5" />
  </Icon>
)
export const BoltIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M13 2.5L5 13.5h6l-1 8 8-11h-6l1-8Z" />
  </Icon>
)
export const UnitsIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 8.5h15M15 4.5l4 4-4 4M20 15.5H5M9 11.5l-4 4 4 4" />
  </Icon>
)
export const WindowIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
    <path d="M3 9h18" />
  </Icon>
)

export function GitHubIcon({ size = 18, ...rest }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false" {...rest}>
      <path d="M12 2C6.48 2 2 6.58 2 12.23c0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.49l-.01-1.7c-2.78.62-3.37-1.37-3.37-1.37-.46-1.18-1.11-1.5-1.11-1.5-.91-.63.07-.62.07-.62 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.35 1.12 2.92.85.09-.66.35-1.12.64-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05a9.4 9.4 0 0 1 5 0c1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.94.68 1.9l-.01 2.81c0 .27.18.6.69.49A10.1 10.1 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z" />
    </svg>
  )
}
