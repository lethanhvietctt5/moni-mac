import { useEffect, useRef, useState, type RefObject } from 'react'

const reducedMotionQuery = '(prefers-reduced-motion: reduce)'

/**
 * Simulates a refresh interval for a mockup: returns a ref to attach to the
 * mockup and a tick that increments every `intervalMs`.
 *
 * It only ticks while the element is on screen and the tab is visible, and
 * never when the visitor prefers reduced motion, so off-screen mockups cost
 * nothing.
 */
export function useLiveTick<T extends Element>(intervalMs = 2000): [RefObject<T | null>, number] {
  const ref = useRef<T | null>(null)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const element = ref.current
    if (!element) return

    const reduced = window.matchMedia(reducedMotionQuery)
    let onScreen = false
    let timer: number | undefined

    const update = () => {
      const shouldRun = onScreen && document.visibilityState === 'visible' && !reduced.matches
      if (shouldRun && timer === undefined) {
        timer = window.setInterval(() => setTick((t) => t + 1), intervalMs)
      } else if (!shouldRun && timer !== undefined) {
        window.clearInterval(timer)
        timer = undefined
      }
    }

    const observer = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting
      update()
    })
    observer.observe(element)
    document.addEventListener('visibilitychange', update)
    reduced.addEventListener('change', update)

    return () => {
      observer.disconnect()
      document.removeEventListener('visibilitychange', update)
      reduced.removeEventListener('change', update)
      if (timer !== undefined) window.clearInterval(timer)
    }
  }, [intervalMs])

  return [ref, tick]
}
