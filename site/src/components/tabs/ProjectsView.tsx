import { projects, type DevServer } from '../../data/sample'
import { ArrowUpRightIcon, BoxIcon, BranchIcon, CodeIcon, FolderIcon, HexagonIcon, SparkleIcon, StopIcon } from '../icons'

function ServerGlyph({ server }: { server: DevServer }) {
  const Icon = server.docker ? BoxIcon : server.type === 'FastAPI' ? CodeIcon : HexagonIcon
  const bg = server.docker ? '#0a84ff' : server.type === 'FastAPI' ? '#2f6fb3' : '#4c9a52'
  return (
    <span className="flex size-7 shrink-0 items-center justify-center rounded-lg text-white" style={{ background: bg }} aria-hidden="true">
      <Icon size={15} strokeWidth={2} />
    </span>
  )
}

const activityColor = { active: 'var(--success)', recent: 'var(--text-3)', idle: 'var(--warning)' }

/** Projects: dev servers and containers grouped by project folder. */
export function ProjectsView({ showBanner = true }: { showBanner?: boolean }) {
  return (
    <div className="space-y-4">
      {showBanner && (
        <div className="flex flex-col gap-3 rounded-xl border border-warning/40 bg-warning/10 p-3.5 sm:flex-row sm:items-center">
          <div className="flex min-w-0 flex-1 gap-3">
            <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-warning/20 text-warning" aria-hidden="true">
              <SparkleIcon size={17} />
            </span>
            <div className="min-w-0">
              <div className="text-[13px] font-semibold">{projects.banner.title}</div>
              <div className="text-[11.5px] text-text-2">{projects.banner.body}</div>
            </div>
          </div>
          <div className="flex shrink-0 gap-2 text-[12px] font-medium" aria-hidden="true">
            <span className="rounded-md border border-sep bg-surface-raised px-3 py-1">Ignore</span>
            <span className="rounded-md bg-warning px-3 py-1 text-[#3a2600]">Stop Idle Servers</span>
          </div>
        </div>
      )}

      <div className="hidden grid-cols-[1fr_88px_80px_76px_118px_28px] gap-3 px-3.5 text-[11px] text-text-3 md:grid" aria-hidden="true">
        <span>Server</span>
        <span>Port</span>
        <span>Uptime</span>
        <span>Memory</span>
        <span>Activity</span>
        <span />
      </div>

      {projects.list.map((project) => (
        <div key={project.name} className="overflow-hidden rounded-xl border border-sep">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 bg-surface px-3.5 py-2.5">
            <FolderIcon size={16} className={project.stale ? 'text-warning' : 'text-accent'} />
            <span className="text-[13.5px] font-semibold">{project.name}</span>
            <span className="hidden text-[11px] text-text-3 sm:inline">{project.path}</span>
            <span className="flex items-center gap-1 rounded-md bg-track/80 px-1.5 py-0.5 text-[10.5px] text-text-2">
              <BranchIcon size={11} />
              {project.branch} · {project.servers.length} servers
            </span>
            <span className="ml-auto text-[12.5px] font-semibold tabular-nums">{project.memory}</span>
            <span className={`text-[12px] font-medium ${project.stale ? 'text-danger' : 'text-accent'}`}>Stop All</span>
          </div>
          <ul className="divide-y divide-sep">
            {project.servers.map((server) => (
              <li
                key={server.command}
                className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1.5 px-3.5 py-2.5 md:grid-cols-[1fr_88px_80px_76px_118px_28px]"
              >
                <div className="flex min-w-0 items-center gap-2.5">
                  <ServerGlyph server={server} />
                  <div className="min-w-0">
                    <div className="truncate font-mono text-[12px]">{server.command}</div>
                    <div className="text-[10.5px] text-text-3">{server.type}</div>
                  </div>
                </div>
                <span className="justify-self-end md:justify-self-start">
                  {server.port ? (
                    <span className="inline-flex items-center gap-0.5 rounded-md bg-accent/12 px-1.5 py-0.5 font-mono text-[11px] text-accent">
                      :{server.port}
                      <ArrowUpRightIcon size={10} strokeWidth={2.2} />
                    </span>
                  ) : (
                    <span className="text-text-3">—</span>
                  )}
                </span>
                <span className="hidden text-[12px] text-text-2 tabular-nums md:block">{server.uptime}</span>
                <span className="hidden text-[12px] font-semibold tabular-nums md:block">{server.memory}</span>
                <span
                  className={`col-span-2 flex items-center gap-1.5 text-[12px] md:col-span-1 ${server.state === 'idle' ? 'font-medium text-warning' : 'text-text-2'}`}
                >
                  <span className="size-1.5 rounded-full" style={{ background: activityColor[server.state] }} />
                  {server.activity}
                  <span className="text-text-3 md:hidden">
                    · {server.uptime} · {server.memory}
                  </span>
                </span>
                <span
                  className={`hidden size-6 items-center justify-center rounded-md md:flex ${server.state === 'idle' ? 'bg-danger/10 text-danger' : 'bg-track/70 text-text-2'}`}
                  aria-hidden="true"
                >
                  <StopIcon size={13} />
                </span>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  )
}
