import { AlertsSection } from './components/AlertsSection'
import { DevicesSection } from './components/DevicesSection'
import { DownloadFooter } from './components/DownloadFooter'
import { Hero } from './components/Hero'
import { MenuBarSection } from './components/MenuBarSection'
import { MetricsSection } from './components/MetricsSection'
import { Nav } from './components/Nav'

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <MenuBarSection />
        <MetricsSection />
        <AlertsSection />
        <DevicesSection />
      </main>
      <DownloadFooter />
    </>
  )
}
