# Phase 26: ISO Disc Image Support for Game Installation - Research

**Researched:** 2026-04-02
**Domain:** macOS disc image mounting (hdiutil), file system scanning, AddCommand integration
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Supported formats:** `.iso` (primary), `.bin/.cue` (secondary). Other formats (.mdf/.mds, .nrg) out of scope.
- **Mount strategy:** Use `hdiutil attach` for .iso natively; attempt `hdiutil convert` to .iso for .bin/.cue that hdiutil can't mount directly. Mount to a temporary directory, unmount after installation (always, even on failure). If mount fails, print actionable error message.
- **Installer discovery priority:**
  1. Parse `autorun.inf` — extract `open=` value
  2. Look for `setup.exe`, `install.exe`, `Setup.exe`, `Install.exe` at volume root
  3. If multiple candidates found, present to user for selection
  4. If no installer found, list all `.exe` files and let user choose, or error if none exist
- **Game name:** derived from volume label (if meaningful) or image filename
- **AddCommand integration:** Detect input extension in AddCommand; route disc images through a handler that returns an installer `.exe` path on the mounted volume; existing pipeline runs unchanged from that point; unmount in defer block
- **CLI UX:** `cellar add /path/to/game.iso` — same command as .exe. Print mount/unmount status. Handle disc 1 only for multi-disc.

### Claude's Discretion

