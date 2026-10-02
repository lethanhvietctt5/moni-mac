import { useInView, useReducedMotion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'

/**
 * Sample readings for the menu bar mockups, moving like MoniMac's 2-second refresh.
 * Each series wanders around the design's value, so the numbers stay believable.
 */
export interface Readings {
  cpu: number // percent
  memory: number // GB
  network: number // MB/s
  gpu: number // percent
  cpuBars: number[] // 0...1, oldest first
  memoryBars: number[]
  networkBars: number[]
  gpuBars: number[]
}

const BARS = 10

// The design's bars (px of 14), so the first frame matches it exactly.
const initial: Readings = {
  cpu: 32,
  memory: 11.2,
  network: 2.4,
  gpu: 18,
  cpuBars: [4, 6, 5, 8, 7, 10, 9, 12, 8, 11].map((h) => h / 14),
  memoryBars: [9, 9, 10, 10, 11, 10, 11, 11, 12, 11].map((h) => h / 14),
  networkBars: [3, 7, 2, 9, 4, 11, 5, 3, 8, 6].map((h) => h / 14),
  gpuBars: [2, 3, 5, 4, 6, 8, 7, 5, 6, 4].map((h) => h / 14),
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v))
const push = (bars: number[], v: number) => [...bars.slice(1 - BARS), v]

function next(r: Readings): Readings {
  const cpu = clamp(r.cpu + (Math.random() - 0.5) * 14 + (32 - r.cpu) * 0.25, 12, 64)
  const memory = clamp(r.memory + (Math.random() - 0.5) * 0.12 + (11.2 - r.memory) * 0.2, 10.8, 11.8)
  const network = clamp(r.network * (0.55 + Math.random() * 0.9) + (2.4 - r.network) * 0.2, 0.2, 6.5)
  const gpu = clamp(r.gpu + (Math.random() - 0.5) * 10 + (18 - r.gpu) * 0.3, 4, 42)
  return {
    cpu,
    memory,
    network,
    gpu,
    cpuBars: push(r.cpuBars, cpu / 64),
    memoryBars: push(r.memoryBars, (memory - 6) / 6.5),
    networkBars: push(r.networkBars, network / 6.5),
    gpuBars: push(r.gpuBars, gpu / 42),
  }
}

/** Live readings while `ref`'s element is on screen; the design's still values with reduced motion. */
export function useReadings<T extends Element>() {
  const ref = useRef<T>(null)
  const inView = useInView(ref)
  const reduce = useReducedMotion()
  const [readings, setReadings] = useState(initial)
  useEffect(() => {
    if (!inView || reduce) return
    const id = window.setInterval(() => setReadings(next), 2000)
    return () => window.clearInterval(id)
  }, [inView, reduce])
  return [ref, readings] as const
}

export const formatPercent = (v: number) => `${Math.round(v)}%`
export const formatGB = (v: number) => `${v.toFixed(1)} GB`
export const formatRate = (v: number) => (v < 1 ? `${Math.round(v * 1000)} KB/s` : `${v.toFixed(1)} MB/s`)
