import type { ComponentType, SVGProps } from 'react'
import { BatteryIcon, CpuIcon, DiskIcon, GpuIcon, MemoryIcon, NetworkIcon, ThermometerIcon } from '../components/icons'
import type { Metric } from '../data/sample'

export const metricIcon: Record<Metric, ComponentType<SVGProps<SVGSVGElement> & { size?: number }>> = {
  cpu: CpuIcon,
  memory: MemoryIcon,
  gpu: GpuIcon,
  network: NetworkIcon,
  disk: DiskIcon,
  battery: BatteryIcon,
  temp: ThermometerIcon,
}
