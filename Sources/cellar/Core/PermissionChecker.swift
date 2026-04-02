import CoreGraphics

struct PermissionChecker {
    struct Result {
        let screenRecording: Bool
    }

    /// Check Screen Recording permission silently (no system prompt).
    /// Returns the permission state. Does NOT block — advisory only.
    static func check() -> Result {
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        return Result(screenRecording: hasScreenRecording)
    }

    /// Print advisory warnings for missing permissions.
    /// Does not block execution — warnings are informational.
    static func printWarningsIfNeeded() {
        let result = check()
        if !result.screenRecording {
            print("Note: Screen Recording permission is not granted.")
            print("  The agent's window detection will be limited without it.")
            print("  Try this: Open System Settings > Privacy & Security > Screen Recording")
            print("  and grant access to Terminal (or your terminal app).")
            print("  Or run: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'")
            print("")
        }
    }
}
