import { useEffect, useRef, useState, type RefObject } from 'react'

/**
 * Scale factor that fits content `width` pixels wide into the observed
 * element's width (never above 1).
 */
export function useFitWidth<T extends HTMLElement>(width: number): [RefObject<T | null>, number] {
  const ref = useRef<T | null>(null)
  const [scale, setScale] = useState(1)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => {
      setScale(Math.min(1, entry.contentRect.width / width))
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [width])

  return [ref, scale]
}
