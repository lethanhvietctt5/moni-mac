import { domAnimation, LazyMotion, MotionConfig } from 'motion/react'
import { Alerts } from './components/Alerts'
import { AlsoIncluded } from './components/AlsoIncluded'
import { Demo } from './components/Demo'
import { Developers } from './components/Developers'
import { FAQ } from './components/FAQ'
import { Footer } from './components/Footer'
import { Grouping } from './components/Grouping'
import { Hero } from './components/Hero'
import { Install } from './components/Install'
import { MenuBarSection } from './components/MenuBarSection'
import { Nav } from './components/Nav'
import { OpenSource } from './components/OpenSource'
import { Privacy } from './components/Privacy'

export default function App() {
  return (
    <MotionConfig reducedMotion="user">
      <LazyMotion features={domAnimation} strict>
        <a
          href="#main"
          className="sr-only z-[60] rounded-lg bg-accent px-4 py-2 text-white focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
        >
          Skip to content
        </a>
        <Nav />
        <main id="main">
          <Hero />
          <Demo />
          <Grouping />
          <MenuBarSection />
          <Developers />
          <Alerts />
          <AlsoIncluded />
          <Privacy />
          <OpenSource />
          <Install />
          <FAQ />
        </main>
        <Footer />
      </LazyMotion>
    </MotionConfig>
  )
}
