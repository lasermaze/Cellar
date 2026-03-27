# Phase 3: Repair Loop - Research

**Researched:** 2026-03-27
**Domain:** Swift CLI — AI-driven retry orchestration, stale-output hang detection, repair report persistence
**Confidence:** HIGH (all findings from direct codebase inspection + project decision log)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Variant Generation Strategy**
- AI generates **full recipe variants** (complete environment config), not just single-fix tweaks
- AI variants only kick in **after bundled retryVariants are exhausted** — bundled variants are fast, free, and tried first
- Existing single-fix logic (WineErrorParser + AI diagnosis) stays as-is within each attempt
- AI receives **cumulative history**: game name, current recipe, error logs from ALL prior attempts, and what configs were already tried — avoids repeating failed approaches
- AI variant scope limited to **environment variables and DLL overrides only** — no registry edits during retry loop (registry changes persist in the bottle and leave residue on failure)

**Retry Budget & Stopping**
- **3 AI-generated variants** after bundled variants are exhausted — separate budget from the existing retry loop
- No wall-clock time limit on the overall loop — attempt count is the natural stopping point
- **Stale-output hang detection** on game launches: if Wine produces no stdout/stderr for 5 minutes, assume hung and kill the process (reuse WinetricksRunner's OutputMonitor/NSLock pattern)
- Hung launch treated as a failed attempt — move to next variant
- Existing maxTotalAttempts cap may need adjustment to accommodate the new AI variant budget

**Learning from Success**
- When user confirms "reached menu" after an AI variant, **save the working config as the user recipe** at ~/.cellar/recipes/
- **Show + auto-save**: display the winning config diff ("Saving: WINEDLLOVERRIDES=d3d9=native, MESA_GL_VERSION=3.0") then save automatically — no approval prompt (consistent with bundled recipe auto-apply behavior)
- **AI overrides win**: saved user recipe includes AI variant changes on top of bundled recipe base config; user recipe takes precedence over bundled recipe on future launches
- Bundled recipe still exists as fallback if user resets their game

**Failure Reporting**
- **Structured summary** after exhausting all variants: list each attempt with variant description, config changes, error category, and AI reasoning (1 sentence per attempt)
- End with best diagnosis + AI-generated manual suggestions (1-2 actionable next steps like "try winecfg and change X" or "this game may need a specific Wine version")
- **Inline AI reasoning during retry**: before each AI variant, show "AI analysis: [reasoning]. Trying: [key config changes]..." — user sees the thought process in real-time (consistent with Phase 2's inline diagnosis)
- **Save repair report** to ~/.cellar/logs/{game}/repair-report-{timestamp}.txt with all attempts, AI reasoning, configs tried, and suggestions — useful for community sharing (Phase 5)
- After failure, **print path only** to report and logs — no interactive prompts after the loop

### Claude's Discretion
- Exact AI prompt engineering for variant generation
- How cumulative history is structured in the prompt (token budget management)
- Adjustment to maxTotalAttempts constant
- Repair report file format details
- How OutputMonitor integrates into WineProcess (vs. being a wrapper)
- Whether to add a new AIService method or extend the existing diagnose() call

### Deferred Ideas (OUT OF SCOPE)
- Confidence scoring on variants (track which approaches work reliably across launches) — RECIPE-05, v2
- Automatic bottle reset between retry attempts (clean slate for each variant) — would need Phase 4's reset capability
- Community-sourced variant suggestions (check if others solved this game) — Phase 5
- Permutation-based variants without AI (combinatorial env var exploration) — could complement AI approach
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RECIPE-04 | Cellar can try multiple recipe variants when a launch fails | Existing retry loop in LaunchCommand (lines 86–231) extended with a second stage: after bundled retryVariants exhausted, call new AIService.generateVariants() with cumulative history, append to envConfigs, continue loop |
</phase_requirements>

---

## Summary

Phase 3 extends the already-functional retry loop in `LaunchCommand.swift` with two additions: (1) AI-powered full-variant generation after bundled retryVariants are exhausted, and (2) hang detection for game launches (the same gap that Phase 1.1 closed for winetricks, now applied to `WineProcess.run()`). The retry loop structure already supports `envConfigs` injection — AI variants just append more entries. The most structurally significant work is adding stale-output detection inside `WineProcess.run()` (currently it calls `process.waitUntilExit()` with no timeout), and adding the repair report persistence path to `CellarPaths`.

The AI variant generation follows the same pattern as the existing `AIService.generateRecipe()` and `AIService.diagnose()` methods: a new static method `AIService.generateVariants()` takes cumulative context and returns `AIResult<[RetryVariant]>`. The existing `RetryVariant` struct (description + environment dictionary) perfectly models what AI needs to return. No new model types are needed for the core data path.

The failure reporting and repair report write are pure I/O tasks — no new dependencies. The report is written to `~/.cellar/logs/{gameId}/repair-report-{timestamp}.txt` using the existing `CellarPaths.logDir(for:)` helper. Recipe save-on-success reuses `RecipeEngine.saveUserRecipe()` which already writes to `~/.cellar/recipes/`.

**Primary recommendation:** Add `AIService.generateVariants()` as a new static method mirroring `diagnose()`; add OutputMonitor to WineProcess; add `repairReportFile(for:timestamp:)` to CellarPaths; extend LaunchCommand's post-bundled-variant block to call generateVariants and continue the loop; write repair report on exhaustion; save recipe on success.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift 6 / ArgumentParser | 1.7.0+ | CLI command structure | Already in Package.swift |
| Foundation (URLSession.shared) | macOS 14 | AI API HTTP calls | Established pattern, avoids semaphore deadlock on background delegate queue |
| NSLock + @unchecked Sendable | built-in | Thread-safe state in readabilityHandler closures | Established in StderrCapture, OutputMonitor — Swift 6 Sendable compliance |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DispatchSemaphore | built-in | Bridge async URLSession to sync call | Same pattern as existing AIService.callAPI() |
| Process + Pipe | built-in | Wine process execution with I/O capture | Same pattern as WineProcess.run() and WinetricksRunner.install() |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Adding OutputMonitor inside WineProcess | Wrapping WineProcess.run() at call site | Inside is cleaner — run() already owns the process lifecycle; call-site wrapping would duplicate the polling loop everywhere it's called |
| New AIResult struct for variants | Reuse AIResult<[RetryVariant]> | No new type needed — AIResult is already generic |

**Installation:** No new packages. All dependencies are already present.

---

## Architecture Patterns

### Recommended File Changes
```
Sources/cellar/
├── Commands/LaunchCommand.swift      # EXTEND: AI variant stage + hang detection + repair report write + recipe save
├── Core/AIService.swift              # ADD: generateVariants() static method
├── Core/WineProcess.swift            # ADD: OutputMonitor + stale-output detection in run()
├── Persistence/CellarPaths.swift     # ADD: repairReportFile(for:timestamp:) helper
└── Models/AIModels.swift             # ADD: AIVariantResult struct (AI reasoning + variants)
```

No new files needed. All additions are to existing files.

### Pattern 1: AI Variant Generation (new AIService method)

**What:** A new static method `AIService.generateVariants()` takes cumulative context (game name, current env, prior attempt history) and returns `AIResult<AIVariantResult>` where `AIVariantResult` carries both a list of `RetryVariant` values and an explanation string for inline display.

**When to use:** Called in LaunchCommand after `configIndex >= envConfigs.count` (bundled variants exhausted) and the AI variant budget isn't spent yet.

**Example structure:**
```swift
struct AIVariantResult {
    let variants: [RetryVariant]
    let reasoning: String  // shown inline before first variant attempt
}

static func generateVariants(
    gameId: String,
    gameName: String,
    currentEnvironment: [String: String],
    attemptHistory: [(description: String, envDiff: [String: String], errorSummary: String)]
) -> AIResult<AIVariantResult>
```

The system prompt constrains output to env vars and DLL overrides only (no winetricks, no registry). Returns a JSON array of variant objects with description + environment. Token budget managed by capping attemptHistory to last 3 entries' stderr summaries (not full logs).

**Confidence:** HIGH — mirrors existing generateRecipe() exactly; same provider routing, same retry wrapper, same JSON extraction.

### Pattern 2: OutputMonitor in WineProcess.run()

**What:** Lift the `OutputMonitor` private class from `WinetricksRunner` into `WineProcess` (or an identical copy). In `WineProcess.run()`, replace `process.waitUntilExit()` with the same polling loop used in WinetricksRunner. The `timedOut` field on `WineResult` is already defined (`let timedOut: Bool`) but is always `false` today — this change will set it correctly.

**When to use:** Every game launch (always-on). 5-minute stale-output timeout per CONTEXT.md decision.

**Existing pattern in WinetricksRunner.install() (lines 84–101):**
```swift
// Stale-output detection loop — poll every 2 seconds instead of waitUntilExit()
let staleTimeout: TimeInterval = 300  // 5 minutes
var didTimeout = false
while process.isRunning {
    Thread.sleep(forTimeInterval: 2.0)
    let timeSinceOutput = Date().timeIntervalSince(outputMonitor.lastOutputTime)
    if timeSinceOutput > staleTimeout {
        process.terminate()
        try? wineProcess.killWineserver()
        Thread.sleep(forTimeInterval: 1.0)
        didTimeout = true
        break
    }
}
```
WineProcess.run() already pipes stdout/stderr through readabilityHandler — the only change is replacing `waitUntilExit()` with this polling loop and calling `outputMonitor.touch()` from each handler. Return `WineResult(..., timedOut: didTimeout)`.

**Confidence:** HIGH — exact copy of proven WinetricksRunner pattern, same NSLock/@unchecked Sendable constraints.

### Pattern 3: LaunchCommand Retry Loop Extension

**What:** After the existing `while configIndex < envConfigs.count` loop exits because `configIndex >= envConfigs.count` (not because a variant succeeded or maxTotalAttempts was hit), call `AIService.generateVariants()` once with the cumulative history and append up to 3 new variants to `envConfigs`. The outer loop naturally continues.

**Structural approach:** Track an `aiVariantsGenerated: Bool` flag. After the while-loop exits due to `configIndex >= envConfigs.count` but before declaring failure:

```swift
// Phase 3 extension: AI variant generation stage
if !aiVariantsGenerated && totalAttempts < maxTotalAttempts {
    aiVariantsGenerated = true
    let history = buildAttemptHistory(allAttempts)
    switch AIService.generateVariants(gameId: game, gameName: ..., currentEnvironment: ..., attemptHistory: history) {
    case .success(let result):
        print("\nAI analysis: \(result.reasoning)")
        for variant in result.variants {
            envConfigs.append((description: variant.description, environment: variant.environment))
        }
        // Continue the outer while loop
    case .unavailable, .failed:
        break
    }
}
```

Then re-evaluate the `while` condition. If variants were appended and budget remains, the loop continues naturally.

**maxTotalAttempts adjustment:** Current value is 5. With 3 AI variants appended, the budget needs to accommodate bundled variants (0–N) + dep installs + AI variants (up to 3). Recommended new value: **10** (generous enough to not block the AI stage, tight enough to prevent runaway loops).

**Confidence:** HIGH — the existing loop structure already supports arbitrary envConfigs injection; this is a direct extension.

### Pattern 4: Recipe Save on Success

**What:** After the validation prompt returns `reachedMenu == true`, check if the winning `config` came from an AI-generated variant (i.e., `configIndex >= originalEnvConfigsCount`). If so, build an updated recipe merging base recipe environment with the winning variant's environment, and call `RecipeEngine.saveUserRecipe()`.

**Display the diff before saving:**
```swift
print("Saving winning configuration:")
for (key, value) in winningEnvDiff {
    print("  \(key)=\(value)")
}
try RecipeEngine.saveUserRecipe(updatedRecipe)
```

Track `originalEnvConfigsCount` before the AI stage appends to `envConfigs`. Track `winningConfigIndex` at loop break to detect AI vs. bundled origin.

**Confidence:** HIGH — `RecipeEngine.saveUserRecipe()` already exists and handles the write; Recipe is `Codable` and can be reconstructed from base recipe + env merge.

### Pattern 5: Repair Report Write

**What:** On loop exhaustion (all variants tried, game still failed), write a structured text report to `CellarPaths.repairReportFile(for: game, timestamp: Date())`.

**New CellarPaths helper:**
```swift
static func repairReportFile(for gameId: String, timestamp: Date) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    let ts = formatter.string(from: timestamp)
    return logDir(for: gameId).appendingPathComponent("repair-report-\(ts).txt")
}
```

Report content: plain text, one section per attempt (description, env changes, error category, AI reasoning). Final section: best diagnosis + manual suggestions from a final AI call (or fallback to last parsed error if AI unavailable).

**Confidence:** HIGH — same pattern as logFile(for:timestamp:); directory already created by existing log-setup code.

### Anti-Patterns to Avoid

- **Don't pass full stderr logs in AI history prompt:** Token budget explodes with 3+ attempts × multi-KB logs. Cap each attempt's error summary to 500 characters of parsed error details or stderr tail — enough context for AI without blowing the context window.
- **Don't use process.waitUntilExit() in the new WineProcess timeout path:** Mixing waitUntilExit() with the polling loop will deadlock (process.terminate() after waitUntilExit() is a no-op if already blocked).
- **Don't advance configIndex inside the AI variant append block:** Appending to envConfigs while the while-loop is checking `configIndex < envConfigs.count` is safe because the append happens *outside* the while body after the loop exits.
- **Don't save recipe if the user answers "no" to reachedMenu:** Save is conditional on `reachedMenu == true`. The existing validation prompt already returns `Bool?` (nil = no answer) — only save on `true`.
- **Don't apply registry edits from AI variants:** CONTEXT.md explicitly excludes registry changes. AI prompt must state this constraint.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stale-output polling loop | Custom timer/sleep variant | Direct copy of WinetricksRunner's OutputMonitor pattern | Identical requirements; proven in production; NSLock/@unchecked Sendable already solves Swift 6 compliance |
| Recipe persistence | Custom JSON write | `RecipeEngine.saveUserRecipe()` | Already handles directory creation, atomic write, pretty-print encoding |
| AI API retry | Custom retry loop | `AIService.withRetry()` (private, but pattern is identical) | The retry logic (3 attempts, 1s delay) is already extracted — add new public method that reuses the same private helper |
| Report timestamp formatting | Custom date string | Exact same `DateFormatter` from `CellarPaths.logFile(for:timestamp:)` | Consistent filename format across logs and reports |

**Key insight:** Every infrastructure component needed for Phase 3 already exists in the codebase. This phase is integration work, not infrastructure work.

---

## Common Pitfalls

### Pitfall 1: maxTotalAttempts too low blocks AI stage
**What goes wrong:** If bundled variants + dep installs consume all 5 attempts, the AI stage never runs. User sees no AI variants attempted.
**Why it happens:** `maxTotalAttempts = 5` was set before AI variants were planned.
**How to avoid:** Raise to 10 (at Claude's discretion per CONTEXT.md). The loop already breaks on success — the cap is only hit on genuine failure.
**Warning signs:** Test with a game that has 2 bundled retryVariants + 1 dep install — that's 4 attempts before AI even starts.

### Pitfall 2: AI variant generation called on every iteration instead of once
**What goes wrong:** Without the `aiVariantsGenerated` flag, `generateVariants()` gets called on every loop iteration after bundled variants are exhausted, burning API tokens and producing duplicate variants.
**Why it happens:** Incorrect loop exit/re-entry logic.
**How to avoid:** Track `var aiVariantsGenerated = false` before the while-loop; set to true before the API call.
**Warning signs:** Multiple "AI analysis:" lines printed for consecutive attempts.

### Pitfall 3: Cumulative history prompt grows unbounded
**What goes wrong:** Passing full stderr from all prior attempts makes the AI prompt enormous, slowing responses and potentially hitting token limits.
**Why it happens:** Each attempt has multi-KB logs; 5 attempts × 8KB = 40KB user message.
**How to avoid:** For each attempt in history, include only: attempt description, env diff keys (not values if sensitive), and a 500-char max excerpt from parsed error details. The AI needs patterns, not exhaustive logs.
**Warning signs:** API calls taking 10+ seconds; HTTP 400 errors from token limit.

### Pitfall 4: process.terminate() without wineserver kill leaves orphaned Wine processes
**What goes wrong:** On stale-output timeout in WineProcess.run(), calling `process.terminate()` kills the Wine binary but leaves `wineserver` running, holding the WINEPREFIX lock. Next attempt fails immediately.
**Why it happens:** WineProcess.run() currently only calls `process.terminate()` for the direct process.
**How to avoid:** Mirror WinetricksRunner: after `process.terminate()`, call `try? wineProcess.killWineserver()` (same WineProcess instance is available via `self`).
**Warning signs:** Immediate exit code on second attempt; "wineserver -k" needed manually.

### Pitfall 5: Recipe save writes partial/broken recipe when base recipe is nil
**What goes wrong:** If the game had no bundled recipe (AI-generated recipe from Phase 2 is the "current recipe"), merging AI variant env on top of a nil base produces a recipe missing required fields.
**Why it happens:** `recipe` variable in LaunchCommand is `Recipe?` — nil for unknown games without Phase 2 AI recipe.
**How to avoid:** Only attempt recipe save when `recipe != nil`. If recipe is nil but AI variant succeeded, save a minimal recipe constructed from the AI variant's environment dict. Log a warning either way.
**Warning signs:** Crash or missing executable field in saved JSON.

### Pitfall 6: Repair report directory not created before write
**What goes wrong:** `~/.cellar/logs/{gameId}/` might not exist if no prior launch logs were written (edge case: game added but never launched successfully).
**Why it happens:** Repair report write happens in the failure path, possibly before any log directory creation.
**How to avoid:** Replicate the existing log directory creation guard from the per-attempt setup block (`try FileManager.default.createDirectory(at: CellarPaths.logDir(for: game), withIntermediateDirectories: true)`). The existing per-attempt block already does this, so the report path is safe as long as at least one attempt ran.
**Warning signs:** File write failure crash in the failure reporting path.

---

## Code Examples

Verified from codebase inspection:

### OutputMonitor (from WinetricksRunner — copy verbatim to WineProcess)
```swift
// Source: Sources/cellar/Core/WinetricksRunner.swift lines 20-35
private final class OutputMonitor: @unchecked Sendable {
    private var _lastOutputTime = Date()
    private let lock = NSLock()

    func touch() {
        lock.lock()
        _lastOutputTime = Date()
        lock.unlock()
    }

    var lastOutputTime: Date {
        lock.lock()
        defer { lock.unlock() }
        return _lastOutputTime
    }
}
```

### WineProcess.run() timeout replacement (replaces waitUntilExit())
```swift
// Replace: process.waitUntilExit()
// With:
let outputMonitor = OutputMonitor()
// (add outputMonitor.touch() in readabilityHandlers above)
let staleTimeout: TimeInterval = 300  // 5 minutes per CONTEXT.md
var didTimeout = false
while process.isRunning {
    Thread.sleep(forTimeInterval: 2.0)
    if Date().timeIntervalSince(outputMonitor.lastOutputTime) > staleTimeout {
        print("\nGame launch has produced no output for \(Int(staleTimeout / 60)) minutes — assuming hung.")
        process.terminate()
        try? killWineserver()
        Thread.sleep(forTimeInterval: 1.0)
        didTimeout = true
        break
    }
}
// ...
return WineResult(exitCode: process.terminationStatus, stderr: stderrCapture.value,
                  elapsed: elapsed, logPath: logFile, timedOut: didTimeout)
```

### AI variant response JSON schema (for generateVariants prompt)
```json
{
  "reasoning": "The game likely needs a specific OpenGL version. Previous attempts show DirectX 8 fallback failing under default Mesa settings.",
  "variants": [
    {
      "description": "Force OpenGL 3.3 compatibility",
      "environment": { "MESA_GL_VERSION_OVERRIDE": "3.3", "MESA_GLSL_VERSION_OVERRIDE": "330" }
    },
    {
      "description": "Disable CSMT for single-threaded rendering",
      "environment": { "WINEDEBUG": "-all", "WINED3D_DISABLE_CSMT": "1" }
    }
  ]
}
```

### LaunchCommand: tracking original config count for save-on-success
```swift
// Before AI variant append:
let originalEnvConfigsCount = envConfigs.count

// After loop, when reachedMenu == true:
let winningConfigIndex = configIndex  // captured at break
let wonWithAIVariant = winningConfigIndex >= originalEnvConfigsCount
if wonWithAIVariant, let baseRecipe = recipe {
    let winningEnv = envConfigs[winningConfigIndex].environment
    // merge winningEnv over baseRecipe.environment
    // build updatedRecipe, call RecipeEngine.saveUserRecipe(updatedRecipe)
}
```

### Repair report file path helper (for CellarPaths)
```swift
// Mirrors existing logFile(for:timestamp:) pattern
static func repairReportFile(for gameId: String, timestamp: Date) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return logDir(for: gameId).appendingPathComponent("repair-report-\(formatter.string(from: timestamp)).txt")
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `process.waitUntilExit()` (blocking forever) | Polling loop with 5-min stale-output timeout | Phase 1.1 (WinetricksRunner) / Phase 3 (WineProcess) | Prevents hung launches blocking forever |
| Single-pass WineErrorParser | WineErrorParser + AI diagnosis on no-actionable-fix | Phase 2 | Handles errors outside parser's known patterns |
| Fixed bundled retryVariants | Bundled variants + dynamic AI-generated variants | Phase 3 | Adapts to unknown failure modes at runtime |

**Deprecated/outdated:**
- `maxTotalAttempts = 5` constant: too low for Phase 3 — needs to be raised to 10 (or made configurable).
- `WineResult.timedOut` always `false`: becomes meaningful after WineProcess.run() timeout is implemented.

---

## Open Questions

1. **How to handle the case where `recipe == nil` (no bundled or user recipe) at recipe-save time**
   - What we know: `recipe` is `Recipe?` in LaunchCommand; AI variant succeeded but there's no base recipe to merge onto
   - What's unclear: Should we construct a minimal stub Recipe from just the winning env, or skip save silently?
   - Recommendation: At Claude's discretion — simplest is to build a minimal Recipe with the game's existing fields from CellarStore + winning env; alternatively, skip save and log a warning. Saving something useful is better than silently discarding.

2. **Exact token budget strategy for cumulative history in AI prompt**
   - What we know: History should include attempt descriptions + error summaries; full stderr is too large
   - What's unclear: Should summaries come from WineErrorParser.parse() output (structured, compact) or from truncated raw stderr?
   - Recommendation: At Claude's discretion — parsed error details (WineError.detail strings) are compact and structured; raw stderr excerpt as fallback when parser returns empty.

3. **Whether to use a single "generate all 3 variants at once" call or sequential per-variant calls**
   - What we know: CONTEXT.md says "3 AI-generated variants" as a budget; single call is more efficient
   - What's unclear: Sequential calls could use cumulative feedback (variant 2 knows variant 1 failed) but cost 3x API calls
   - Recommendation: Single call returning up to 3 variants — simpler, faster, consistent with how generateRecipe() works. Sequential calls would be a future enhancement.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (swift-testing) |
| Config file | none — discovered via `swift test -Xswiftc -F /path/to/Testing.framework` |
| Quick run command | `swift test -Xswiftc -F$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks` |
| Full suite command | same (only one test target) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RECIPE-04 | At least one AI variant is generated and attempted when bundled variants exhausted | unit | `swift test --filter AIServiceVariantTests` | ❌ Wave 0 |
| RECIPE-04 | User sees "Trying variant 2/3..." labeling on retry attempts | manual-only | observe CLI output during launch | N/A |
| RECIPE-04 | Repair report file is written to correct path on exhaustion | unit | `swift test --filter RepairReportTests` | ❌ Wave 0 |
| RECIPE-04 | Working AI variant is saved as user recipe | unit | `swift test --filter RecipeEngineSaveTests` | ❌ Wave 0 |
| RECIPE-04 | Hung launch (stale output) is treated as failed attempt | unit | `swift test --filter WineProcessTimeoutTests` | ❌ Wave 0 |

Note: Most LaunchCommand integration behavior (full retry loop) is manual-only due to Wine process dependency. Unit tests focus on pure logic: AIService.generateVariants() parsing, CellarPaths path helpers, RecipeEngine.saveUserRecipe() write, and WineProcess.run() timeout return value.

### Sampling Rate
- **Per task commit:** `swift test -Xswiftc -F$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks`
- **Per wave merge:** same
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/cellarTests/AIServiceVariantTests.swift` — covers generateVariants() JSON parsing, variant count cap, unavailable/failed paths
- [ ] `Tests/cellarTests/RepairReportTests.swift` — covers CellarPaths.repairReportFile(for:timestamp:) path format
- [ ] `Tests/cellarTests/WineProcessTimeoutTests.swift` — covers WineResult.timedOut=true path (mock process required — likely manual-only, may be omitted)

---

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection — `Sources/cellar/Commands/LaunchCommand.swift` (full file, 300 lines)
- Direct codebase inspection — `Sources/cellar/Core/AIService.swift` (full file, 383 lines)
- Direct codebase inspection — `Sources/cellar/Core/WinetricksRunner.swift` (full file, 127 lines)
- Direct codebase inspection — `Sources/cellar/Core/WineProcess.swift` (full file, 188 lines)
- Direct codebase inspection — `Sources/cellar/Core/RecipeEngine.swift` (full file, 111 lines)
- Direct codebase inspection — `Sources/cellar/Persistence/CellarPaths.swift` (full file, 36 lines)
- Direct codebase inspection — `Sources/cellar/Models/Recipe.swift`, `AIModels.swift`, `WineResult.swift`
- `.planning/phases/03-repair-loop/03-CONTEXT.md` — locked decisions
- `.planning/STATE.md` — project decisions log

### Secondary (MEDIUM confidence)
- None required — all findings verifiable from first-party codebase source

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already present and battle-tested in codebase
- Architecture: HIGH — all patterns are direct extensions of existing, proven code
- Pitfalls: HIGH — derived from reading actual code paths and decision log
- Test infrastructure: HIGH — test framework identified from existing DependencyCheckerTests.swift

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (stable Swift/Foundation APIs; no fast-moving dependencies)
