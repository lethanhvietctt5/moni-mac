import { MotionConfig } from 'motion/react'
import { AlertsSection } from './components/AlertsSection'
import { DevicesSection } from './components/DevicesSection'
import { DownloadFooter } from './components/DownloadFooter'
import { FaqSection } from './components/FaqSection'
import { Hero } from './components/Hero'
import { MenuBarSection } from './components/MenuBarSection'
import { MetricsSection } from './components/MetricsSection'
import { Nav } from './components/Nav'

export default function App() {
  // The page is prerendered, so animations never branch on reduced motion while rendering (the server
  // can't know it). Motion drops the movement for those visitors instead and keeps only the fades.
  return (
    <MotionConfig reducedMotion="user">
      <Nav />
      <main>
        <Hero />
        <MenuBarSection />
        <MetricsSection />
        <AlertsSection />
        <DevicesSection />
        <FaqSection />
      </main>
      <DownloadFooter />
    </MotionConfig>
  )
}
