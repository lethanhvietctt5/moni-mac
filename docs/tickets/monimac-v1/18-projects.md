# 18 — Projects

**What to build:** The **Projects** tab. **ProjectCatalog** builds projects from listening sockets and Docker containers, following each process to its working directory and then to the enclosing project root (nearest git repo or package manifest). Each project shows its name, path, git branch, server count, total memory, and Stop All. Each server row shows the command, a detected type (Next.js, Vite, Storybook, FastAPI, Docker, Watcher, Mock API, …), port, uptime, memory, and activity ("Active · now", "Idle 4 days"). Clicking a port opens it in the browser; there are also Stop per server and reveal-in-Finder per project. **Idle** means no new inbound connections on any of the server's ports *and* CPU under a small floor; watchers with no port are idle by CPU alone. Servers idle for 2 days or more trigger a banner with "Stop Idle Servers" and "Ignore"; Ignore hides it until the project is active again. The subtitle summarizes the totals.

**Blocked by:** 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] Running dev servers and containers appear grouped under the right project
- [ ] Server types are detected from the command line and ports
- [ ] Idle status follows the definition, verified with scripted connection and CPU histories
- [ ] Stop, Stop All, Stop Idle Servers, open port, and reveal in Finder record the right actions
- [ ] Ignore suppresses the banner until the project becomes active
