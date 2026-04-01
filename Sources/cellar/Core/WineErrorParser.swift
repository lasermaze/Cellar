import Foundation

// MARK: - Error Category

enum WineErrorCategory {
    case missingDLL
    case crash
    case graphics
    case configuration
    case unknown
    case audio
    case input
    case font
    case memory
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

    // MARK: - Pre-compiled patterns (static to avoid per-parse allocation)

    private static let missingDLLPattern = try! NSRegularExpression(
        pattern: #"err:module:import_dll.*Library\s+(\S+)"#
    )
    private static let dsoundFunctionPattern = try! NSRegularExpression(
        pattern: #"err:dsound:(\w+)"#
    )
    private static let dllChannelPattern = try! NSRegularExpression(
        pattern: #"(?:err|warn|fixme|trace):(\w+):"#
    )

    // MARK: - DLL to causal channel mapping

    private static let dllToChannelMap: [String: String] = [
        "d3d9.dll": "d3d", "d3d9": "d3d",
        "d3d11.dll": "d3d", "d3d11": "d3d",
        "d3dx9": "d3d",
        "ddraw.dll": "ddraw", "ddraw": "ddraw",
        "dsound.dll": "dsound", "dsound": "dsound",
        "dinput.dll": "dinput", "dinput8.dll": "dinput",
    ]

    // MARK: - Harmless macOS warn: allowlist

    private static let harmlessWarnPhrases: [String] = [
        "Could not determine screen saver state",
        "RtlSetHeapInformation",
        "GetSystemFirmwareTable",
        "DrvDocumentEvent",
        "parse_depend_manifests",
        "parse_assembly_identity",
    ]

    // MARK: - Main parse entry point

