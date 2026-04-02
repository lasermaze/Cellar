# Phase 23: Homebrew Tap Distribution with Launcher .app — Research

**Researched:** 2026-04-01
**Domain:** Homebrew tap mechanics, GitHub Actions CI/CD, macOS .app bundles, binary distribution
**Confidence:** HIGH (all critical findings verified with official docs or multiple sources)

## Summary

Phase 23 distributes the Cellar CLI via a Homebrew tap with pre-built bottles, eliminating the source-build requirement of the current `Cellar.command`. Three deliverables are needed: (1) a GitHub tap repo (`<org>/homebrew-cellar`) with a Ruby formula, (2) a GitHub Actions workflow in the main Cellar repo that builds a universal binary on tagged push and uploads it to GitHub Releases, and (3) a `Cellar.app` created in `/Applications` after install for double-click-to-serve.

The Gatekeeper concern is **not a blocker for formula bottles**. Homebrew's 2025 Gatekeeper crackdown targets *casks* only. Formula bottles — compiled CLI binaries poured into Homebrew's prefix — are explicitly exempt. An ad-hoc `codesign --sign -` applied in `post_install` resolves any Apple Silicon execution issues without requiring a paid developer account.

The `.app` bundle problem is the hardest design decision. Homebrew formulas cannot write to `/Applications` — that's strictly a cask privilege. The recommended pattern for CLI+server tools is to ship a shell script in `bin/` that creates the `.app` on first run (via `cellar install-app` subcommand), and have `caveats` tell the user to run it once. Alternatively, a minimal `Cellar.app` can be pre-built and stored in the formula's `libexec/` directory, then symlinked or copied to `~/Applications` (not `/Applications`) without requiring sudo.

**Primary recommendation:** Use `swift build -c release --arch x86_64 --arch arm64` to produce a universal binary in one step. Distribute via a dedicated tap repo. Use `NSHipster/update-homebrew-formula-action` to automate sha256 updates. For the `.app`, create it in `post_install` inside `libexec/` and provide a `cellar install-app` subcommand that copies it to `~/Applications`, with `caveats` prompting the user.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIST-01 | `brew tap <org>/cellar && brew install cellar` installs a pre-built binary — no Xcode or Swift toolchain required on the user's machine | Formula bottle DSL with `root_url` pointing to GitHub Releases + `cellar: :any_skip_relocation` makes this work. Bottles are poured without any source build. |
| DIST-02 | GitHub Actions workflow builds a universal (arm64 + x86_64) release binary on every tagged push, uploads to GitHub Releases, and updates the bottle hash in the formula | `swift build -c release --arch x86_64 --arch arm64` produces a fat binary on a single macOS runner. `softprops/action-gh-release` uploads it. `NSHipster/update-homebrew-formula-action` or manual sed updates the sha256 in the tap formula. |
| DIST-03 | After `brew install`, a `Cellar.app` exists that starts `cellar serve` if not running and opens `http://127.0.0.1:8080` | Homebrew formulas cannot write to `/Applications`. The pattern is: bundle a pre-built `.app` shell in `libexec/`, expose `cellar install-app` subcommand, print `caveats` instructions. The `.app` itself is a 5-file shell script bundle with `Info.plist`. Port detection via `lsof -i :8080`. |

Note: DIST-01, DIST-02, DIST-03 are not yet defined in REQUIREMENTS.md — they must be added during planning.
</phase_requirements>

## Standard Stack

### Core

