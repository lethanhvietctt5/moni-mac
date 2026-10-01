import Darwin
import Foundation

/// Per-process reads for Projects. They work for the user's own processes without privileges.
enum DevProcessInfo {
    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func startTime(_ info: proc_bsdinfo) -> Date {
        Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    /// The kernel's name for the process (up to 32 characters, e.g. "com.docker.backend").
    static func name(_ info: proc_bsdinfo) -> String {
        var info = info
        let name = withUnsafeBytes(of: &info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if !name.isEmpty { return name }
        return withUnsafeBytes(of: &info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// The working directory.
    static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static let argumentsMax: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctl(&mib, 2, &value, &size, nil, 0) == 0 ? Int(value) : 256 * 1024
    }()

    /// argv, from `KERN_PROCARGS2`: argc, the executable path, padding NULs, then argv's strings.
    static func arguments(_ pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argumentsMax
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseArguments(buffer.prefix(size))
    }

    static func parseArguments(_ buffer: ArraySlice<UInt8>) -> [String]? {
        guard buffer.count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = buffer.startIndex + MemoryLayout<Int32>.size
        // Skip the executable path, then the NULs that pad it.
        while index < buffer.endIndex, buffer[index] != 0 { index += 1 }
        while index < buffer.endIndex, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < buffer.endIndex {
            let start = index
            while index < buffer.endIndex, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// CPU time in seconds and the physical footprint.
    static func usage(_ pid: Int32, timebase: (numer: UInt64, denom: UInt64)) -> (cpuTime: TimeInterval, memory: UInt64)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return nil }
        // rusage reports CPU time in Mach absolute time units.
        let nanoseconds = (usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom
        return (Double(nanoseconds) / 1_000_000_000, usage.ri_phys_footprint)
    }

    struct Sockets {
        /// Ports with a TCP listener, ascending.
        var listening: [UInt16] = []
        /// Established TCP connections: (local port, "remoteAddress:remotePort").
        var established: [(port: UInt16, peer: String)] = []
    }

    /// The process's TCP sockets. Only socket descriptors are inspected; a dev server can hold
    /// hundreds of file and kqueue descriptors.
    static func sockets(_ pid: Int32) -> Sockets {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return Sockets() }
        let capacity = Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride + 16
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(capacity * MemoryLayout<proc_fdinfo>.stride))
        guard used > 0 else { return Sockets() }
        var listening = Set<UInt16>()
        var established: [(port: UInt16, peer: String)] = []
        for fd in fds.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            let local = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            switch tcp.tcpsi_state {
            case TSI_S_LISTEN:
                listening.insert(local)
            case TSI_S_ESTABLISHED:
                let remotePort = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_fport))
                established.append((local, "\(address(tcp.tcpsi_ini)):\(remotePort)"))
            default:
                continue
            }
        }
        return Sockets(listening: listening.sorted(), established: established)
    }

    private static func address(_ info: in_sockinfo) -> String {
        var info = info
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if info.insi_vflag & UInt8(INI_IPV4) != 0 {
            var address = info.insi_faddr.ina_46.i46a_addr4
            inet_ntop(AF_INET, &address, &text, socklen_t(text.count))
        } else {
            inet_ntop(AF_INET6, &info.insi_faddr.ina_6, &text, socklen_t(text.count))
        }
        return String(decoding: text.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
