import { faq } from '../faq'
import { Container, Reveal, SectionHeader } from './ui'

export function FaqSection() {
  return (
    <section id="faq" className="bg-white py-24 lg:py-32">
      <Container className="flex flex-col gap-12 lg:flex-row lg:gap-[72px]">
        <SectionHeader eyebrow="FAQ" title="Questions, answered." className="lg:w-[400px] lg:shrink-0">
          What MoniMac does, what it costs, and how it compares with the system monitors you may already know.
        </SectionHeader>
        <Reveal className="min-w-0 flex-1" delay={0.1}>
          {faq.map(({ question, answer }) => (
            <div key={question} className="flex flex-col gap-2 border-t border-line py-6 last:border-b">
              <h3 className="text-[19px]/[25px] font-semibold tracking-[-0.3px] text-ink">{question}</h3>
              <p className="text-[16px]/[25px] text-ink-2">{answer}</p>
            </div>
          ))}
        </Reveal>
      </Container>
    </section>
  )
}
