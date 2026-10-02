import type { ComponentType, SVGProps } from 'react'
import { BatteryIcon, CpuIcon, DiskIcon, GpuIcon, MemoryIcon, NetworkIcon, ThermometerIcon } from '../components/icons'
import type { Metric } from '../data/sample'

/** An icon component from components/icons. */
export type IconComponent = ComponentType<SVGProps<SVGSVGElement> & { size?: number }>

export const metricIcon: Record<Metric, IconComponent> = {
  cpu: CpuIcon,
  memory: MemoryIcon,
  gpu: GpuIcon,
  network: NetworkIcon,
  disk: DiskIcon,
  battery: BatteryIcon,
  temp: ThermometerIcon,
}
