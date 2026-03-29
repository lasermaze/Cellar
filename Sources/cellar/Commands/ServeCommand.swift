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
        // Prevent Vapor from hijacking CommandLine.arguments
        let portValue = port

        // Use a dedicated run loop thread for the async Vapor server
        nonisolated(unsafe) var serverError: (any Error)?
        let done = DispatchSemaphore(value: 0)

        let thread = Thread {
            let eventLoop = DispatchQueue(label: "cellar.serve")
            eventLoop.async {
                Task {
                    do {
                        let env = Environment(name: "development", arguments: ["vapor"])
                        let app = try await Application.make(env)
                        try WebApp.configure(app, port: portValue)
                        try await app.execute()
                        try await app.asyncShutdown()
                    } catch {
                        serverError = error
                    }
                    done.signal()
                }
            }
            RunLoop.current.run()
        }
        thread.start()

        done.wait()
        if let error = serverError {
            throw error
        }
    }
}
