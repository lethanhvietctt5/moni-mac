import { useState } from 'react'
import { useLiveTick } from '../hooks/useLiveTick'
import { AppWindow } from './AppWindow'
import { InfoIcon } from './icons'
import { Reveal, Section } from './Section'

export function Demo() {
  const [selected, setSelected] = useState('overview')
  const [ref, tick] = useLiveTick<HTMLDivElement>(2000)

  return (
    <Section
      id="features"
      eyebrow="Take it for a spin"
      title="One window for the whole machine."
      intro="CPU, memory, GPU, network, disk, battery, Bluetooth, sound, temperatures, and your dev servers, each with history and the apps behind the numbers. Click around."
    >
      <Reveal className="mt-12 sm:mt-16">
        <div ref={ref}>
          <AppWindow selected={selected} onSelect={setSelected} tick={tick} />
        </div>
        <p className="mx-auto mt-5 flex max-w-xl items-start justify-center gap-2 text-center text-[13px] text-ink-3">
          <InfoIcon size={15} className="mt-[2px] shrink-0" />
          <span>
            Simulated data. A web page can't read your Mac, so these numbers are samples. Pick a tab with the mouse, or
            focus the tabs and use the arrow keys.
          </span>
        </p>
      </Reveal>
    </Section>
  )
}
