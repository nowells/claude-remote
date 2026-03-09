import Foundation

/// Listens on a Unix domain socket at `Config.socketPath`.
/// The Python hook script connects, sends a JSON-encoded ApprovalRequest,
/// waits for a JSON-encoded Response, then disconnects.
///
/// Each connection is handled on a private concurrent queue; the handler
/// closure is `async` so it can await a decision without blocking the queue.
final class UnixSocketServer {

    // MARK: - Types

    struct Response: Codable {
        let id: String
        let decision: String  // "allow" or "deny"
    }

    private struct IncomingPayload: Codable {
        let id: String?
        let tool_name: String
        let tool_input: String  // raw JSON string
    }

    typealias Handler = (ApprovalRequest) async -> Response

    // MARK: - State

    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "unix-socket", attributes: .concurrent)
    private var onRequest: Handler?

    // MARK: - Start

    func start(handler: @escaping Handler) throws {
        self.onRequest = handler

        let path = Config.socketPath

        // Clean up any leftover socket file
        unlink(path)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw NSError(domain: "UnixSocket", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "socket() failed: \(errno)"])
        }

        // Bind — copy path into sun_path, then bind using a pointer to the whole struct
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: CChar.self, capacity: sunPathSize) { cStr in
                _ = path.withCString { strncpy(cStr, $0, sunPathSize - 1) }
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: "UnixSocket", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(errno)"])
        }

        guard listen(serverFD, 16) == 0 else {
            throw NSError(domain: "UnixSocket", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "listen() failed: \(errno)"])
        }

        // Set permissions so the hook script (same user) can connect
        chmod(path, 0o700)

        queue.async { [weak self] in self?.acceptLoop() }
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while serverFD >= 0 {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            queue.async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Per-connection Handler

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Read until EOF or newline
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk.prefix(n))
            if chunk.prefix(n).contains(0x0a) { break }  // newline = end of message
        }

        // Parse request
        let payload: IncomingPayload
        do {
            payload = try JSONDecoder().decode(IncomingPayload.self, from: buffer)
        } catch {
            sendError(fd: fd, message: "JSON parse error: \(error)")
            return
        }

        let request = ApprovalRequest(
            id: payload.id ?? UUID().uuidString,
            toolName: payload.tool_name,
            toolInput: payload.tool_input
        )

        // Bridge async handler → sync blocking wait (acceptable: each client has its own thread)
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?

        Task {
            if let handler = self.onRequest {
                let response = await handler(request)
                responseData = try? JSONEncoder().encode(response)
            }
            semaphore.signal()
        }

        // Wait up to remoteResponseTimeoutSeconds + 10s buffer
        let deadline = DispatchTime.now() + Config.remoteResponseTimeoutSeconds + 10
        let waitResult = semaphore.wait(timeout: deadline)

        if waitResult == .timedOut || responseData == nil {
            sendError(fd: fd, message: "timeout")
        } else if var data = responseData {
            if data.last != 0x0a { data.append(0x0a) }
            data.withUnsafeBytes { ptr in
                _ = write(fd, ptr.baseAddress, ptr.count)
            }
        }
    }

    private func sendError(fd: Int32, message: String) {
        let payload = #"{"error":"\#(message)"}"# + "\n"
        _ = payload.withCString { write(fd, $0, strlen($0)) }
    }

    // MARK: - Teardown

    func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(Config.socketPath)
    }

    deinit { stop() }
}
