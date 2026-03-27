import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check dependencies and system status"
    )

    mutating func run() {
        print("Cellar - Wine game launcher for macOS\n")

        // Step 1: detect current dependency state
        var status = DependencyChecker().checkAll()

        printDependencyStatus(status)

        // Step 2: guided install if deps are missing
        if !status.allRequired {
            let installer = GuidedInstaller()

            // Install Homebrew if missing
            if status.homebrew == nil {
                print("\nHomebrew is required to install and manage Wine.")
                print("Install Homebrew now? [y/n] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer == "y" {
                    installer.installHomebrew()
                }
                // Re-check after attempted install
                status = DependencyChecker().checkAll()
            }

            // Install Wine if Homebrew is now present but Wine is missing
            if status.homebrew != nil && status.wine == nil {
                print("\nWine is required to run games.")
                print("Install Wine now? [y/n] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer == "y" {
                    installer.installWine()
                }
                // Re-check after attempted install
                status = DependencyChecker().checkAll()
            }

            // Print updated status after any installs
            if !status.allRequired {
                print("\nUpdated status:")
                printDependencyStatus(status)
            }
        }

        // Step 3: if all deps present, show next-step guidance
        if status.allRequired {
            print("\nAll dependencies found. Run `cellar add /path/to/setup.exe` to get started.")
        }
    }

    // MARK: - Private helpers

    private func printDependencyStatus(_ status: DependencyStatus) {
        print("Dependencies:")
        if let brew = status.homebrew {
            print("  Homebrew: \(brew.path)")
        } else {
            print("  Homebrew: not found")
        }
        if let wine = status.wine {
            print("  Wine:     \(wine.path)")
        } else {
            print("  Wine:     not found")
        }
        if status.gptk {
            print("  GPTK:    detected")
        } else {
            print("  GPTK:    not detected (optional)")
        }
    }
}
