import ArgumentParser
import Foundation

struct InstallAppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-app",
        abstract: "Install Cellar.app to ~/Applications for double-click launch"
    )

    mutating func run() throws {
        // 1. Locate the .app bundle
        // The binary is typically at /opt/homebrew/Cellar/cellar/<version>/bin/cellar
        // (or symlinked via /opt/homebrew/bin/cellar -> ../Cellar/cellar/<version>/bin/cellar)
        // The .app lives at /opt/homebrew/Cellar/cellar/<version>/libexec/Cellar.app
        // Strategy: resolve symlinks on the binary path, then go up one level (bin -> version root)
        // and into libexec/Cellar.app.
        let fm = FileManager.default

        let rawBinaryPath = CommandLine.arguments[0]
        let resolvedBinaryPath = (rawBinaryPath as NSString).resolvingSymlinksInPath
        let binaryURL = URL(fileURLWithPath: resolvedBinaryPath)
        // Go: .../bin/cellar -> .../bin -> ... -> ../libexec/Cellar.app
        let binDirURL = binaryURL.deletingLastPathComponent()            // .../bin
        let versionRootURL = binDirURL.deletingLastPathComponent()       // .../cellar/<version>
        let appURL = versionRootURL.appendingPathComponent("libexec/Cellar.app")

        guard fm.fileExists(atPath: appURL.path) else {
            print("Error: Cellar.app not found at \(appURL.path)")
            print("This command works after installing via Homebrew (brew install cellar).")
            print("If you built from source, the .app is created by the Homebrew formula's post_install step.")
            throw ExitCode.failure
        }

        // 2. Determine destination — ~/Applications/Cellar.app
        let homeURL = fm.homeDirectoryForCurrentUser
        let applicationsURL = homeURL.appendingPathComponent("Applications")
        let destinationURL = applicationsURL.appendingPathComponent("Cellar.app")

        // Create ~/Applications if it doesn't exist
        if !fm.fileExists(atPath: applicationsURL.path) {
            do {
                try fm.createDirectory(at: applicationsURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error: Could not create ~/Applications: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // 3. Copy the .app — remove existing copy first to allow updates
        if fm.fileExists(atPath: destinationURL.path) {
            do {
                try fm.removeItem(at: destinationURL)
            } catch {
                print("Error: Could not remove existing Cellar.app at \(destinationURL.path): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        do {
            try fm.copyItem(at: appURL, to: destinationURL)
        } catch {
            print("Error: Could not copy Cellar.app to ~/Applications: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        print("Cellar.app installed to ~/Applications/Cellar.app")
        print("Double-click it to start the Cellar web UI.")
    }
}
