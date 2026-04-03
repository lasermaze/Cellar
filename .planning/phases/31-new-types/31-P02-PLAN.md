---
phase: 31-new-types
plan: 02
type: execute
wave: 1
depends_on: []
files_modified: [Sources/cellar/Core/AgentControl.swift]
autonomous: true
requirements: [ARCH-02, BUG-04]

must_haves:
  truths:
    - AgentControl class is final and Sendable with no @unchecked annotation
    - Thread safety provided by OSAllocatedUnfairLock — not bare vars
    - shouldAbort and userForceConfirmed readable as Bool properties
    - abort() and confirm() methods set flags through the lock
  artifacts:
    - Sources/cellar/Core/AgentControl.swift (new)
  key_links:
    - AgentControl replaces bare vars on AgentTools (wiring happens in Phase 34/35)
---

<objective>
Create the AgentControl thread-safe control channel class.

Purpose: Provide a properly Sendable, lock-protected control channel that replaces the @unchecked Sendable bare vars currently on AgentTools — eliminating data races between web routes and agent loop.
Output: New file AgentControl.swift.
</objective>

<execution_context>
@/Users/peter/.claude/get-shit-done/workflows/execute-plan.md
@/Users/peter/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/agent-loop-rewrite-brief.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create AgentControl.swift</name>
  <files>Sources/cellar/Core/AgentControl.swift</files>
  <action>
Create a new file `Sources/cellar/Core/AgentControl.swift` with the following exact implementation:

```swift
import Foundation

// MARK: - AgentControl

/// Thread-safe control channel between web UI and agent loop.
///
/// Web routes call `abort()` / `confirm()`. Agent loop reads `shouldAbort` / `userForceConfirmed`.
/// Uses `OSAllocatedUnfairLock` for proper Sendable conformance without `@unchecked`.
final class AgentControl: Sendable {
    private let _lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var shouldAbort = false
        var userForceConfirmed = false
    }

    var shouldAbort: Bool {
        _lock.withLock { $0.shouldAbort }
    }

    var userForceConfirmed: Bool {
        _lock.withLock { $0.userForceConfirmed }
    }

    func abort() {
        _lock.withLock { $0.shouldAbort = true }
    }

    func confirm() {
        _lock.withLock { $0.userForceConfirmed = true }
    }
}
```

Note: `OSAllocatedUnfairLock` is available from `import Foundation` (it's in the `os` module which Foundation re-exports). If the compiler cannot find it, add `import os` explicitly.

This class is not wired into AgentTools or LaunchController yet — that happens in Phase 34/35. It just needs to exist and compile.
  </action>
  <verify>
    <automated>cd /Users/peter/Documents/Cellar && swift build 2>&1 | tail -5</automated>
  </verify>
  <done>AgentControl.swift exists at Sources/cellar/Core/AgentControl.swift; class is final and Sendable; uses OSAllocatedUnfairLock; project compiles</done>
</task>

</tasks>

<verification>
1. `swift build` succeeds with zero errors
2. `Sources/cellar/Core/AgentControl.swift` exists
3. AgentControl is `final class` and conforms to `Sendable` (not `@unchecked Sendable`)
4. No other files modified
</verification>

<success_criteria>
- `swift build` passes
- AgentControl.swift is a new file with the thread-safe control channel
- No changes to any existing file
</success_criteria>

<output>
After completion, create `.planning/phases/31-new-types/31-P02-SUMMARY.md`
</output>
