import ArgumentParser
@preconcurrency import Vapor
import Foundation

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the web interface"
    )

    @ArgumentParser.Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    mutating func run() throws {
        let portValue = port
        let state = ServerState()
        let done = DispatchSemaphore(value: 0)

        let thread = Thread {
            Task {
                do {
                    let env = Environment(name: "development", arguments: ["vapor"])
                    let app = try await Application.make(env)
                    try WebApp.configure(app, port: portValue)
                    print("Cellar web server running on http://127.0.0.1:\(portValue)")
                    try await app.execute()
                    try await app.asyncShutdown()
                } catch {
                    state.setError(error)
                }
                done.signal()
            }
            RunLoop.current.run()
        }
        thread.start()

        done.wait()
        if let error = state.error {
            print("Error: \(error)")
            Foundation.exit(1)
        }
    }
}

private final class ServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: (any Error)?

    var error: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return _error
    }

    func setError(_ error: any Error) {
        lock.lock()
        _error = error
        lock.unlock()
    }
}
