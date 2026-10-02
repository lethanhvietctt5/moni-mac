# MoniMac website

The landing page for MoniMac: React, Vite, TypeScript, Tailwind CSS, and Motion. It makes no external requests (no fonts, scripts, trackers, or analytics). Keep it that way: the Content-Security-Policy in `vercel.json` blocks them.

## Develop

```bash
cd site
npm install
npm run dev       # http://localhost:5173
npm run build     # type-checks, builds to dist/, then prerenders the page (see SEO)
npm run lint
npm run preview   # serves dist/
```

## Layout

- `src/components/`: one file per section (`Nav`, `Hero`, `MenuBarSection`, `MetricsSection`, `AlertsSection`, `DevicesSection`, `FaqSection`, `DownloadFooter`), plus shared pieces in `ui.tsx`.
- `src/site.ts`: links, the version, and the macOS requirement. Bump `VERSION` when a release ships.
- `src/faq.ts`: the FAQ section's questions, which also become FAQPage structured data. Keep every answer true to the app.
- `.env`: `VITE_SITE_URL`, the public URL. Change it there if the domain changes.
- `src/live.ts`: the sample readings that tick in the menu bar mockups.
- `public/shots/`: the app mockups, exported at 2× WebP from the "MoniMac Landing Page" frame of the Pencil design. Re-export them there when the design changes.

The page follows the Pencil design's "MoniMac Landing Page" frame. It's light only, and fonts are bundled (Inter via `@fontsource-variable/inter`), so the page makes no external requests.

## SEO

`npm run build` ships the page prerendered, so crawlers that don't run JavaScript still read it. After the client build, it builds `src/entry-server.tsx` for Node, and `scripts/prerender.js` then:

- renders the app into `dist/index.html`'s `#root` (`main.tsx` hydrates it)
- adds the structured data (SoftwareApplication with `VERSION`, and FAQPage)
- writes `sitemap.xml` and `robots.txt`

Prerendering means the first render must be the same on the server and in the browser. Render nothing from `window`, the time, randomness, or `useReducedMotion()`: `MotionConfig reducedMotion="user"` in `App.tsx` handles reduced motion. Entrance animations start at `opacity: 0` in the HTML, and a `<noscript>` style in `index.html` shows them without JavaScript.