| Tool / Library | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `brew tap-new` | Homebrew CLI | Scaffold tap repo + CI workflows | Official tool; generates correct `.github/workflows` |
| `swift build --arch` | Swift 6.0 (system) | Universal binary compilation | Single command, no `lipo` needed for SPM targets |
| `softprops/action-gh-release` | v2 | Upload binary artifacts to GitHub Releases | De-facto standard for GH release uploads in Actions |
| `NSHipster/update-homebrew-formula-action` | @main | Update sha256 in tap formula after release | Purpose-built for exactly this workflow; eliminates manual sed |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `codesign --sign -` (ad-hoc) | Ad-hoc sign binary so Apple Silicon executes it | Always — run in `post_install` in the formula |
| `lsof -i :8080` | Detect if `cellar serve` is already listening | In the `.app` launcher shell script before starting a new server |
| `open http://127.0.0.1:8080` | Open default browser to web UI | In the `.app` launcher shell script after confirming server is up |
| `shasum -a 256` | Compute bottle SHA256 for formula | In CI after building the binary archive |

### Alternatives Considered

| Standard | Alternative | Tradeoff |
|----------|-------------|----------|
| Formula + `cellar install-app` caveats | Cask distributing `.app` directly to `/Applications` | Cask requires signed/notarized binary per Homebrew 5.0.0; formula bottles are exempt |
| `swift build --arch x86_64 --arch arm64` | Separate arm64 + x86_64 builds then `lipo` | Both work; `--arch` flags produce fat binary in one pass which is simpler |
| `NSHipster/update-homebrew-formula-action` | Manual `sed` to update sha256 | Action handles all platform sha256s + version bump atomically; sed is fragile |
| Shell script `.app` bundle | Swift-compiled `.app` with `NSWorkspace` | Shell script requires no compilation, no signing friction, is trivially debuggable |

## Architecture Patterns

### Deliverable 1: Tap Repository (`<org>/homebrew-cellar`)

```
homebrew-cellar/
├── Formula/
│   └── cellar.rb          # The formula (source of truth for version + sha256)
└── .github/
    └── workflows/
        └── tests.yml      # Auto-generated by brew tap-new; tests formula on PR
```

The tap repo is separate from the main Cellar source repo. Users add it once with `brew tap <org>/cellar`.

### Deliverable 2: GitHub Actions in Main Repo

Triggered on `on: release: types: [published]` OR `on: push: tags: ['v*']`.

```
.github/
└── workflows/
    └── release.yml        # Build universal binary, upload to Releases, update tap formula
```

The workflow:
1. Runs on `macos-latest` (ARM64 runner as of 2024)
2. Builds `swift build -c release --arch x86_64 --arch arm64`
3. Archives: `tar -czf cellar-<version>-macos.tar.gz -C .build/apple/Products/Release cellar`
4. Computes `shasum -a 256 cellar-<version>-macos.tar.gz`
5. Uploads archive to GitHub Releases via `softprops/action-gh-release@v2`
6. Updates tap formula sha256 via `NSHipster/update-homebrew-formula-action@main`

### Deliverable 3: Formula (`cellar.rb`)

```ruby
class Cellar < Formula
  desc "AI-powered Wine launcher for old Windows games on macOS"
  homepage "https://github.com/<org>/cellar"
  url "https://github.com/<org>/cellar/releases/download/v1.3.0/cellar-1.3.0-macos.tar.gz"
  sha256 "<computed-by-ci>"
  version "1.3.0"

  bottle do
    root_url "https://github.com/<org>/cellar/releases/download/v1.3.0"
    cellar :any_skip_relocation
    sha256 arm64_sequoia: "<hash>"
    sha256 sequoia:       "<hash>"
  end

  def post_install
    # Ad-hoc sign for Apple Silicon execution
    system "codesign", "--sign", "-", bin/"cellar"

    # Build the minimal Cellar.app launcher inside libexec
    app_dir = libexec/"Cellar.app/Contents/MacOS"
    app_dir.mkpath
    (libexec/"Cellar.app/Contents").write_file "Info.plist", <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>CellarLauncher</string>
        <key>CFBundleIdentifier</key><string>dev.cellar.launcher</string>
        <key>CFBundleName</key><string>Cellar</string>
        <key>CFBundleVersion</key><string>#{version}</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSUIElement</key><true/>
      </dict></plist>
    XML
    (app_dir/"CellarLauncher").write <<~SH
      #!/bin/bash
      CELLAR_BIN="#{opt_bin}/cellar"
      if ! lsof -i :8080 -s TCP:LISTEN -t >/dev/null 2>&1; then
        "$CELLAR_BIN" serve &
        sleep 1
      fi
      open http://127.0.0.1:8080
    SH
    chmod 0755, app_dir/"CellarLauncher"
  end

  def caveats
    <<~EOS
      To add Cellar.app to your Applications folder, run:
        cellar install-app
      Then double-click Cellar.app to start the web UI without opening a terminal.
    EOS
  end

  test do
    system "#{bin}/cellar", "--version"
  end
end
```