    /// Parse Wine stderr output and return structured WineDiagnostics.
    static func parse(_ stderr: String) -> WineDiagnostics {
        var diagnostics = WineDiagnostics.empty()
        var subsystemsWithErrors = Set<String>()

        let lines = stderr.components(separatedBy: "\n")

        for line in lines {
            // --- Noise filtering ---
            // Filter known-harmless macOS warn: lines
            if line.contains("warn:") {
                let isHarmless = harmlessWarnPhrases.contains { line.contains($0) }
                if isHarmless {
                    diagnostics.filteredHarmlessWarnCount += 1
                    continue
                }
            }

            // Track fixme: lines for deferred filtering
            if line.contains("fixme:") {
                let channel = extractChannel(from: line)
                if !channel.isEmpty && !subsystemsWithErrors.contains(channel) {
                    diagnostics.filteredFixmeCount += 1
                    continue
                }
            }

            // --- Error detection ---

            // Pattern 1: Missing DLL — err:module:import_dll Library {name}.dll not found
            if line.contains("err:module:import_dll") {
                let range = NSRange(line.startIndex..., in: line)
                if let match = missingDLLPattern.firstMatch(in: line, range: range),
                   match.numberOfRanges > 1,
                   let captureRange = Range(match.range(at: 1), in: line) {
                    let dll = String(line[captureRange])
                    let fix = dllToWinetricksFix(dll)
                    let error = WineError(category: .missingDLL, detail: "\(dll) not found", suggestedFix: fix)
                    diagnostics.addError(error)
                    subsystemsWithErrors.insert("module")
                    // Track channel for causal chain
                    let dllLower = dll.lowercased()
                    for (key, channel) in dllToChannelMap {
                        if dllLower.contains(key.lowercased()) {
                            subsystemsWithErrors.insert(channel)
                        }
                    }
                }
                continue
            }

            // Pattern 2: Crash — unhandled exception (not virtual_setup_exception, handled in memory)
            if line.contains("unhandled exception") && !line.contains("err:seh:") && !line.contains("err:virtual:") {
                let error = WineError(
                    category: .crash,
                    detail: "Wine process crashed (memory/threading exception)",
                    suggestedFix: .setEnvVar("WINE_CPU_TOPOLOGY", "1:0")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("ntdll")
                continue
            }

            // Pattern 3: Graphics errors — X11/display/OpenGL
            if line.contains("err:x11") || (line.contains("err:winediag") && line.contains("display")) {
                let error = WineError(
                    category: .graphics,
                    detail: "Graphics/display configuration error",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("x11")
                continue
            }

            // Pattern 4: Configuration errors — registry or prefix issues
            if line.contains("err:reg") || line.contains("err:setupapi") {
                let error = WineError(
                    category: .configuration,
                    detail: "Wine configuration/registry error",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("reg")
                continue
            }

            // Pattern 5: DirectDraw initialization failure — suggest cnc-ddraw
            if line.contains("DirectDraw Init Failed") ||
               (line.contains("ddraw") && line.contains("80004001")) {
                let error = WineError(
                    category: .graphics,
                    detail: "DirectDraw initialization failed (likely Wine+Rosetta+MoltenVK translation chain)",
                    suggestedFix: .compound([
                        .placeDLL("cnc-ddraw", .gameDir),
                        .setDLLOverride("ddraw", "n,b")
                    ])
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("ddraw")
                continue
            }

            // --- Audio patterns ---

            // Audio 1: err:dsound: — DirectSound error
            if line.contains("err:dsound:") {
                let funcName: String
                let range = NSRange(line.startIndex..., in: line)
                if let match = dsoundFunctionPattern.firstMatch(in: line, range: range),
                   match.numberOfRanges > 1,
                   let captureRange = Range(match.range(at: 1), in: line) {
                    funcName = String(line[captureRange])
                } else {
                    funcName = "unknown"
                }
                // Specialized "no driver" check
                if line.contains("no driver") || line.contains("80004001") {
                    let error = WineError(
                        category: .audio,
                        detail: "DirectSound: no audio driver",
                        suggestedFix: .setDLLOverride("dsound", "n,b")
                    )
                    diagnostics.addError(error)
                } else {
                    let error = WineError(
                        category: .audio,
                        detail: "DirectSound error: \(funcName)",
                        suggestedFix: .setDLLOverride("dsound", "n,b")
                    )
                    diagnostics.addError(error)
                }
                subsystemsWithErrors.insert("dsound")
                continue
            }

            // Audio 2: err:alsa: or err:mmdevapi: — Audio backend error
            if line.contains("err:alsa:") {
                let error = WineError(
                    category: .audio,
                    detail: "Audio backend error (alsa)",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("alsa")
                continue
            }
            if line.contains("err:mmdevapi:") {
                let error = WineError(
                    category: .audio,
                    detail: "Audio backend error (mmdevapi)",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("mmdevapi")
                continue
            }

            // --- Input patterns ---

            // Input 1: err:dinput: — DirectInput error
            if line.contains("err:dinput:") {
                let error = WineError(
                    category: .input,
                    detail: "DirectInput error",
                    suggestedFix: .installWinetricks("dinput8")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("dinput")
                continue
            }

            // Input 2: err:xinput or fixme:xinput + GetCapabilities
            if (line.contains("err:xinput") || line.contains("fixme:xinput")) &&
               line.contains("GetCapabilities") {
                let error = WineError(
                    category: .input,
                    detail: "XInput device not found",
                    suggestedFix: .setEnvVar("SDL_JOYSTICK_DISABLED", "1")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("xinput")
                continue
            }

            // --- Font patterns ---

            // Font 1: FreeType error
            if (line.contains("err:font:") || line.contains("err:gdi:")) &&
               (line.contains("freetype") || line.contains("FreeType") || line.contains("cannot find")) {
                let error = WineError(
                    category: .font,
                    detail: "FreeType font loading error",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("font")
                continue
            }

            // Font 2: GDI/font catch-all
            if line.contains("err:gdi:") || line.contains("err:font:") {
                let error = WineError(
                    category: .font,
                    detail: "GDI/font rendering error",
                    suggestedFix: .installWinetricks("corefonts")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("font")
                subsystemsWithErrors.insert("gdi")
                continue
            }

            // --- Memory patterns ---

            // Memory 1: Access violation / page fault
            if line.contains("err:seh:") && line.contains("Unhandled exception") && line.contains("page fault") {
                let error = WineError(
                    category: .memory,
                    detail: "Access violation (page fault)",
                    suggestedFix: .installWinetricks("vcrun2019")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("seh")
                continue
            }

            // Memory 2: Memory protection error
            if line.contains("err:virtual:virtual_setup_exception") ||
               line.contains("err:virtual:virtual_handle_signal") {
                let error = WineError(
                    category: .memory,
                    detail: "Memory protection error",
                    suggestedFix: .setEnvVar("WINE_CPU_TOPOLOGY", "1:0")
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("virtual")
                continue
            }

            // Memory 3: Deadlock
            if line.contains("err:ntdll:RtlpWaitForCriticalSection") {
                let error = WineError(
                    category: .memory,
                    detail: "Deadlock detected (critical section timeout)",
                    suggestedFix: nil
                )
                diagnostics.addError(error)
                subsystemsWithErrors.insert("ntdll")
                continue
            }

            // --- Success signals ---

            // Graphics: DirectDraw initialized
            if line.contains("trace:ddraw:") && (line.contains("init") || line.contains("initialized")) {
                diagnostics.addSuccess(WineSuccess(subsystem: .graphics, detail: "DirectDraw initialized"))
                continue
            }

            // Graphics: Direct3D adapter initialized
            if line.contains("d3d_adapter_init") ||
               (line.contains("wined3d") && line.contains("GL_RENDERER")) {
                diagnostics.addSuccess(WineSuccess(subsystem: .graphics, detail: "Direct3D adapter initialized"))
                continue
            }

            // Audio: Audio device opened
            if line.contains("trace:dsound:") && (line.contains("open") || line.contains("success")) {
                diagnostics.addSuccess(WineSuccess(subsystem: .audio, detail: "Audio device opened"))
                continue
            }

            // Input: DirectInput device acquired
            if line.contains("trace:dinput:") && (line.contains("acquired") || line.contains("created")) {
                diagnostics.addSuccess(WineSuccess(subsystem: .input, detail: "DirectInput device acquired"))
                continue
            }
        }

        // --- Causal chain detection (post-pass) ---
        let allErrors = diagnostics.allErrors()
        let missingDLLErrors = allErrors.filter { $0.category == .missingDLL }
        let otherErrors = allErrors.filter { $0.category != .missingDLL }

        for dllError in missingDLLErrors {
            let dllLower = dllError.detail.lowercased()
            var channel: String? = nil
            for (key, ch) in dllToChannelMap {
                if dllLower.contains(key.lowercased()) {
                    channel = ch
                    break
                }
            }
            guard let ch = channel else { continue }

            let downstream = otherErrors.filter { $0.detail.lowercased().contains(ch) }
            if !downstream.isEmpty {
                let chain = CausalChain(
                    rootCause: dllError,
                    downstreamEffects: downstream,
                    summary: "missing \(dllError.detail) caused \(downstream.map { $0.detail }.joined(separator: ", "))"
                )
                diagnostics.causalChains.append(chain)
            }
        }

        return diagnostics
    }

    // MARK: - Legacy compatibility

    /// Legacy compatibility wrapper — returns flat [WineError] array.
    /// Prefer parse() for new code.
    static func parseLegacy(_ stderr: String) -> [WineError] {
        return parse(stderr).allErrors()
    }

    // MARK: - Filtered log generation

    /// Returns stderr with noise lines removed but all err:/warn:/trace: lines
    /// from subsystems-with-errors kept. Used by read_log tool integration.
    static func filteredLog(_ stderr: String, diagnostics: WineDiagnostics) -> String {
        // Collect the subsystem names from subsystems that have errors
        var subsystemsWithErrors = Set<String>()
        if !diagnostics.graphics.errors.isEmpty {
            subsystemsWithErrors.insert("ddraw")
            subsystemsWithErrors.insert("d3d")
            subsystemsWithErrors.insert("x11")
            subsystemsWithErrors.insert("winediag")
        }
        if !diagnostics.audio.errors.isEmpty {
            subsystemsWithErrors.insert("dsound")
            subsystemsWithErrors.insert("alsa")
            subsystemsWithErrors.insert("mmdevapi")
        }
        if !diagnostics.input.errors.isEmpty {
            subsystemsWithErrors.insert("dinput")
            subsystemsWithErrors.insert("xinput")
        }
        if !diagnostics.font.errors.isEmpty {
            subsystemsWithErrors.insert("font")
            subsystemsWithErrors.insert("gdi")
        }
        if !diagnostics.memory.errors.isEmpty {
            subsystemsWithErrors.insert("seh")
            subsystemsWithErrors.insert("virtual")
            subsystemsWithErrors.insert("ntdll")
        }
        if !diagnostics.configuration.errors.isEmpty {
            subsystemsWithErrors.insert("reg")
            subsystemsWithErrors.insert("setupapi")
        }
        if !diagnostics.missingDLL.errors.isEmpty {
            subsystemsWithErrors.insert("module")
        }

        let lines = stderr.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            // Always remove known-harmless warn: lines
            if line.contains("warn:") {
                let isHarmless = harmlessWarnPhrases.contains { line.contains($0) }
                if isHarmless { return false }
            }
            // Remove fixme: lines for channels NOT in subsystemsWithErrors
            if line.contains("fixme:") {
                let channel = extractChannel(from: line)
                if !channel.isEmpty && !subsystemsWithErrors.contains(channel) {
                    return false
                }
            }
            return true
        }
        return filtered.joined(separator: "\n")
    }

    // MARK: - Private helpers

    /// Extract the Wine channel name from a log line (e.g. "0009:fixme:dsound:..." -> "dsound")
    private static func extractChannel(from line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        if let match = dllChannelPattern.firstMatch(in: line, range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: line) {
            return String(line[captureRange])
        }
        return ""
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
