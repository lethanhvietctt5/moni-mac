import CoreWLAN
import Darwin
import Foundation
import MoniMacCore
import SystemConfiguration

/// Reads network for each snapshot.
///
/// Rates come from the kernel's 64-bit per-interface byte counters (`NET_RT_IFLIST2`), summed over
/// the physical interfaces (`en*`: Wi-Fi, Ethernet, tethering), so VPN tunnels aren't counted twice.
/// The active interface's details (name, Wi-Fi network, link rate) change rarely and cost XPC calls,
/// so they're re-read every `detailsInterval`.
@MainActor
final class NetworkReader {
    private struct Counters {
        var received: UInt64
        var sent: UInt64
        /// Link speed in bits per second, as the driver reports it (0 if unknown).
        var baudRate: UInt64
    }

    private var previous: (counters: [String: Counters], uptime: UInt64)?
    private var buffer = [UInt8]()
    private var details: (interface: NetworkInterface?, uptime: UInt64)?
    private var displayNames: [String: String] = [:]
    private let store = SCDynamicStoreCreate(nil, "MoniMac" as CFString, nil, nil)
    private let processes = NetworkProcessReader()
    private let detailsInterval: UInt64 = 10_000_000_000

    func sample() -> Reading<NetworkReading> {
        guard let counters = readCounters() else { return .unavailable(.failed("sysctl(NET_RT_IFLIST2) failed")) }
        let uptime = DispatchTime.now().uptimeNanoseconds
        defer { previous = (counters, uptime) }
        let interface = activeInterface(counters: counters, uptime: uptime)
        guard let previous, uptime > previous.uptime else { return .unavailable(.warmingUp) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, now) in counters {
            // A new interface starts its baseline; a reset counter (driver reload) contributes nothing.
            guard let before = previous.counters[name] else { continue }
            received += now.received >= before.received ? now.received - before.received : 0
            sent += now.sent >= before.sent ? now.sent - before.sent : 0
        }
        let seconds = Double(uptime - previous.uptime) / 1_000_000_000
        return .value(NetworkReading(
            interface: interface,
            downloadPerSecond: Double(received) / seconds, uploadPerSecond: Double(sent) / seconds,
            received: Double(received), sent: Double(sent)
        ))
    }

    /// Adds per-process network figures (`ResourceUse.network`) to the process list.
    /// Called only when the process list is refreshed (every few seconds), never with a stale list.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        self.processes.refreshIfDue()
        guard case .value(var list) = processes, let rates = self.processes.latest() else { return processes }
        for index in list.indices {
            // nettop lists every process with sockets; absent means no traffic.
            list[index].resources.network = rates[list[index].pid] ?? 0
        }
        return .value(list)
    }

    // MARK: Interface details

    private func activeInterface(counters: [String: Counters], uptime: UInt64) -> NetworkInterface? {
        if let details, uptime - details.uptime < detailsInterval { return details.interface }
        let interface = readActiveInterface(counters: counters)
        details = (interface, uptime)
        return interface
    }

    private func readActiveInterface(counters: [String: Counters]) -> NetworkInterface? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let bsdName = global["PrimaryInterface"] as? String
        else { return nil }

        if CWWiFiClient.shared().interfaceNames()?.contains(bsdName) == true,
           let wifi = CWWiFiClient.shared().interface(withName: bsdName) {
            let rate = wifi.transmitRate()
            return NetworkInterface(
                name: Self.wifiName(phyMode: wifi.activePHYMode().rawValue, band: wifi.wlanChannel()?.channelBand.rawValue),
                // Nil unless MoniMac has Location permission.
                networkName: wifi.ssid(),
                linkRate: rate > 0 ? rate * 1_000_000 : nil
            )
        }
        let baudRate = counters[bsdName]?.baudRate ?? 0
        return NetworkInterface(name: displayName(bsdName), linkRate: baudRate > 0 ? Double(baudRate) : nil)
    }

    /// "Wi-Fi 6E" from the PHY mode (`CWPHYMode`) and band (`CWChannelBand`), compared by raw value
    /// so newer modes don't need newer SDK availability checks.
    static func wifiName(phyMode: Int, band: Int?) -> String {
        switch phyMode {
        case 7: "Wi-Fi 7"  // 802.11be
        case 6: band == 3 ? "Wi-Fi 6E" : "Wi-Fi 6"  // 802.11ax; 6E on the 6 GHz band
        case 5: "Wi-Fi 5"  // 802.11ac
        case 4: "Wi-Fi 4"  // 802.11n
        default: "Wi-Fi"
        }
    }

    /// The name System Settings uses, e.g. "Ethernet", "iPhone USB", "Thunderbolt Bridge". Cached per interface.
    private func displayName(_ bsdName: String) -> String {
        if let cached = displayNames[bsdName] { return cached }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let name = interfaces.first { SCNetworkInterfaceGetBSDName($0) as String? == bsdName }
            .flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
            ?? (bsdName.hasPrefix("utun") || bsdName.hasPrefix("ipsec") ? "VPN" : bsdName)
        displayNames[bsdName] = name
        return name
    }

    // MARK: Counters

    /// Per-interface counters for the physical (`en*`) interfaces, or nil if the sysctl fails.
    private func readCounters() -> [String: Counters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        // The table can grow between sizing and reading; retry with room to spare.
        for _ in 0..<3 {
            guard sysctl(&mib, 6, nil, &length, nil, 0) == 0 else { return nil }
            if buffer.count < length { buffer = [UInt8](repeating: 0, count: length + length / 4) }
            length = buffer.count
            if sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 { return Self.parse(buffer, length: length) }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    /// Walks `RTM_IFINFO2` messages: each `if_msghdr2` is followed by the interface's `sockaddr_dl`.
    private static func parse(_ buffer: [UInt8], length: Int) -> [String: Counters] {
        let headerSize = MemoryLayout<if_msghdr2>.stride
        var result: [String: Counters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                defer { offset += messageLength }
                guard Int32(header.ifm_type) == RTM_IFINFO2, headerSize + 8 <= messageLength else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                // sockaddr_dl: sdl_nlen is byte 5, the name starts at byte 8.
                let address = offset + headerSize
                let nameLength = Int(raw[address + 5])
                guard nameLength >= 3, headerSize + 8 + nameLength <= messageLength,
                      raw[address + 8] == UInt8(ascii: "e"), raw[address + 9] == UInt8(ascii: "n"),
                      message.ifm_flags & IFF_LOOPBACK == 0
                else { continue }
                let name = String(decoding: raw[(address + 8)..<(address + 8 + nameLength)], as: UTF8.self)
                result[name] = Counters(
                    received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes,
                    baudRate: message.ifm_data.ifi_baudrate
                )
            }
        }
        return result
    }
}
