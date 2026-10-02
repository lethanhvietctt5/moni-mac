import { projects } from '../data/sample'
import { BranchIcon, FolderCodeIcon, GaugeIcon, StopIcon } from './icons'
import { Reveal, Section } from './Section'
import { ProjectsView } from './tabs/ProjectsView'

const points = [
  {
    icon: FolderCodeIcon,
    title: 'Grouped by project',
    body: 'Dev servers, watchers, and Docker containers land under the project folder they run from, with its current git branch.',
  },
  {
    icon: BranchIcon,
    title: 'Knows what it is',
    body: 'Next.js, Vite, Storybook, FastAPI, Docker, watchers, mock APIs: each with its port, uptime, and memory. Click a port to open it.',
  },
  {
    icon: GaugeIcon,
    title: 'Active or idle',
    body: 'A server counts as active when it gets new connections or uses CPU. Servers idle for days get a banner, so forgotten ones surface.',
  },
  {
    icon: StopIcon,
    title: 'Stop it from here',
    body: 'Stop one server, a whole project, or every idle server. MoniMac asks the process to exit and checks it’s still the one you saw.',
  },
]

export function Developers() {
  return (
    <Section
      id="developers"
      eyebrow="For developers"
      title="Find the dev server you forgot about."
      intro={`That Vite server from last week is still holding a port and most of a gigabyte. Projects shows every dev server and container you're running, grouped by project.`}
      className="bg-page-alt"
    >
      <div className="mt-12 grid grid-cols-1 gap-10 sm:mt-16 lg:grid-cols-[1fr_1.9fr] lg:gap-12">
        <Reveal>
          <ul className="space-y-6">
            {points.map(({ icon: Icon, title, body }) => (
              <li key={title} className="flex gap-3.5">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-accent/12 text-accent">
                  <Icon size={18} />
                </span>
                <div>
                  <h3 className="text-[16px] font-semibold text-ink">{title}</h3>
                  <p className="mt-1 text-[15px] leading-relaxed text-ink-2">{body}</p>
                </div>
              </li>
            ))}
          </ul>
        </Reveal>
        <Reveal delay={0.1}>
          <div
            role="img"
            aria-label={`Illustration: the Projects tab with three projects (acme-web, api-gateway, old-landing), their dev servers and containers, and a banner saying ${projects.banner.title.toLowerCase()}.`}
            className="overflow-hidden rounded-[14px] border border-sep bg-win p-3 text-text shadow-[0_24px_70px_-24px_rgba(0,0,0,0.3)] sm:p-4"
          >
            <ProjectsView />
          </div>
        </Reveal>
      </div>
    </Section>
  )
}
