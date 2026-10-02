import { Plus } from 'lucide-react'
import { faq } from '../faq'
import { Container, Reveal, SectionHeader } from './ui'

export function FaqSection() {
  return (
    <section id="faq" className="bg-white py-24 lg:py-32">
      <Container className="flex flex-col gap-12 lg:flex-row lg:gap-[72px]">
        <SectionHeader eyebrow="FAQ" title="Questions, answered." className="lg:w-[400px] lg:shrink-0">
          What MoniMac does, what it costs, and how it compares with the system monitors you may already know.
        </SectionHeader>
        {/* Native <details>: the answers stay in the HTML for search engines, open without JavaScript,
            and open themselves when find-in-page matches them. */}
        <Reveal className="min-w-0 flex-1" delay={0.1}>
          {faq.map(({ question, answer }) => (
            <details key={question} className="faq-item group border-t border-line last:border-b">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-6 [&::-webkit-details-marker]:hidden">
                <h3 className="text-[19px]/[25px] font-semibold tracking-[-0.3px] text-ink">{question}</h3>
                <Plus
                  className="size-5 shrink-0 text-ink-3 transition-transform duration-300 group-open:rotate-45"
                  strokeWidth={2}
                  aria-hidden="true"
                />
              </summary>
              <p className="pr-11 pb-6 text-[16px]/[25px] text-ink-2">{answer}</p>
            </details>
          ))}
        </Reveal>
      </Container>
    </section>
  )
}
