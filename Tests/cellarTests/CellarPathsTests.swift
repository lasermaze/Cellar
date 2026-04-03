import Testing
import Foundation
@testable import cellar

@Suite("CellarPaths — Path Construction")
struct CellarPathsTests {

    @Test("Base path ends with .cellar")
    func basePath() {
        #expect(CellarPaths.base.lastPathComponent == ".cellar")
    }

    @Test("gamesJSON is base/games.json")
    func gamesJsonPath() {
        #expect(CellarPaths.gamesJSON.lastPathComponent == "games.json")
        #expect(CellarPaths.gamesJSON.deletingLastPathComponent() == CellarPaths.base)
    }

    @Test("configFile is base/config.json")
    func configFilePath() {
        #expect(CellarPaths.configFile.lastPathComponent == "config.json")
    }

    @Test("bottleDir appends gameId under bottles directory")
    func bottleDirForGame() {
        let url = CellarPaths.bottleDir(for: "cossacks")
        #expect(url.lastPathComponent == "cossacks")
        #expect(url.deletingLastPathComponent().lastPathComponent == "bottles")
    }

    @Test("logDir appends gameId under logs directory")
    func logDirForGame() {
        let url = CellarPaths.logDir(for: "deus-ex")
        #expect(url.lastPathComponent == "deus-ex")
        #expect(url.deletingLastPathComponent().lastPathComponent == "logs")
    }

    @Test("userRecipeFile appends gameId.json under recipes directory")
    func userRecipeFilePath() {
        let url = CellarPaths.userRecipeFile(for: "rayman-2")
        #expect(url.lastPathComponent == "rayman-2.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "recipes")
    }

    @Test("successdbFile appends gameId.json under successdb directory")
    func successdbFilePath() {
        let url = CellarPaths.successdbFile(for: "civ3")
        #expect(url.lastPathComponent == "civ3.json")
    }
}
