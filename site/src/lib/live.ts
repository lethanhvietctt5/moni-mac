/**
 * Deterministic, smooth pseudo-random values for the simulated live metrics.
 * Everything is a pure function of (seed, tick), so a mockup re-renders
 * consistent numbers without keeping its own random state.
 */

import { live, type LiveReading } from '../data/sample'

function hash(seed: number, n: number): number {
  let h = (seed * 374761393 + n * 668265263) | 0
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  h ^= h >>> 16
  return (h >>> 0) / 4294967296
}

/** Smooth noise in [0, 1): eased interpolation between hashed points. */
export function wave(seed: number, t: number): number {
  const i = Math.floor(t)
  const f = t - i
  const e = f * f * (3 - 2 * f)
  return hash(seed, i) * (1 - e) + hash(seed, i + 1) * e
}

/** A value that drifts around `base` by up to ±`spread` (a fraction of base). */
export function wobble(base: number, spread: number, seed: number, tick: number): number {
  return base * (1 + spread * (wave(seed, tick / 2) * 2 - 1))
}

/**
 * A sliding window of `length` samples ending at `tick`, each within
 * [lo, hi]. Every tick the window moves one sample to the left.
 */
export function series(seed: number, length: number, tick: number, lo: number, hi: number): number[] {
  return Array.from({ length }, (_, i) => lo + (hi - lo) * wave(seed, (tick + i) / 1.6))
}

/** The current value of a simulated live reading (see `live` in sample.ts). */
export function liveValue(reading: LiveReading, tick: number): number {
  const { base, spread, seed } = live[reading]
  return wobble(base, spread, seed, tick)
}

export function clamp(value: number, lo = 0, hi = 1): number {
  return Math.min(hi, Math.max(lo, value))
}

export function fixed(value: number, digits = 1): string {
  return value.toFixed(digits)
}
