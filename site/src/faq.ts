import { MIN_MACOS } from './site'

// Questions people search for, answered in plain text: the FAQ section renders these,
// and the prerender turns them into FAQPage structured data. Keep every answer true to the app.
export const faq: { question: string; answer: string }[] = [
  {
    question: 'What is MoniMac?',
    answer:
      'MoniMac is a free, open-source system monitor for macOS. It puts CPU, memory, GPU, network and temperature in your menu bar, and its popover and window add disk, battery, Bluetooth devices and sound, show which apps use the most CPU, memory, GPU, network, disk and power, and keep up to 90 days of history.',
  },
  {
    question: 'Is MoniMac really free?',
    answer:
      'Yes. MoniMac is free and open source, with no paid tier, subscription, account or license key. The source code is on GitHub.',
  },
  {
    question: 'How is MoniMac different from Activity Monitor?',
    answer:
      'Activity Monitor shows what is running right now. MoniMac keeps the numbers in your menu bar, groups helper processes under the app they belong to, keeps up to 90 days of history, shows temperatures and fan speeds, and alerts you when an app keeps using too much CPU, memory, disk or network.',
  },
  {
    question: 'Is MoniMac an alternative to iStat Menus or Stats?',
    answer:
      'Yes. Like iStat Menus and Stats, MoniMac shows CPU, memory, GPU, network and temperature in the macOS menu bar, with disk, battery and Bluetooth devices in its window. iStat Menus is paid; MoniMac is free and open source. MoniMac also alerts you when an app keeps using too much, sets the volume of each app, and finds local dev servers you forgot to stop.',
  },
  {
    question: 'How do I check CPU temperature and fan speed on a Mac?',
    answer:
      'macOS has no built-in view for sensor temperatures. MoniMac reads them from the System Management Controller and shows CPU, GPU and other sensor temperatures and fan speeds in its Temperature & Fans tab, and can show a temperature in the menu bar. It only reads them: MoniMac never changes fan speeds and needs no admin password.',
  },
  {
    question: 'How do I find out why my Mac is slow?',
    answer:
      'Open MoniMac’s popover or window to see which apps are using the most CPU, memory, GPU, disk and network right now, and look at the history to see when it started. Alerts tell you when an app stays busy for minutes or its memory grows fast, and you can quit the app, with its helper processes, right from the list.',
  },
  {
    question: 'Does MoniMac slow down my Mac?',
    answer:
      'No. MoniMac is a native Swift app under 10 MB, built to use less than 1% CPU on average with the popover closed. Each reading is refreshed only as often as it changes.',
  },
  {
    question: 'Which Macs does MoniMac support?',
    answer: `MoniMac runs on Macs with Apple silicon (M1 or later) and needs ${MIN_MACOS}. Intel Macs aren’t supported.`,
  },
  {
    question: 'Does MoniMac collect my data?',
    answer:
      'No. MoniMac has no analytics, tracking or account. Its history is a database on your Mac, and the only connection it makes itself is checking GitHub for updates.',
  },
  {
    question: 'How do I install MoniMac?',
    answer:
      'Download the disk image, drag MoniMac into Applications, and run “xattr -dr com.apple.quarantine /Applications/MoniMac.app” in Terminal once. MoniMac isn’t notarized by Apple, so macOS blocks it until that flag is removed. Updates install from inside the app.',
  },
]
