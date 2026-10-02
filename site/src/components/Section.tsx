import { m } from 'motion/react'
import { useId, type ReactNode } from 'react'

/** Fades content in once as it scrolls into view. */
export function Reveal({ children, className = '', delay = 0 }: { children: ReactNode; className?: string; delay?: number }) {
  return (
    <m.div
      className={className}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '0px 0px -10% 0px' }}
      transition={{ duration: 0.6, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </m.div>
  )
}

/** A page section with an eyebrow, a heading, and an intro paragraph. */
export function Section({
  id,
  eyebrow,
  title,
  intro,
  children,
  className = '',
  align = 'center',
}: {
  id?: string
  eyebrow?: string
  title: ReactNode
  intro?: ReactNode
  children?: ReactNode
  className?: string
  align?: 'center' | 'left'
}) {
  const headingId = useId()
  return (
    <section id={id} aria-labelledby={headingId} className={`px-4 py-20 sm:px-6 sm:py-24 ${className}`}>
      <div className="mx-auto max-w-6xl">
        <Reveal className={align === 'center' ? 'mx-auto max-w-2xl text-center' : 'max-w-2xl'}>
          {eyebrow && <p className="mb-3 text-[13px] font-semibold tracking-wide text-accent uppercase">{eyebrow}</p>}
          <h2 id={headingId} className="text-[32px] leading-[1.1] font-semibold tracking-tight text-balance text-ink sm:text-[44px]">
            {title}
          </h2>
          {intro && <p className="mt-4 text-[17px] leading-relaxed text-pretty text-ink-2 sm:text-[19px]">{intro}</p>}
        </Reveal>
        {children}
      </div>
    </section>
  )
}