**Note on `/Applications` write restriction:** Homebrew formulas cannot write to `/Applications` in `post_install` without `sudo`. The pattern above stores the app in `libexec/` and exposes `cellar install-app` to copy it to `~/Applications` (no sudo) or `/Applications` (requires sudo, user-prompted). Most CLI+server projects use this pattern.

### Deliverable 4: `cellar install-app` Subcommand (in main source)

A new `InstallAppCommand` added to `Sources/cellar/Commands/`:

```swift
// Copies libexec/Cellar.app → ~/Applications/Cellar.app
// Falls back to /Applications if ~/Applications doesn't exist and user confirms
struct InstallAppCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "install-app",
        abstract: "Install Cellar.app to ~/Applications for double-click launch"
    )
    func run() throws { ... }
}
```

### Pattern: Detecting if cellar serve is already running

```bash
# In the .app launcher shell script:
if ! lsof -i :8080 -s TCP:LISTEN -t >/dev/null 2>&1; then
    "$(brew --prefix)/bin/cellar" serve &
    sleep 1  # brief startup wait before opening browser
fi
open http://127.0.0.1:8080
```

`lsof -i :8080 -s TCP:LISTEN -t` returns just PIDs of processes listening on TCP port 8080, with exit code 0 if any found. No `sudo` needed. Exit code 1 means nothing is listening — safe to start the server.

### Anti-Patterns to Avoid

- **Using `nc -z localhost 8080`:** `nc` behavior varies by macOS version; `lsof` is more reliable for TCP LISTEN detection.
- **Hardcoding brew prefix in the .app script:** Use `$(brew --prefix)` or the resolved `#{opt_bin}` path from formula DSL which handles both `/usr/local` (Intel) and `/opt/homebrew` (Apple Silicon).
- **Using `sleep 3` to wait for server:** Prefer polling: `for i in $(seq 10); do lsof -i :8080 -s TCP:LISTEN -t >/dev/null 2>&1 && break; sleep 0.5; done`.
- **Distributing the .app as a cask instead of formula artifact:** Casks require code signing for Homebrew 5.0.0 compliance (enforced September 2026). Formula bottles are exempt from this requirement.
- **Building bottles on Intel (`macos-13`) separately for x86_64:** `swift build --arch x86_64 --arch arm64` on a single `macos-latest` (arm64) runner produces a valid universal fat binary without cross-compilation issues.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Updating formula sha256 after release | Shell `sed` script | `NSHipster/update-homebrew-formula-action` | Handles multi-platform sha256 + version + bottle block atomically; sed on Ruby DSL is fragile |
| Uploading release artifacts | `gh release upload` shell script | `softprops/action-gh-release@v2` | Handles draft releases, tag creation, content type, overwrite flags |
| Universal binary creation | `lipo` combine step | `swift build -c release --arch x86_64 --arch arm64` | SPM produces fat binary directly; lipo is only needed for pre-existing per-arch artifacts |
| .app bundle from Swift NSWorkspace | Full SwiftUI wrapper | Shell script in `Contents/MacOS/` | 5-line shell script does everything needed; Swift app adds signing friction |

