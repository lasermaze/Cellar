import Foundation

/// Defines an engine family's fingerprint signals for detection.
struct EngineDefinition: Sendable {
    let name: String                    // "GSC/DMCR"
    let family: String                  // "gsc" (matches SuccessDatabase engine field)
    let filePatterns: [String]          // ["fsgame.ltx", "*.db0"] — exact names or *.ext globs or dir/
    let peImportSignals: [String]       // DLL names that support this engine
    let stringSignatures: [String]      // ["X-Ray Engine", "GSC Game World"]
    let typicalGraphicsApi: String?     // "directdraw"
}

/// Result of engine detection with confidence and matched signals.
struct EngineDetectionResult: Sendable {
    let name: String          // Engine display name
    let family: String        // Lowercase family ID for successdb queries
    let confidence: String    // "high", "medium", or "low"
    let signals: [String]     // e.g. ["file:fsgame.ltx", "string:GSC Game World"]
}

/// Data-driven engine registry with weighted detection scoring.
/// Modeled after KnownDLLRegistry — add new engines by adding array entries.
struct EngineRegistry {

    // MARK: - Engine Definitions

    // Source: SteamDB FileDetectionRuleSets + PCGamingWiki + enginedetect.py
    static let engines: [EngineDefinition] = [
        // 1. GSC/DMCR (X-Ray Engine) — S.T.A.L.K.E.R., Cossacks, American Conquest
        EngineDefinition(
            name: "GSC/DMCR",
            family: "gsc",
            filePatterns: ["fsgame.ltx", "xr_3da.exe", "dmcr.exe", "*.db0", "*.db1"],
            peImportSignals: ["ddraw.dll"],
            stringSignatures: ["X-Ray Engine", "GSC Game World", "DMCR"],
            typicalGraphicsApi: "directdraw"
        ),
        // 2. Unreal Engine 1 — Unreal, Unreal Tournament, Deus Ex, Rune
        EngineDefinition(
            name: "Unreal 1",
            family: "unreal1",
            filePatterns: ["*.u", "*.utx", "*.uax", "*.umx", "*.unr"],
            peImportSignals: ["d3d8.dll", "d3d9.dll"],
            stringSignatures: ["Unreal Engine", "Epic Games"],
            typicalGraphicsApi: "direct3d9"
        ),
        // 3. Build Engine — Duke Nukem 3D, Shadow Warrior, Blood
        EngineDefinition(
            name: "Build",
            family: "build",
            filePatterns: ["*.grp", "*.art", "game.con", "defs.con", "build.exe", "commit.dat"],
            peImportSignals: ["ddraw.dll"],
            stringSignatures: ["Build Engine", "Ken Silverman"],
            typicalGraphicsApi: "directdraw"
        ),
        // 4. id Tech 2/3 — Quake, Quake 2, Quake 3, RTCW, CoD
        EngineDefinition(
            name: "id Tech 2/3",
            family: "idtech",
            filePatterns: ["*.pak", "*.pk3", "baseq2/", "baseq3/", "id1/"],
            peImportSignals: ["opengl32.dll"],
            stringSignatures: ["id Tech", "id Software", "Quake"],
            typicalGraphicsApi: "opengl"
        ),
        // 5. Unity — broad modern engine
        EngineDefinition(
            name: "Unity",
            family: "unity",
            filePatterns: ["unityplayer.dll", "*_data/", "globalgamemanagers", "assembly-csharp.dll", "managed/"],
            peImportSignals: [],
            stringSignatures: ["Unity Engine", "UnityMain"],
            typicalGraphicsApi: "direct3d9"
        ),
        // 6. UE4/5 — Unreal Engine 4 and 5
        EngineDefinition(
            name: "UE4/5",
            family: "unreal4",
            filePatterns: ["*.uasset", "*.uexp", "*.utoc", "*.ucas"],
            peImportSignals: ["d3d11.dll", "d3d9.dll"],
            stringSignatures: ["Unreal Engine 4", "Unreal Engine 5", "Epic Games"],
            typicalGraphicsApi: "direct3d11"
        ),
        // 7. Westwood — Command & Conquer, Red Alert, Tiberian Sun
        EngineDefinition(
            name: "Westwood",
            family: "westwood",
            filePatterns: ["*.mix", "conquer.mix", "redalert.mix", "tibsun.mix",
                           "ra2.mix", "scores.mix", "local.mix"],
            peImportSignals: ["ddraw.dll"],
            stringSignatures: ["Westwood Studios", "Command & Conquer"],
            typicalGraphicsApi: "directdraw"
        ),
        // 8. Blizzard — Diablo, StarCraft, Warcraft
        EngineDefinition(
            name: "Blizzard",
            family: "blizzard",
            filePatterns: ["*.mpq", "diabdat.mpq", "stardat.mpq",
                           "war3.mpq", "d2data.mpq"],
            peImportSignals: ["ddraw.dll", "dsound.dll"],
            stringSignatures: ["Blizzard Entertainment", "Battle.net"],
            typicalGraphicsApi: "directdraw"
        ),
    ]

