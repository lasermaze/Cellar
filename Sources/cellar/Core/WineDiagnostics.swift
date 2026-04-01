import Foundation

// MARK: - WineSuccess

struct WineSuccess {
    let subsystem: WineErrorCategory
    let detail: String
}

// MARK: - SubsystemDiagnostic

struct SubsystemDiagnostic {
    var errors: [WineError] = []
    var successes: [WineSuccess] = []
}

// MARK: - CausalChain

struct CausalChain {
    let rootCause: WineError
    let downstreamEffects: [WineError]
    let summary: String
}

// MARK: - WineDiagnostics

struct WineDiagnostics {
    var graphics: SubsystemDiagnostic = SubsystemDiagnostic()
    var audio: SubsystemDiagnostic = SubsystemDiagnostic()
    var input: SubsystemDiagnostic = SubsystemDiagnostic()
    var font: SubsystemDiagnostic = SubsystemDiagnostic()
    var memory: SubsystemDiagnostic = SubsystemDiagnostic()
    var configuration: SubsystemDiagnostic = SubsystemDiagnostic()
    var missingDLL: SubsystemDiagnostic = SubsystemDiagnostic()
    var crash: SubsystemDiagnostic = SubsystemDiagnostic()
    var unknown: SubsystemDiagnostic = SubsystemDiagnostic()

    var causalChains: [CausalChain] = []
    var filteredFixmeCount: Int = 0
    var filteredHarmlessWarnCount: Int = 0

    // MARK: - Summary

    var summaryLine: String {
        let totalErrors = allErrors().count
        let totalSuccesses = allSuccesses().count

        var errorSubsystems: [String] = []
        if !graphics.errors.isEmpty { errorSubsystems.append("graphics") }
        if !audio.errors.isEmpty { errorSubsystems.append("audio") }
        if !input.errors.isEmpty { errorSubsystems.append("input") }
        if !font.errors.isEmpty { errorSubsystems.append("font") }
        if !memory.errors.isEmpty { errorSubsystems.append("memory") }
        if !configuration.errors.isEmpty { errorSubsystems.append("configuration") }
        if !missingDLL.errors.isEmpty { errorSubsystems.append("missingDLL") }
        if !crash.errors.isEmpty { errorSubsystems.append("crash") }
        if !unknown.errors.isEmpty { errorSubsystems.append("unknown") }

        var successSubsystems: [String] = []
        if !graphics.successes.isEmpty { successSubsystems.append("graphics") }
        if !audio.successes.isEmpty { successSubsystems.append("audio") }
        if !input.successes.isEmpty { successSubsystems.append("input") }
        if !font.successes.isEmpty { successSubsystems.append("font") }
        if !memory.successes.isEmpty { successSubsystems.append("memory") }

        var parts: [String] = []

        if totalErrors == 0 {
            parts.append("0 errors")
        } else {
            parts.append("\(totalErrors) error\(totalErrors == 1 ? "" : "s") (\(errorSubsystems.joined(separator: ", ")))")
        }

        if totalSuccesses == 0 {
            parts.append("0 successes")
        } else {
            parts.append("\(totalSuccesses) success\(totalSuccesses == 1 ? "" : "es") (\(successSubsystems.joined(separator: ", ")))")
        }

        parts.append("\(filteredFixmeCount) fixme line\(filteredFixmeCount == 1 ? "" : "s") filtered")

        return parts.joined(separator: ", ")
    }

    // MARK: - Factory

    static func empty() -> WineDiagnostics {
        return WineDiagnostics()
    }

    // MARK: - Helpers

    func allErrors() -> [WineError] {
        return graphics.errors + audio.errors + input.errors + font.errors +
               memory.errors + configuration.errors + missingDLL.errors +
               crash.errors + unknown.errors
    }

    func allSuccesses() -> [WineSuccess] {
        return graphics.successes + audio.successes + input.successes +
               font.successes + memory.successes
    }

