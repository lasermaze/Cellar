import ArgumentParser
import Foundation

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync local success records to collective memory"
    )

    mutating func run() {
        let config = CellarConfig.load()

        guard config.contributeMemory == true else {
            print("Collective memory contribution is not enabled.")
            print("Enable it in Settings or run `cellar launch` and opt in when prompted.")
            return
        }

        let records = SuccessDatabase.loadAll()
        guard !records.isEmpty else {
            print("No local success records to sync.")
            return
        }

        let status = DependencyChecker().checkAll()
        guard let wineURL = status.wine else {
            print("Wine is not installed. Cannot detect environment for sync.")
            return
        }

        print("Syncing \(records.count) success record(s) to collective memory...")

        let result = CollectiveMemoryWriteService.syncAll(wineURL: wineURL)

        if result.synced > 0 {
            print("Synced: \(result.synced)")
        }
        if result.failed > 0 {
            print("Failed: \(result.failed) (check ~/.cellar/logs/memory-push.log)")
        }
        if result.synced == 0 && result.failed == 0 {
            print("Nothing to sync.")
        }
    }
}