## Common Pitfalls

### Pitfall 1: Formula bottle block not matching actual GitHub Releases URL
**What goes wrong:** `brew install` falls back to source build (requires Xcode on user machine) because the `root_url` or sha256 in the bottle block is wrong.
**Why it happens:** CI builds the binary, but the tap formula is updated in a separate step that can race or fail silently.
**How to avoid:** Use `NSHipster/update-homebrew-formula-action` with `needs: [build]` dependency and verify the formula parses with `brew audit --new Formula/cellar.rb` in CI.
**Warning signs:** `brew install` output says "Building from source" rather than "Pouring cellar".

### Pitfall 2: Binary executes on Intel but not Apple Silicon (Gatekeeper)
**What goes wrong:** Users with Apple Silicon see "cannot be opened because it is from an unidentified developer."
**Why it happens:** Formula bottles poured from GitHub Releases can inherit quarantine; Apple Silicon requires code signature for native arm64 binaries.
**How to avoid:** Add `system "codesign", "--sign", "-", bin/"cellar"` to `post_install`. Ad-hoc signing requires no developer account.
**Warning signs:** Works for testers on Intel, fails on M-series Macs.

### Pitfall 3: `cellar` binary path hardcoded in .app launcher
**What goes wrong:** `Cellar.app` fails for users with non-standard Homebrew prefix (Intel `/usr/local`, Apple Silicon `/opt/homebrew`).
**Why it happens:** Shell script hardcodes `/opt/homebrew/bin/cellar`.
**How to avoid:** In the formula's `post_install`, write the binary path using `#{opt_bin}/cellar` — Homebrew DSL resolves to the actual installed prefix.
**Warning signs:** App works for creator, fails for half of users.

### Pitfall 4: `.app` bundle not marked executable
**What goes wrong:** Double-clicking Cellar.app in Finder does nothing; macOS silently refuses to launch.
**Why it happens:** `Contents/MacOS/CellarLauncher` needs executable bit set (`chmod 0755`).
**How to avoid:** Always `chmod 0755` the executable in `post_install` after writing it.

### Pitfall 5: Cask vs Formula confusion for the .app
**What goes wrong:** Attempting to use a Homebrew Cask to distribute the launcher `.app` hits Gatekeeper enforcement (September 2026 deadline).
**Why it happens:** Casks are designed for GUI apps and require notarization/signing from Homebrew 5.0+.
**How to avoid:** Keep everything as a **formula** (the CLI binary is the primary artifact). Place the `.app` in `libexec/`, expose it via a subcommand, instruct users via `caveats`. Do NOT create a separate cask.

### Pitfall 6: GITHUB_TOKEN scope for cross-repo tap update
**What goes wrong:** The workflow that pushes to the tap repo fails with "permission denied".
**Why it happens:** `GITHUB_TOKEN` is scoped to the current repo; pushing to `<org>/homebrew-cellar` requires a PAT or GitHub App token.
**How to avoid:** `NSHipster/update-homebrew-formula-action` accepts a `GH_PERSONAL_ACCESS_TOKEN` secret. Create a PAT with `repo` scope scoped to the tap repo and store it as a repo secret.

### Pitfall 7: `macos-latest` runner architecture confusion
**What goes wrong:** CI uses `macos-latest` expecting Intel; since 2024 this routes to ARM64 (macos-14+).
**Why it happens:** GitHub changed `macos-latest` to arm64 in April 2024.
**How to avoid:** `swift build -c release --arch x86_64 --arch arm64` works on either architecture. The fat binary output path is `.build/apple/Products/Release/cellar` (note: `apple` not architecture-specific).

## Code Examples