    mutating func addError(_ error: WineError) {
        switch error.category {
        case .graphics:
            graphics.errors.append(error)
        case .audio:
            audio.errors.append(error)
        case .input:
            input.errors.append(error)
        case .font:
            font.errors.append(error)
        case .memory:
            memory.errors.append(error)
        case .configuration:
            configuration.errors.append(error)
        case .missingDLL:
            missingDLL.errors.append(error)
        case .crash:
            crash.errors.append(error)
        case .unknown:
            unknown.errors.append(error)
        }
    }

    mutating func addSuccess(_ success: WineSuccess) {
        switch success.subsystem {
        case .graphics:
            graphics.successes.append(success)
        case .audio:
            audio.successes.append(success)
        case .input:
            input.successes.append(success)
        case .font:
            font.successes.append(success)
        case .memory:
            memory.successes.append(success)
        case .configuration:
            configuration.successes.append(success)
        case .missingDLL:
            missingDLL.successes.append(success)
        case .crash:
            crash.successes.append(success)
        case .unknown:
            unknown.successes.append(success)
        }
    }

    // MARK: - Dictionary Serialization

    func asDictionary() -> [String: Any] {
        var result: [String: Any] = [:]

        result["summary"] = summaryLine

        let subsystems: [(String, SubsystemDiagnostic)] = [
            ("graphics", graphics),
            ("audio", audio),
            ("input", input),
            ("font", font),
            ("memory", memory),
            ("configuration", configuration),
            ("missing_dll", missingDLL),
            ("crash", crash),
            ("unknown", unknown)
        ]

        for (name, diag) in subsystems {
            if !diag.errors.isEmpty || !diag.successes.isEmpty {
                var subsystemDict: [String: Any] = [:]

                if !diag.errors.isEmpty {
                    subsystemDict["errors"] = diag.errors.map { error -> [String: Any] in
                        var entry: [String: Any] = [
                            "category": categoryName(error.category),
                            "detail": error.detail
                        ]
                        if let fix = error.suggestedFix {
                            entry["suggested_fix"] = describeWineFix(fix)
                        }
                        return entry
                    }
                }

                if !diag.successes.isEmpty {
                    subsystemDict["successes"] = diag.successes.map { s -> [String: Any] in
                        return ["detail": s.detail]
                    }
                }

                result[name] = subsystemDict
            }
        }

        if !causalChains.isEmpty {
            result["causal_chains"] = causalChains.map { chain -> [String: Any] in
                return [
                    "root_cause": chain.rootCause.detail,
                    "downstream_effects": chain.downstreamEffects.map { $0.detail },
                    "summary": chain.summary
                ]
            }
        }

        result["filtered_fixme_count"] = filteredFixmeCount
        result["filtered_harmless_warn_count"] = filteredHarmlessWarnCount

        return result
    }

    // MARK: - Private Helpers

    private func categoryName(_ category: WineErrorCategory) -> String {
        switch category {
        case .missingDLL: return "missingDLL"
        case .crash: return "crash"
        case .graphics: return "graphics"
        case .configuration: return "configuration"
        case .unknown: return "unknown"
        case .audio: return "audio"
        case .input: return "input"
        case .font: return "font"
        case .memory: return "memory"
        }
    }

    private func describeWineFix(_ fix: WineFix) -> String {
        switch fix {
        case .installWinetricks(let verb):
            return "install_winetricks(\(verb))"
        case .setEnvVar(let key, let value):
            return "set_env(\(key)=\(value))"
        case .setDLLOverride(let dll, let mode):
            return "set_dll_override(\(dll), \(mode))"
        case .placeDLL(let dllName, let target):
            let targetStr: String
            switch target {
            case .gameDir: targetStr = "game_dir"
            case .system32: targetStr = "system32"
            case .syswow64: targetStr = "syswow64"
            }
            return "place_dll(\(dllName), \(targetStr))"
        case .setRegistry(let key, let name, let data):
            return "set_registry(\(key), \(name), \(data))"
        case .compound(let fixes):
            return fixes.map { describeWineFix($0) }.joined(separator: " + ")
        }
    }
}
