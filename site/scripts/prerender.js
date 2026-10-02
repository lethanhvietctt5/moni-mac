// Puts the rendered page into dist/index.html, so search engines and link previews get the content without
// running JavaScript, then writes the structured data, sitemap.xml and robots.txt. `npm run build` runs it.
import { readFile, rm, writeFile } from 'node:fs/promises'

const server = new URL('../dist-ssr/entry-server.js', import.meta.url)
const { render, structuredData, SITE_URL } = await import(server.href)
const page = new URL('../dist/index.html', import.meta.url)

const html = await readFile(page, 'utf8')
const root = '<div id="root"></div>'
if (!html.includes(root)) throw new Error(`dist/index.html has no empty ${root}`)
// `<` is escaped so no text inside the JSON can close the script element.
const json = (data) => JSON.stringify(data).replaceAll('<', '\\u003c')
const ldScripts = structuredData()
  .map((data) => `    <script type="application/ld+json">${json(data)}</script>\n`)
  .join('')
await writeFile(
  page,
  html.replace(root, `<div id="root">${render()}</div>`).replace('</head>', `${ldScripts}  </head>`),
)

const today = new Date().toISOString().slice(0, 10)
await writeFile(
  new URL('../dist/sitemap.xml', import.meta.url),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${SITE_URL}/</loc>
    <lastmod>${today}</lastmod>
  </url>
</urlset>
`,
)
await writeFile(new URL('../dist/robots.txt', import.meta.url), `User-agent: *\nAllow: /\n\nSitemap: ${SITE_URL}/sitemap.xml\n`)

await rm(new URL('../dist-ssr', import.meta.url), { recursive: true })