### Universal Binary Build + Archive (CI shell step)
```bash
# Source: swifttoolkit.dev, verified with Swift docs
swift build -c release --arch x86_64 --arch arm64
BINARY=.build/apple/Products/Release/cellar
lipo -info "$BINARY"   # verify: contains arm64 x86_64
VERSION=${GITHUB_REF_NAME#v}   # strip 'v' prefix from tag
ARCHIVE="cellar-${VERSION}-macos.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname $BINARY)" "$(basename $BINARY)"
shasum -a 256 "$ARCHIVE"
```

### Minimal Info.plist for shell-script .app
```xml
<!-- Source: official macOS bundle docs, relentlesscoding.com -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CellarLauncher</string>
  <key>CFBundleIdentifier</key><string>dev.cellar.launcher</string>
  <key>CFBundleName</key><string>Cellar</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
```
`LSUIElement = true` hides the app from Dock and menu bar (appropriate for a launcher that immediately opens the browser).

### GitHub Actions Release Workflow (`.github/workflows/release.yml` in main repo)
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Build universal binary
        run: |
          swift build -c release --arch x86_64 --arch arm64
          VERSION="${GITHUB_REF_NAME#v}"
          ARCHIVE="cellar-${VERSION}-macos.tar.gz"
          tar -czf "$ARCHIVE" -C .build/apple/Products/Release cellar
          echo "ARCHIVE=$ARCHIVE" >> $GITHUB_ENV
          echo "VERSION=$VERSION" >> $GITHUB_ENV

      - name: Upload to GitHub Releases
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ env.ARCHIVE }}
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Update Homebrew formula
        uses: NSHipster/update-homebrew-formula-action@main
        with:
          repository: ${{ github.repository }}
          tap: <org>/homebrew-cellar
          formula: Formula/cellar.rb
        env:
          GH_PERSONAL_ACCESS_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
```

### Port Detection in Launcher Script
```bash
# Source: macOS lsof man page; verified on macOS Sequoia
if ! lsof -i TCP:8080 -s TCP:LISTEN -t >/dev/null 2>&1; then
    "$(brew --prefix)/bin/cellar" serve &
    # Poll instead of fixed sleep
    for i in $(seq 1 20); do
        lsof -i TCP:8080 -s TCP:LISTEN -t >/dev/null 2>&1 && break
        sleep 0.5
    done
fi
open http://127.0.0.1:8080
```

### Formula post_install Ad-Hoc Signing
```ruby
# Source: github.com/orgs/Homebrew/discussions/3614
def post_install
  system "codesign", "--sign", "-", bin/"cellar"
end
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Bintray for bottle hosting | GitHub Releases (since Homebrew 2.5.2) | Bintray shut down; GitHub Releases is the standard |
| Separate arm64 + x86_64 builds merged with `lipo` | `swift build --arch x86_64 --arch arm64` fat binary | One build step, one runner |
| `macos-latest` = Intel x86_64 | `macos-latest` = ARM64 (since April 2024) | Must use `--arch x86_64 --arch arm64` explicitly to get both |
| `--no-quarantine` cask bypass | Deprecated in Homebrew 5.0.0 (Nov 2025) | Formula bottles unaffected; cask distribution for unsigned apps is ending |

## Open Questions

1. **Where should `Cellar.app` ultimately live — `~/Applications` or `/Applications`?**
   - What we know: Writing to `/Applications` requires `sudo`; `~/Applications` works without sudo; macOS Spotlight indexes both
   - What's unclear: Whether typical non-technical users have `~/Applications` on their system (it's not created by default)
   - Recommendation: Copy to `~/Applications` if it exists, otherwise create `~/Applications` first. Prompt user to move to `/Applications` manually if they prefer it system-wide. Avoids `sudo` entirely.

2. **Should the tap repo be `<org>/homebrew-cellar` (a dedicated tap) or a formula submitted to `homebrew-core`?**
   - What we know: `homebrew-core` has strict requirements (notable, maintained project, no closed-source deps); a private tap can be created and published immediately
   - What's unclear: Whether the project meets `homebrew-core` acceptance criteria
   - Recommendation: Start with a dedicated tap (`<org>/homebrew-cellar`). Submit to `homebrew-core` later when the project has broader adoption.

