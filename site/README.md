# MoniMac website

The landing page for MoniMac: React, Vite, TypeScript, Tailwind CSS, and Motion. It makes no external requests (no fonts, scripts, trackers, or analytics). Keep it that way: the Content-Security-Policy in `vercel.json` blocks them.

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

- `src/components/`: one file per section (`Nav`, `Hero`, `MenuBarSection`, `MetricsSection`, `AlertsSection`, `DevicesSection`, `DownloadFooter`), plus shared pieces in `ui.tsx`.
- `src/site.ts`: links, the version, and the macOS requirement. Bump `VERSION` when a release ships.
- `src/live.ts`: the sample readings that tick in the menu bar mockups.
- `public/shots/`: the app mockups, exported at 2× WebP from the "MoniMac Landing Page" frame of the Pencil design. Re-export them there when the design changes.

The page follows the Pencil design's "MoniMac Landing Page" frame. It's light only, and fonts are bundled (Inter via `@fontsource-variable/inter`), so the page makes no external requests.
