import { motion } from 'motion/react'
import type { ReactNode } from 'react'

/** The 1200 px column the design lays every section on. */
export function Container({ className = '', children }: { className?: string; children: ReactNode }) {
  return <div className={`mx-auto w-full max-w-[1248px] px-6 ${className}`}>{children}</div>
}

/** Fades and lifts its content in the first time it scrolls into view. */
export function Reveal({
  className,
  delay = 0,
  children,
}: {
  className?: string
  delay?: number
  children: ReactNode
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '0px 0px -80px 0px' }}
      transition={{ duration: 0.7, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  )
}

/**
 * A mockup exported from the Pencil design at 2×. `width` and `height` are the design's
 * point size, so the browser reserves the space before the image loads.
 */
export function Shot({
  name,
  alt,
  width,
  height,
  className = '',
  eager = false,
}: {
  name: string
  alt: string
  width: number
  height: number
  className?: string
  eager?: boolean
}) {
  return (
    <img
      src={`/shots/${name}.webp`}
      alt={alt}
      width={width}
      height={height}
      loading={eager ? 'eager' : 'lazy'}
      decoding="async"
      draggable={false}
      className={`block h-auto max-w-full select-none ${className}`}
    />
  )
}

/** A numbered point in a section's story column, separated by hairlines. */
export function StoryPoint({ number, title, children }: { number: string; title: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-2 border-t border-line pt-6 pb-7">
      <span className="text-[13px] font-semibold tracking-[0.4px] text-ink-3">{number}</span>
      <h3 className="text-[21px]/[27px] font-semibold tracking-[-0.3px] text-ink">{title}</h3>
      <p className="text-[16px]/[25px] text-ink-2">{children}</p>
    </div>
  )
}

/** Section eyebrow, headline, and subhead, as the design's section headers. */
export function SectionHeader({
  eyebrow,
  title,
  children,
  dark = false,
  className = '',
}: {
  eyebrow: ReactNode
  title: ReactNode
  children?: ReactNode
  dark?: boolean
  className?: string
}) {
  return (
    <Reveal className={`flex flex-col gap-5 ${className}`}>
      <p className={`text-[15px] font-semibold ${dark ? 'text-snow-2' : 'text-ink-2'}`}>{eyebrow}</p>
      <h2
        className={`max-w-[760px] text-[38px]/[42px] font-semibold tracking-[-1px] sm:text-[48px]/[52px] lg:text-[56px]/[60px] lg:tracking-[-1.6px] ${
          dark ? 'text-snow' : 'text-ink'
        }`}
      >
        {title}
      </h2>
      {children && (
        <p className={`max-w-[640px] text-[17px]/[26px] sm:text-[19px]/[29px] ${dark ? 'text-snow-2' : 'text-ink-2'}`}>
          {children}
        </p>
      )}
    </Reveal>
  )
}

/** GitHub's mark. Lucide no longer ships brand icons. */
export function GithubIcon({ className = 'size-4' }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true" className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  )
}
