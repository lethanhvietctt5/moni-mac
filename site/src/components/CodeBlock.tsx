import { useEffect, useState } from 'react'
import { CheckIcon, CopyIcon } from './icons'

/** A shell command with a copy button that confirms the copy. */
export function CodeBlock({ code, label }: { code: string; label: string }) {
  const [status, setStatus] = useState<'idle' | 'copied' | 'failed'>('idle')

  useEffect(() => {
    if (status === 'idle') return
    const timer = window.setTimeout(() => setStatus('idle'), 2000)
    return () => window.clearTimeout(timer)
  }, [status])

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setStatus('copied')
    } catch {
      setStatus('failed')
    }
  }

  return (
    <div className="scheme-dark group relative overflow-hidden rounded-xl border border-white/10 bg-[#111216] text-[#f5f5f7]">
      <div className="flex items-center justify-between border-b border-white/[0.07] px-4 py-2">
        <span className="text-[12px] font-medium text-[#a1a1a6]">{label}</span>
        <button
          type="button"
          onClick={copy}
          className={`flex items-center gap-1.5 rounded-md px-2.5 py-1 text-[12px] font-medium transition-colors ${
            status === 'copied' ? 'bg-[#30d158]/15 text-[#30d158]' : 'text-[#c7c7cc] hover:bg-white/10'
          }`}
        >
          {status === 'copied' ? <CheckIcon size={14} strokeWidth={2.4} /> : <CopyIcon size={14} />}
          {status === 'copied' ? 'Copied' : status === 'failed' ? 'Press ⌘C to copy' : 'Copy'}
        </button>
      </div>
      <pre className="px-4 py-3.5 font-mono text-[13px] leading-relaxed break-all whitespace-pre-wrap">
        <code>
          <span className="text-[#6c6c70] select-none">$ </span>
          {code}
        </code>
      </pre>
      <span className="sr-only" role="status" aria-live="polite">
        {status === 'copied' ? 'Copied to clipboard' : status === 'failed' ? 'Copy failed; select the text and copy it' : ''}
      </span>
    </div>
  )
}
