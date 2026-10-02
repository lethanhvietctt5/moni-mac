import { StrictMode } from 'react'
import { renderToString } from 'react-dom/server'
import App from './App'
import { faq } from './faq'
import { DOWNLOAD_URL, MIN_MACOS, REPO_URL, SITE_URL, VERSION } from './site'

export { SITE_URL }

/** The page's markup, which scripts/prerender.js puts inside #root. */
export function render() {
  return renderToString(
    <StrictMode>
      <App />
    </StrictMode>,
  )
}

/** Schema.org data for search engines: the app itself, and the FAQ section's questions. */
export function structuredData() {
  return [
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'MoniMac',
      description:
        'A free, open-source system monitor for macOS: CPU, memory, GPU, network and temperature in the menu bar, plus disk, battery and per-app usage with up to 90 days of history.',
      url: `${SITE_URL}/`,
      image: `${SITE_URL}/icon-256.webp`,
      screenshot: `${SITE_URL}/shots/hero.webp`,
      applicationCategory: 'UtilitiesApplication',
      operatingSystem: 'macOS',
      softwareVersion: VERSION,
      softwareRequirements: `Apple silicon, ${MIN_MACOS}`,
      downloadUrl: DOWNLOAD_URL,
      isAccessibleForFree: true,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      sameAs: [REPO_URL],
    },
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: faq.map(({ question, answer }) => ({
        '@type': 'Question',
        name: question,
        acceptedAnswer: { '@type': 'Answer', text: answer },
      })),
    },
  ]
}