- Whether to create a separate `DiscImageHandler` struct or inline the logic in AddCommand
- Exact hdiutil flags for mounting (read-only, nobrowse, etc.)
- Whether to support .img files (often just renamed .iso)
- Temp directory naming/cleanup strategy
- How to handle cases where hdiutil needs sudo (shouldn't for read-only mounts)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ISO/BIN/CUE detection | AddCommand detects .iso, .bin, .cue file extension before existing pipeline | URL.pathExtension on installerURL; set of ["iso", "bin", "cue"] |
| Disc image mounting | Mount image to a temporary location using hdiutil attach, capture mount point | hdiutil attach -plist -readonly -nobrowse; parse system-entities array from plist output using PropertyListSerialization |
| Installer discovery within mounted volumes | Scan volume for autorun.inf, common installer names, fallback to .exe list | FileManager.default.contentsOfDirectory; case-insensitive autorun.inf parsing |
| Cleanup/unmount after install | Detach with hdiutil detach on mount point, always (even on failure) | Swift defer block in async func; hdiutil detach <mountpoint> |

</phase_requirements>

## Summary

Phase 26 extends `cellar add` to accept `.iso`, `.bin`, and `.cue` disc image files. The implementation wraps the existing installer pipeline — AddCommand detects the file extension, mounts the image with `hdiutil attach`, discovers the installer `.exe` within the mounted volume, and hands that path to the existing pipeline. Cleanup is guaranteed by a `defer` block.

macOS's `hdiutil` tool handles this entirely without third-party dependencies. It supports ISO 9660 images natively via `hdiutil attach`. For `.bin` files, hdiutil can mount raw binary images using `-imagekey diskimage-class=CRawDiskImage`, but game `.bin/.cue` pairs that use non-standard sector formats (CD-ROM Mode 2 XA, etc.) may need conversion with `hdiutil convert`. The plist output format (`-plist` flag) is stable and machine-parseable using Foundation's `PropertyListSerialization`.

The recommended architecture is a separate `DiscImageHandler` struct in `Sources/cellar/Core/` following the `GuidedInstaller`/`WinetricksRunner` pattern — synchronous, `Process`-based, returning structured results. This keeps `AddCommand.run()` readable and keeps disc image logic testable in isolation. The integration point in AddCommand is a small guard at the top of `run()` that swaps the `installerURL` for the discovered `.exe` URL.

**Primary recommendation:** Create `DiscImageHandler.swift` in `Sources/cellar/Core/` with a single `mountAndDiscover(imageURL:) throws -> (installerURL: URL, mountPoint: URL)` method. AddCommand calls it early, `defer`s a `detach(mountPoint:)` call, then continues the existing pipeline unchanged.

## Standard Stack

### Core

| Tool/API | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `hdiutil` | macOS built-in | Mount/unmount/convert disc images | Apple's official disc image tool; no dependencies; handles ISO, UDIF, raw binary |
| `Foundation.Process` | Swift stdlib | Run hdiutil as subprocess | Already used throughout codebase (GuidedInstaller, WinetricksRunner, WineProcess) |
| `Foundation.PropertyListSerialization` | Swift stdlib | Parse hdiutil -plist output | Standard; no third-party XML parsing needed |
| `Foundation.FileManager` | Swift stdlib | Scan mounted volume for executables | Already used in AddCommand, BottleScanner |

### Supporting

| Tool/API | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `hdiutil convert` | macOS built-in | Convert .bin to writable ISO before attaching | When `hdiutil attach` fails on a .bin file |
| `Foundation.URL.pathExtension` | Swift stdlib | Detect .iso/.bin/.cue extension | Already used in AddCommand for other extension detection |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `hdiutil attach -plist` | Parse human-readable hdiutil output | Plist is stable and machine-readable per Apple docs; text output is "generally unstructured" |
| `hdiutil attach -mountpoint` | Default /Volumes mount | `-mountpoint` gives us a known path; avoids parsing volume name; cleaner cleanup |

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/Core/
├── DiscImageHandler.swift    # New: mount/discover/detach logic
├── GuidedInstaller.swift     # Existing pattern to follow
├── WinetricksRunner.swift    # Existing pattern to follow
└── ...
```

### Pattern 1: DiscImageHandler Struct (follows GuidedInstaller/WinetricksRunner pattern)

**What:** A separate struct with synchronous Process-based methods; returns structured results.
**When to use:** Any time AddCommand receives a .iso, .bin, or .cue file.

```swift
// Sources/cellar/Core/DiscImageHandler.swift
import Foundation

struct DiscImageHandler {

    struct DiscMountResult {
        let mountPoint: URL
        let devEntry: String   // /dev/diskNsM — used for detach
    }

    /// Mounts a disc image and returns mount info.
    /// Caller is responsible for calling detach() in a defer block.
    func mount(imageURL: URL) throws -> DiscMountResult { ... }

    /// Discovers the installer .exe within a mounted volume.
    /// Priority: autorun.inf > common names > user selection > error.
    func discoverInstaller(at mountPoint: URL) throws -> URL { ... }

    /// Detaches a mounted disc image. Safe to call even if mount partially succeeded.
    func detach(devEntry: String) { ... }
}
```

**AddCommand integration point (line 17–24 area):**

```swift
// After file existence check, before dependency check:
let discImageExtensions = Set(["iso", "bin", "cue"])
let fileExtension = installerURL.pathExtension.lowercased()

var mountResult: DiscImageHandler.DiscMountResult? = nil
var effectiveInstallerURL = installerURL

if discImageExtensions.contains(fileExtension) {
    let handler = DiscImageHandler()
    print("Mounting disc image...")
    let mount = try handler.mount(imageURL: installerURL)
    mountResult = mount
    defer {
        // Unmount happens at scope exit, even on throw
        handler.detach(devEntry: mount.devEntry)
        print("Disc image unmounted.")
    }
    print("Disc image mounted at \(mount.mountPoint.path)")
    effectiveInstallerURL = try handler.discoverInstaller(at: mount.mountPoint)
    // Use effectiveInstallerURL instead of installerURL for rest of pipeline
}
```

**Note:** `defer` works correctly in async `run()` methods — Swift's defer executes at scope exit regardless of async/await.

### Pattern 2: hdiutil attach with -plist output

**What:** Run `hdiutil attach -readonly -nobrowse -plist <image>` and parse XML plist from stdout.
**When to use:** Mounting .iso files and compatible .bin files.

```swift
// Source: hdiutil man page + hdiutil info -plist (verified against live output)
// The plist structure:
// {
//   "system-entities": [
//     { "dev-entry": "/dev/disk5", "content-hint": "GUID_partition_scheme" },
//     { "dev-entry": "/dev/disk5s1", "mount-point": "/Volumes/GAME_DISC" }
//   ]
// }
//
// Parsing pattern:
let data = stdoutData
if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
   let entities = plist["system-entities"] as? [[String: Any]] {
    for entity in entities {
        if let mountPoint = entity["mount-point"] as? String,
           let devEntry = entity["dev-entry"] as? String {
            // Found the mounted volume
        }
    }
}
```

**Recommended flags:**
- `-readonly` — forces read-only; disc images should never be written to
- `-nobrowse` — hides the volume from Finder/Spotlight; clean UX, no spurious desktop icons
- `-plist` — machine-parseable output; stable since macOS 10.0
- No `-mountpoint` needed — parse mount-point from plist instead (handles multi-partition images)

### Pattern 3: Capturing stdout from Process (no streaming needed)

**What:** Run hdiutil synchronously and capture stdout to Data for plist parsing. Unlike GuidedInstaller/WinetricksRunner, hdiutil finishes quickly — no streaming or stale-output detection needed.

```swift
// Simple synchronous capture (different from WinetricksRunner's streaming pattern)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
process.arguments = ["attach", "-readonly", "-nobrowse", "-plist", imageURL.path]

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = Pipe()  // discard stderr (hdiutil progress noise)

try process.run()
process.waitUntilExit()

let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
// parse outputData as plist
```

**Note:** `hdiutil detach` takes either a mount-point path or a `/dev/diskN` entry. Using the dev-entry from the plist is most reliable (mount-point may not exist if only a block device was attached with no filesystem).

### Pattern 4: autorun.inf parsing

**What:** Read `AUTORUN.INF` (case-insensitive filename) from volume root and extract `open=` value.
**When to use:** Before falling back to hardcoded installer name scan.

```swift
// autorun.inf is a Windows INI file. Format:
// [autorun]
// open=Setup.exe
// (values may have quotes, forward slashes, mixed case)

func parseAutorun(at volumeRoot: URL) -> URL? {
    let candidates = ["AUTORUN.INF", "autorun.inf", "Autorun.inf"]
    for name in candidates {
        let url = volumeRoot.appendingPathComponent(name)
        guard let content = try? String(contentsOf: url, encoding: .isoLatin1) else { continue }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("open=") {
                let value = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .init(charactersIn: "\"'"))
                    .replacingOccurrences(of: "\\", with: "/")
                let exeURL = volumeRoot.appendingPathComponent(value)
                if FileManager.default.fileExists(atPath: exeURL.path) {
                    return exeURL
                }
            }
        }
    }
    return nil
}
```

**Encoding note:** autorun.inf files use Windows-1252 or Latin-1. Use `.isoLatin1` encoding (not `.utf8`) to avoid decoding failures.

### Pattern 5: .bin/.cue handling

**What:** Try `hdiutil attach` first on the .bin file. If it fails (exit code != 0), attempt `hdiutil convert` to an ISO before attaching.
**When to use:** When input is .bin or .cue extension.

```swift
// For .cue input: find companion .bin in same directory
// For .bin input: find companion .cue in same directory (optional — hdiutil may not need it)