    // MARK: - Unique file patterns (high weight)

    /// File patterns that are unique to a single engine family (worth +0.5).
    /// Common extension-only patterns like *.grp, *.pak, *.mix, *.mpq are lower weight (+0.3).
    private static let uniquePatterns: Set<String> = [
        "fsgame.ltx", "xr_3da.exe", "dmcr.exe",
        "unityplayer.dll", "globalgamemanagers", "assembly-csharp.dll",
        "game.con", "defs.con", "build.exe", "commit.dat",
        "conquer.mix", "redalert.mix", "tibsun.mix", "ra2.mix",
        "diabdat.mpq", "stardat.mpq", "war3.mpq", "d2data.mpq",
        "baseq2/", "baseq3/", "id1/",
        "managed/",
    ]

    // MARK: - Detection

    /// Detect engine from game files, PE imports, and binary strings.
    /// Returns the highest-scoring engine above the minimum threshold, or nil.
    static func detect(
        gameFiles: [String],
        peImports: [String],
        binaryStrings: [String]
    ) -> EngineDetectionResult? {
        let lowercaseFiles = gameFiles.map { $0.lowercased() }
        let lowercaseImports = peImports.map { $0.lowercased() }

        var bestResult: EngineDetectionResult?
        var bestScore: Double = 0

        for engine in engines {
            var score: Double = 0
            var signals: [String] = []
            var signalTypes: Set<String> = []  // track which types matched

            // Check file patterns (case-insensitive)
            for pattern in engine.filePatterns {
                let lowPattern = pattern.lowercased()

                for (index, file) in lowercaseFiles.enumerated() {
                    let matched: Bool
                    if lowPattern.hasPrefix("*.") {
                        // Extension pattern: match suffix
                        let ext = String(lowPattern.dropFirst(1)) // ".ext"
                        matched = file.hasSuffix(ext)
                    } else if lowPattern.hasSuffix("/") {
                        // Directory pattern: exact match
                        matched = file == lowPattern
                        // Also match "*_data/" style patterns
                        || (lowPattern == "*_data/" && file.hasSuffix("_data/"))
                    } else {
                        // Exact filename match
                        matched = file == lowPattern
                    }

                    if matched {
                        let originalFile = gameFiles[index]
                        let isUnique = uniquePatterns.contains(lowPattern)
                        score += isUnique ? 0.6 : 0.3
                        signals.append("file:\(originalFile)")
                        signalTypes.insert("file")
                        break  // only count each pattern once
                    }
                }
            }

            // Check PE import overlap
            for importSignal in engine.peImportSignals {
                if lowercaseImports.contains(importSignal.lowercased()) {
                    score += 0.25
                    signals.append("import:\(importSignal)")
                    signalTypes.insert("import")
                }
            }

            // Check binary string matches (case-insensitive substring)
            for signature in engine.stringSignatures {
                let lowSig = signature.lowercased()
                for binaryString in binaryStrings {
                    if binaryString.lowercased().contains(lowSig) {
                        score += 0.15
                        signals.append("string:\(signature)")
                        signalTypes.insert("string")
                        break  // only count each signature once
                    }
                }
            }

            // Multiple signal types agreeing: multiply by 1.2
            if signalTypes.count > 1 {
                score *= 1.2
            }

            if score > bestScore {
                bestScore = score
                let confidence: String
                if score >= 0.6 {
                    confidence = "high"
                } else if score >= 0.35 {
                    confidence = "medium"
                } else if score >= 0.15 {
                    confidence = "low"
                } else {
                    continue  // below threshold
                }
                bestResult = EngineDetectionResult(
                    name: engine.name,
                    family: engine.family,
                    confidence: confidence,
                    signals: signals
                )
            }
        }

        // Final threshold check (bestScore could be > 0 but < 0.15)
        if bestScore < 0.15 {
            return nil
        }

        return bestResult
    }

    // MARK: - Graphics API Detection

    /// Detect graphics API from PE imports. Prefers higher DX version.
    /// Returns nil if no graphics API DLL is found.
    static func detectGraphicsApi(peImports: [String]) -> String? {
        let lower = peImports.map { $0.lowercased() }

        // Priority order: d3d11 > d3d9 > d3d8 > ddraw > opengl
        if lower.contains("d3d11.dll") { return "direct3d11" }
        if lower.contains("d3d9.dll") { return "direct3d9" }
        if lower.contains("d3d8.dll") { return "direct3d8" }
        if lower.contains("ddraw.dll") { return "directdraw" }
        if lower.contains("opengl32.dll") { return "opengl" }

        return nil
    }
}
