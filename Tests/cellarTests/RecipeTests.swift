import Testing
import Foundation
@testable import cellar

@Suite("Recipe — Encoding, Decoding, Backward Compatibility")
struct RecipeTests {

    @Test("Recipe JSON round-trip preserves all fields")
    func fullRoundTrip() throws {
        let recipe = Recipe(
            id: "test-game",
            name: "Test Game",
            version: "1.0",
            source: "bundled",
            executable: "game.exe",
            wineTested: "9.0",
            environment: ["WINEDLLOVERRIDES": "ddraw=n,b"],
            registry: [RegistryEntry(description: "DLL override", regContent: "HKCU\\Software\\Wine\\DllOverrides")],
            launchArgs: ["-windowed"],
            notes: "Works well",
            setupDeps: ["vcrun2019"],
            installDir: "Program Files/TestGame",
            retryVariants: nil
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(recipe)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        #expect(decoded.id == "test-game")
        #expect(decoded.executable == "game.exe")
        #expect(decoded.environment["WINEDLLOVERRIDES"] == "ddraw=n,b")
        #expect(decoded.setupDeps == ["vcrun2019"])
        #expect(decoded.installDir == "Program Files/TestGame")
    }

    @Test("Recipe decodes with only required fields")
    func minimalDecode() throws {
        let json = """
        {
            "id": "minimal",
            "name": "Minimal Game",
            "version": "1",
            "source": "ai",
            "executable": "run.exe",
            "environment": {},
            "registry": [],
            "launch_args": [],
            "notes": null
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        #expect(decoded.id == "minimal")
        #expect(decoded.wineTested == nil)
        #expect(decoded.setupDeps == nil)
        #expect(decoded.installDir == nil)
        #expect(decoded.retryVariants == nil)
    }

    @Test("Recipe CodingKeys use snake_case")
    func codingKeysFormat() throws {
        let recipe = Recipe(
            id: "test", name: "Test", version: "1", source: "bundled", executable: "test.exe",
            wineTested: "9.0", environment: [:], registry: [], launchArgs: ["-x"],
            notes: nil, setupDeps: ["dotnet48"], installDir: "dir",
            retryVariants: nil
        )
        let data = try JSONEncoder().encode(recipe)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("wine_tested"))
        #expect(json.contains("launch_args"))
        #expect(json.contains("setup_deps"))
        #expect(json.contains("install_dir"))
    }

    @Test("Recipe with empty environment decodes")
    func emptyEnvironment() throws {
        let json = """
        {"id":"e","name":"E","version":"1","source":"ai","executable":"e.exe","environment":{},"registry":[],"launch_args":[]}
        """
        let decoded = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(decoded.environment.isEmpty)
    }

    @Test("Recipe with retry variants decodes")
    func retryVariants() throws {
        let json = """
        {
            "id":"rv","name":"RV","version":"1","source":"ai","executable":"rv.exe",
            "environment":{},"registry":[],"launch_args":[],
            "retry_variants":[{"description":"Try fullscreen","environment":{"WINEDLLOVERRIDES":"ddraw=n"}}]
        }
        """
        let decoded = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(decoded.retryVariants?.count == 1)
        #expect(decoded.retryVariants?.first?.description == "Try fullscreen")
    }
}