// Attempt 1: direct attach (works for Mode 1 / 2048-byte sector raw images)
// hdiutil attach -imagekey diskimage-class=CRawDiskImage -readonly -nobrowse -plist game.bin

// Attempt 2: convert to iso first (for Mode 2 XA or non-standard sector sizes)
// hdiutil convert game.bin -format UDTO -o /tmp/cellar-game-XXXXXX.iso
// Then: hdiutil attach -readonly -nobrowse -plist /tmp/cellar-game-XXXXXX.iso
// Cleanup: delete the temp .iso after detach
```

### Anti-Patterns to Avoid

- **Mounting to a hardcoded path:** Use a temp dir with `FileManager.default.temporaryDirectory` + UUID, or let hdiutil auto-mount under `/Volumes`. Hardcoded paths collide if two instances run concurrently.
- **Relying on volume label for mount point:** The `/Volumes/<label>` path is not guaranteed — some ISO images have no label or have special characters. Always read the mount-point from plist output.
- **Parsing hdiutil's human-readable output:** Apple documents it as "generally unstructured." Always use `-plist`.
- **Not detaching on failure:** Any error before detach leaves a mounted volume dangling. Always use `defer` to call detach.
- **Running hdiutil with sudo:** Not needed. `hdiutil attach` on a read-only image as a normal user works without elevated privileges.
- **Using -mountpoint flag with multi-partition images:** Some game ISOs have two partitions (ISO9660 + HFS hybrid). `-mountpoint` only works for single-partition images. Let hdiutil auto-mount and read the mount-point from plist.
- **Blocking stdin during installer discovery:** The user-selection prompt (multiple candidates) requires `readLine()` — same pattern as AddCommand already uses for recipe questions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ISO mounting | Custom ISO9660 parser | `hdiutil attach` | macOS provides this; handles HFS hybrid, UDF, ISO9660, Joliet — all common game disc formats |
| .bin/.cue parsing | CUE sheet parser | `hdiutil attach -imagekey diskimage-class=CRawDiskImage` or `hdiutil convert` | CUE format has many edge cases (MODE2/2352, multi-track, INDEX offsets) |
| Plist XML parsing | Manual XML string parsing | `PropertyListSerialization` | Foundation already in the project; handles both binary and XML plist |
| Temp directory creation | Custom UUID path | `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` | System temp dir is auto-cleaned; UUID ensures uniqueness |

**Key insight:** hdiutil is the correct macOS-native tool for this domain. Wine/CrossOver itself uses hdiutil internally for disc image support. There are no third-party alternatives that would be appropriate for a macOS CLI tool with no SPM dependency policy.

## Common Pitfalls

### Pitfall 1: hdiutil attach returns exit 0 but no mount-point

**What goes wrong:** Some .iso files mount the block device (appear in plist `system-entities`) but no `mount-point` key exists — the filesystem was not recognized or no volumes were present.
**Why it happens:** ISOs without a recognizable filesystem (raw data discs, copy-protected images with non-standard sectors) attach but don't mount.
**How to avoid:** After parsing plist, verify at least one entity has a `mount-point` key. If none, detach immediately and report: "Could not mount disc image — the image may be copy-protected or in an unsupported format."
**Warning signs:** `system-entities` array contains only one entry (the block device), no `mount-point` key anywhere.

### Pitfall 2: Mount-point path case sensitivity / volume name collisions

**What goes wrong:** If a volume named "GAME" is already mounted at `/Volumes/GAME`, hdiutil mounts the new image at `/Volumes/GAME 1`. The mounted path is only reliably known from plist output, not from guessing.
**Why it happens:** macOS appends a number suffix to resolve volume label conflicts.
**How to avoid:** Always read `mount-point` from plist output. Never construct the path as `/Volumes/<imagename>`.

### Pitfall 3: autorun.inf backslash paths

**What goes wrong:** Windows installers use backslash paths in autorun.inf: `open=Disk1\Setup.exe`. Using this directly on macOS as a URL path fails.
**Why it happens:** ISO 9660 files from Windows use Windows path separators.
**How to avoid:** Replace `\\` with `/` after reading the `open=` value before constructing the URL.

### Pitfall 4: defer vs. async scope in Swift

**What goes wrong:** Placing `defer` inside an `if` block means it only fires when that block exits, not the function.
**Why it happens:** Swift `defer` is scoped to the enclosing block, not just the function.
**How to avoid:** Either use a top-level `defer` with an optional (`if let mount = mountResult { detach(mount) }`) placed early in `run()`, or extract the disc-image handling into a separate helper that owns the defer scope. The pattern used in this codebase (AddCommand.run() is a single long async function) makes the optional defer approach cleaner:
```swift
var mountResult: DiscImageHandler.DiscMountResult? = nil
defer {
    if let m = mountResult {
        DiscImageHandler().detach(devEntry: m.devEntry)
        print("Disc image unmounted.")
    }
}
// ... set mountResult = try handler.mount(imageURL: installerURL) ...
```

### Pitfall 5: hdiutil detach failing with "resource busy"

**What goes wrong:** `hdiutil detach <mountpoint>` fails with "hdiutil: couldn't unmount disk" if any process still has a file handle open inside the mounted volume — including the Wine installer that just ran.
**Why it happens:** Wine installer process may not fully exit before detach is called. Wineserver child processes may hold file handles.
**How to avoid:** After `wineProcess.run()` returns, call `killWineserver()` (already exists in WineProcess) before detach. If detach fails at exit code != 0, retry once with `-force`. Log a warning if forced detach was needed.

### Pitfall 6: .cue file provided but .bin is missing/misnamed

**What goes wrong:** User provides `game.cue` — the .cue file references `game.bin` but the actual file is `GAME.BIN` or `game track 01.bin`.
**Why it happens:** Case sensitivity on macOS (HFS+) vs. the case-insensitive filename inside the .cue sheet.
**How to avoid:** When input is `.cue`, read the CUE file's `FILE "..."` directive (first line after `FILE`) to find the .bin filename. Do a case-insensitive search in the same directory.

## Code Examples

Verified patterns from official sources and live system verification:

### Run hdiutil attach and parse plist output

```swift
// Source: hdiutil man page + verified against live hdiutil info -plist output (2026-04-02)
func runHdiutil(_ args: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw DiscImageError.hdiutilFailed(errMsg)
    }
    return outPipe.fileHandleForReading.readDataToEndOfFile()
}
```

### Parse mount-point from hdiutil attach -plist output

```swift
// Source: verified against live hdiutil info -plist output structure (2026-04-02)
// Top-level key (for hdiutil attach output): "system-entities" array directly (not nested under "images")
// Each entity dict may contain: "dev-entry", "content-hint", "mount-point"
func parseMountPoint(from plistData: Data) throws -> (mountPoint: URL, devEntry: String) {
    guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
          let dict = plist as? [String: Any],
          let entities = dict["system-entities"] as? [[String: Any]] else {
        throw DiscImageError.plistParseFailed
    }
    for entity in entities {
        if let mountStr = entity["mount-point"] as? String,
           let devStr = entity["dev-entry"] as? String {
            return (URL(fileURLWithPath: mountStr), devStr)
        }
    }
    throw DiscImageError.noVolumesMounted
}
```

**Important:** `hdiutil attach -plist` output has `system-entities` at the top level (not nested under an `images` key). `hdiutil info -plist` nests under `images[N].system-entities`. The attach command's plist is different from the info command's plist.

### hdiutil detach with fallback to -force

```swift
// Source: hdiutil man page
func detach(devEntry: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["detach", devEntry]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        // Retry with -force (resource busy after Wine process exit)
        let forceProcess = Process()
        forceProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        forceProcess.arguments = ["detach", "-force", devEntry]
        forceProcess.standardOutput = Pipe()
        forceProcess.standardError = Pipe()
        try? forceProcess.run()
        forceProcess.waitUntilExit()
    }
}
```

### Common installer names scan (volume root)

```swift
// Priority order from CONTEXT.md decision
let commonNames = ["setup.exe", "install.exe", "Setup.exe", "Install.exe"]
let volumeRoot: URL = ...

