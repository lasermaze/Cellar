import Foundation

struct BottleManager {
    let wineBinary: URL

    /// Create a new bottle for a game. Returns the bottle path.
    func createBottle(gameId: String) throws -> URL {
        let bottlePath = CellarPaths.bottleDir(for: gameId)

        // Create directory with intermediate directories (Pitfall 7)
        try FileManager.default.createDirectory(
            at: bottlePath,
            withIntermediateDirectories: true
        )

        let wineProcess = WineProcess(wineBinary: wineBinary, winePrefix: bottlePath)
        try wineProcess.initPrefix()

        print("Bottle created at \(bottlePath.path)")
        return bottlePath
    }

    /// Check if a bottle exists for a game.
    func bottleExists(gameId: String) -> Bool {
        let bottlePath = CellarPaths.bottleDir(for: gameId)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: bottlePath.path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}
