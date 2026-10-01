import Darwin
import Foundation
import MoniMacCore

/// A minimal Docker Engine API client over its unix socket. Blocking; call it off the main thread.
///
/// It speaks HTTP/1.0, so the engine answers without chunked encoding and closes the connection,
/// and the whole response is read until EOF.
struct DockerClient: Sendable {
    let socketPath: String
    var timeout: TimeInterval = 3

    /// Docker Desktop's per-user socket, then the system one. Nil when neither exists, i.e. Docker
    /// isn't installed. A link left behind while Docker is quit still counts: connecting to it fails,
    /// which reads as "not running".
    static func locate() -> DockerClient? {
        let candidates = [NSHomeDirectory() + "/.docker/run/docker.sock", "/var/run/docker.sock"]
        return candidates.first { path in
            var info = stat()
            return lstat(path, &info) == 0
        }.map { DockerClient(socketPath: $0) }
    }

    enum Failure: Error {
        /// Nothing accepted the connection: Docker isn't running.
        case notRunning
        case http(Int)
        case malformed
    }

    struct Response {
        var status: Int
        var body: Data
    }

    func get(_ path: String) throws -> Data {
        let response = try request("GET", path)
        guard (200..<300).contains(response.status) else { throw Failure.http(response.status) }
        return response.body
    }

    func request(_ method: String, _ path: String) throws -> Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.notRunning }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var time = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.notRunning }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw Failure.notRunning }

        let request = Array("\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\n\r\n".utf8)
        let sent = request.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == request.count else { throw Failure.notRunning }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                // 0 is EOF; -1 is a timeout or reset, after which the response is whatever arrived.
                break
            }
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> Response {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else { throw Failure.malformed }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let statusLine = head.split(separator: "\r\n").first ?? ""
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { throw Failure.malformed }
        return Response(status: status, body: Data(data[end.upperBound...]))
    }
}