for name in commonNames {
    let candidate = volumeRoot.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
    }
}
// Fallback: list all .exe files
let contents = try FileManager.default.contentsOfDirectory(
    at: volumeRoot,
    includingPropertiesForKeys: nil
)
let exes = contents.filter { $0.pathExtension.lowercased() == "exe" }
```

### Extension detection in AddCommand (integration point)

```swift
// In AddCommand.run(), after verifying file exists (line ~24), before dependency check:
let discExtensions = Set(["iso", "bin", "cue"])
var effectiveInstallerURL = installerURL
var mountResult: DiscImageHandler.MountResult? = nil

defer {
    if let m = mountResult {
        DiscImageHandler().detach(devEntry: m.devEntry)
        print("Disc image unmounted.")
    }
}

if discExtensions.contains(installerURL.pathExtension.lowercased()) {
    let handler = DiscImageHandler()
    print("Mounting disc image \(installerURL.lastPathComponent)...")
    let mount = try handler.mount(imageURL: installerURL)
    mountResult = mount
    print("Mounted at \(mount.mountPoint.path)")
    effectiveInstallerURL = try handler.discoverInstaller(at: mount.mountPoint)
    print("Found installer: \(effectiveInstallerURL.lastPathComponent)")
}

// All subsequent pipeline code uses effectiveInstallerURL instead of installerURL
// Game name derivation also updated to prefer volume label over image filename
```

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Third-party tools (cdemu, fuseiso) | macOS `hdiutil` | hdiutil is Apple-maintained, always present on macOS, no install required |
| Mounting to /Volumes directly | `-nobrowse` flag | Prevents Finder from showing mounted image as removable disk |

**Deprecated/outdated:**
- `hdid`: Replaced by `hdiutil attach`. hdid(8) still exists but hdiutil is the documented interface.

## Open Questions

1. **hdiutil attach behavior for Mode 2 XA .bin files (CD-ROM XA format)**
   - What we know: Mode 2 XA is used by some late-1990s games. hdiutil may fail to attach these without conversion.
   - What's unclear: Does `-imagekey diskimage-class=CRawDiskImage` handle Mode 2 XA, or does it always need `hdiutil convert` first?
   - Recommendation: Implement with try-convert-on-failure pattern. First attempt direct attach; if that fails, attempt `hdiutil convert -format UDTO -o /tmp/...` and attach the converted file. This covers both cases and is the approach documented in CONTEXT.md.

2. **Volume label extraction for game name**
   - What we know: The `mount-point` from plist output is derived from the volume label (e.g., `/Volumes/CIVILIZATION III`). This can be used as the game name.
   - What's unclear: Whether to prefer the volume label or the image filename when both are present.
   - Recommendation: Prefer volume label if it's non-generic (not "CDROM", "DISC1", etc.); fall back to image filename. Simple heuristic: if volume label is shorter than 30 chars and doesn't match common generic patterns, use it.

3. **Web UI (GameController) support for disc images**
   - What we know: `POST /games` in GameController.swift (line 36-51) validates the installer path and extracts the game ID from filename. This only handles .exe files currently.
   - What's unclear: Whether Phase 26 should also update GameController to accept disc images via the web UI.
   - Recommendation: Out of scope for Phase 26 per CONTEXT.md (no deferred ideas mentioned, but the discussion was CLI-focused). The web UI can be extended in a follow-on phase. For now, document that disc image support is CLI-only.

## Sources

### Primary (HIGH confidence)
- `hdiutil` man page (macOS system) - attach, detach, convert verbs, plist flag, imagekey options
- Live `hdiutil info -plist` output (2026-04-02) - verified system-entities plist structure with mount-point and dev-entry keys
- AddCommand.swift (project codebase) - integration points, existing pipeline structure, defer usage
- GuidedInstaller.swift / WinetricksRunner.swift (project codebase) - Process patterns to follow
- CellarPaths.swift (project codebase) - temp dir patterns, FileManager.default.temporaryDirectory usage

### Secondary (MEDIUM confidence)
- hdiutil man page examples section: `hdiutil attach -imagekey diskimage-class=CRawDiskImage myBlob.bar` — confirms raw binary image support
- hdiutil man page: `hdiutil detach` accepts mount-point or dev-entry — confirmed in help output
- Apple DiskImages framework behavior: `-nobrowse` hides volumes from Finder (from man page)

### Tertiary (LOW confidence)
- autorun.inf encoding (Latin-1 / Windows-1252): Based on Windows file format knowledge — should be validated against actual game ISOs
- Mode 2 XA behavior with hdiutil: Not directly tested — requires actual Mode 2 CD image to verify

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — hdiutil is macOS built-in, verified man page and live plist output
- Architecture: HIGH — follows established GuidedInstaller/WinetricksRunner patterns exactly
- Pitfalls: MEDIUM/HIGH — most verified via man page and live output; Mode 2 XA behavior is LOW
- Code examples: HIGH — plist structure verified against live `hdiutil info -plist` output

**Research date:** 2026-04-02
**Valid until:** 2027-04-02 (hdiutil is a stable macOS API, changes very rarely)
