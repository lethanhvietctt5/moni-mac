import { release } from '../../data/sample'
import { Card } from '../ui'

function Row({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-sep py-2.5 last:border-0">
      <div className="min-w-0">
        <div className="text-[13px]">{label}</div>
        {detail && <div className="text-[11px] text-text-2">{detail}</div>}
      </div>
      <span className="shrink-0 rounded-md bg-track/70 px-2 py-0.5 text-[12px] font-medium text-text">{value}</span>
    </div>
  )
}

export function SettingsTab() {
  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
      <Card>
        <div className="mb-1 text-[13px] font-semibold">General</div>
        <Row label="Launch at login" value="On" />
        <Row label="Refresh interval" value="2 s" detail="1 s, 2 s, or 5 s" />
        <Row label="Show icon in Dock" value="Off" />
        <Row label="CPU usage" value="System" detail="System (0–100%) or Per-core (up to 1200%)" />
      </Card>
      <Card>
        <div className="mb-1 text-[13px] font-semibold">Units &amp; Alerts</div>
        <Row label="Temperature" value="°C" detail="°C or °F" />
        <Row label="Network speed" value="MB/s" detail="MB/s or Mbps" />
        <Row label="Rapid memory growth" value="+1 GB" detail="Within 10 minutes" />
        <Row label="Heavy disk writes" value="10 GB" detail="In an hour" />
      </Card>
      <Card className="md:col-span-2">
        <div className="mb-1 text-[13px] font-semibold">Data &amp; About</div>
        <Row label="Keep history" value="30 days" detail="7, 30, or 90 days" />
        <Row label={`MoniMac ${release.version}`} value="Check for Updates…" detail="Free and open source" />
      </Card>
    </div>
  )
}
