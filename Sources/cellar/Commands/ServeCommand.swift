import ArgumentParser
@preconcurrency import Vapor

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the web interface"
    )

    @ArgumentParser.Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    mutating func run() throws {
        // Prevent Vapor from hijacking CommandLine.arguments
        let env = Environment(name: "development", arguments: ["vapor"])

        // Bridge async Application.make into synchronous ParsableCommand.run()
        let portValue = port
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var appError: (any Error)?

        Thread {
            Task {
                do {
                    let app = try await Application.make(env)
                    try WebApp.configure(app, port: portValue)
                    try await app.execute()
                    try await app.asyncShutdown()
                } catch {
                    appError = error
                }
                semaphore.signal()
            }
        }.start()

        semaphore.wait()
        if let error = appError {
            throw error
        }
    }
}
