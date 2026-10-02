# MoniMac website

The landing page for MoniMac: React, Vite, TypeScript, Tailwind CSS, and Motion. It makes no external requests (no fonts, scripts, trackers, or analytics), and the page says so, so keep it that way.

## Develop

```bash
cd site
npm install
npm run dev       # http://localhost:5173
npm run build     # type-checks, then builds to dist/
npm run lint
npm run preview   # serves dist/
```

## Layout

- `src/components/`: one file per section, plus the mockups (`MenuBar`, `Popover`, `AppWindow` with its tabs in `tabs/`, `ShareCard`, `Notification`, `CodeBlock`, `FAQ`).
- `src/data/sample.ts`: every number the mockups show, so they agree with each other. The mockups follow the Pencil designs; metric colors come from `App/Sources/Palette.swift`.
- `src/hooks/useLiveTick.ts`: drives the simulated live values. It ticks only while a mockup is on screen and the tab is visible, and not at all with reduced motion.
- `public/`: icons made from `App/Icon/AppIcon-source.png`, and `og.png`.

## Open Graph image

`public/og.png` (1200 × 630) is rendered from `og/og.html` with headless Chrome:

```bash
npm run og
```

Commit the new PNG. Once the site has a domain, make `og:image` and `twitter:image` in `index.html` absolute and add the canonical link (both are marked TODO).

## Deploy on Vercel

Import the repository and set:

| Setting | Value |
| --- | --- |
| Root Directory | `site` |
| Framework Preset | Vite |
| Build Command | `npm run build` |
| Output Directory | `dist` |

`vercel.json` caches the hashed files in `assets/` for a year and sets a strict Content Security Policy (self only), which also guards the no-external-requests promise.