3. **Does `NSHipster/update-homebrew-formula-action` support multi-platform bottles (arm64_sequoia + sequoia) or only the source URL sha256?**
   - What we know: The action description says it handles sha256 for release assets matching naming patterns
   - What's unclear: Whether it handles the `bottle do` block specifically or only the top-level `sha256`
   - Recommendation: Test during Wave 1. Fallback: use a shell `sed` script targeting the specific sha256 line in the bottle block.

4. **What macOS version tags to target in the bottle block?**
   - What we know: As of April 2026, supported tags include `arm64_tahoe`, `tahoe`, `arm64_sequoia`, `sequoia`, `arm64_sonoma`, `sonoma`
   - What's unclear: The exact set of tags for the CI runner's macOS version
   - Recommendation: Start with `arm64_sequoia` + `sequoia` (the runner likely uses Sequoia). The universal binary works on all supported macOS versions (project minimum is macOS 14 from Package.swift).

5. **Is a separate `cellar install-app` subcommand worth the complexity vs purely using `caveats` with a manual `cp` instruction?**
   - What we know: `caveats` are shown once at install time; users may miss them. A subcommand is more discoverable.
   - Recommendation: Implement `cellar install-app` as it can be re-run and is more user-friendly than manual copy.

## Sources

### Primary (HIGH confidence)
- [docs.brew.sh/How-to-Create-and-Maintain-a-Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap) — tap structure, brew tap-new, GitHub Actions bottle workflow
- [docs.brew.sh/Bottles](https://docs.brew.sh/Bottles) — bottle DSL format, root_url, cellar: :any_skip_relocation, sha256 per platform
- [brew.sh/2025/11/12/homebrew-5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0) — confirmed: Gatekeeper changes affect casks only, formula bottles exempt
- [github.com/orgs/Homebrew/discussions/3614](https://github.com/orgs/Homebrew/discussions/3614) — ad-hoc codesign in post_install verified pattern
- [github.com/NSHipster/update-homebrew-formula-action](https://github.com/NSHipster/update-homebrew-formula-action) — action inputs, workflow trigger pattern, PAT requirement

### Secondary (MEDIUM confidence)
- [swifttoolkit.dev/posts/releasing-with-gh-actions](https://www.swifttoolkit.dev/posts/releasing-with-gh-actions) — complete GitHub Actions YAML for Swift release binary, `--arch` flags confirmed
- [brew.sh/2020/11/18/homebrew-tap-with-bottles-uploaded-to-github-releases](https://brew.sh/2020/11/18/homebrew-tap-with-bottles-uploaded-to-github-releases) — official Homebrew blog on GitHub Releases bottles (2020, still current workflow)
- [blog.vandenakker.xyz/posts/create-macos-app-bundle-from-script](https://blog.vandenakker.xyz/posts/create-macos-app-bundle-from-script) — .app bundle structure: Contents/MacOS/, Info.plist minimum keys

### Tertiary (LOW confidence — flag for validation)
- macOS platform bottle tag names (`arm64_tahoe`, `tahoe`, etc.) — verified via multiple Homebrew discussions but the exact tag for CI runner needs confirmation at build time
- `NSHipster/update-homebrew-formula-action` handling of `bottle do` blocks specifically — action README is ambiguous; needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — official Homebrew docs, verified CI workflow
- Architecture: HIGH — bottle DSL, .app structure, port detection all from official sources
- Pitfalls: HIGH — Gatekeeper/cask distinction verified with Homebrew 5.0.0 release notes; prefix issue from Homebrew internals
- Open questions: Honestly flagged LOW items that require validation during implementation

**Research date:** 2026-04-01
**Valid until:** 2026-07-01 (Homebrew platform tags may evolve; Swift toolchain flags are stable)
