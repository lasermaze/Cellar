import Foundation

// MARK: - Error Category

enum WineErrorCategory {
    case missingDLL
    case crash
    case graphics
    case configuration
    case unknown
}

// MARK: - Suggested Fix

enum DLLPlacementTarget {
    case gameDir    // next to EXE — how cnc-ddraw works
    case system32   // Wine's virtual System32 inside WINEPREFIX
    case syswow64   // Wine's SysWOW64 — 32-bit system DLLs in wow64 bottles

    /// Auto-detect the correct placement target based on bottle layout and DLL properties.
    static func autoDetect(bottleURL: URL, dllBitness: Int, isSystemDLL: Bool) -> DLLPlacementTarget {
        let syswow64Path = bottleURL
            .appendingPathComponent("drive_c/windows/syswow64")
        let isWow64 = FileManager.default.fileExists(atPath: syswow64Path.path)

        if isSystemDLL && isWow64 && dllBitness == 32 {
            return .syswow64
        }
        return .gameDir
    }
}

enum WineFix {
    // Existing (Level 1)
    case installWinetricks(String)         // verb name
    case setEnvVar(String, String)         // key, value
    case setDLLOverride(String, String)    // dll, mode (n,b / native / builtin)

    // New (Level 2+3)
    case placeDLL(String, DLLPlacementTarget)   // dllName (matches KnownDLLRegistry.name), target
    case setRegistry(String, String, String)    // key path, value name, data (e.g. "dword:00000001")

    // Compound (any level)
    case compound([WineFix])                    // ordered list of sub-actions
}

// MARK: - Wine Error

struct WineError {
    let category: WineErrorCategory
    let detail: String
    let suggestedFix: WineFix?
}

// MARK: - WineErrorParser

struct WineErrorParser {
    /// Parse Wine stderr output for known error patterns.
    /// Returns array of diagnosed errors, most specific first.
    static func parse(_ stderr: String) -> [WineError] {
        var errors: [WineError] = []

        // Pattern 1: Missing DLL — err:module:import_dll Library {name}.dll not found
        for match in matchPattern(stderr, #"err:module:import_dll.*Library\s+(\S+)"#) {
            let dll = match
            let fix = dllToWinetricksFix(dll)
            errors.append(WineError(
                category: .missingDLL,
                detail: "\(dll) not found",
                suggestedFix: fix
            ))
        }

        // Pattern 2: Crash — virtual_setup_exception or unhandled exception
        if stderr.contains("virtual_setup_exception") || stderr.contains("unhandled exception") {
            errors.append(WineError(
                category: .crash,
                detail: "Wine process crashed (memory/threading exception)",
                suggestedFix: .setEnvVar("WINE_CPU_TOPOLOGY", "1:0")
            ))
        }

        // Pattern 3: Graphics errors — X11/display/OpenGL
        if stderr.contains("err:x11") || (stderr.contains("err:winediag") && stderr.contains("display")) {
            errors.append(WineError(
                category: .graphics,
                detail: "Graphics/display configuration error",
                suggestedFix: nil
            ))
        }

        // Pattern 4: Configuration errors — registry or prefix issues
        if stderr.contains("err:reg") || stderr.contains("err:setupapi") {
            errors.append(WineError(
                category: .configuration,
                detail: "Wine configuration/registry error",
                suggestedFix: nil
            ))
        }

        // Pattern 5: DirectDraw initialization failure — suggest cnc-ddraw
        if stderr.contains("DirectDraw Init Failed") || stderr.contains("ddraw") && stderr.contains("80004001") {
            errors.append(WineError(
                category: .graphics,
                detail: "DirectDraw initialization failed (likely Wine+Rosetta+MoltenVK translation chain)",
                suggestedFix: .compound([
                    .placeDLL("cnc-ddraw", .gameDir),
                    .setDLLOverride("ddraw", "n,b")
                ])
            ))
        }

        return errors
    }

    /// Map known DLL names to winetricks fix verbs.
    private static func dllToWinetricksFix(_ dll: String) -> WineFix? {
        let dllLower = dll.lowercased()
        if dllLower.contains("mscoree") { return .installWinetricks("dotnet48") }
        if dllLower.contains("d3dx9") { return .installWinetricks("d3dx9") }
        if dllLower.contains("d3dx10") { return .installWinetricks("d3dx10") }
        if dllLower.contains("d3dx11") { return .installWinetricks("d3dx11_43") }
        if dllLower.contains("d3dcompiler") { return .installWinetricks("d3dcompiler_47") }
        if dllLower.contains("vcrun") { return .installWinetricks("vcrun2019") }
        if dllLower.contains("msvcp") || dllLower.contains("msvcr") { return .installWinetricks("vcrun2019") }
        if dllLower.contains("xinput") { return .installWinetricks("xinput") }
        return nil
    }

    /// Extract regex matches from text. Returns captured group 1 for each match.
    private static func matchPattern(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[captureRange])
        }
    }
}
