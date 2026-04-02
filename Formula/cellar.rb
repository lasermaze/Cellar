# This formula lives in the tap repo (cellar-community/homebrew-cellar) at Formula/cellar.rb.
# It is stored here in the main repo as a template; CI uses NSHipster/update-homebrew-formula-action
# to keep the sha256 and version in the tap repo in sync after each tagged release.
class Cellar < Formula
  desc "AI-powered Wine launcher for old Windows games on macOS"
  homepage "https://github.com/cellar-community/cellar"
  url "https://github.com/cellar-community/cellar/releases/download/vPLACEHOLDER/cellar-PLACEHOLDER-macos.tar.gz"
  sha256 "PLACEHOLDER"
  version "PLACEHOLDER"

  bottle do
    root_url "https://github.com/cellar-community/cellar/releases/download/vPLACEHOLDER"
    cellar :any_skip_relocation
    sha256 arm64_sequoia: "PLACEHOLDER"
    sha256 sequoia:       "PLACEHOLDER"
  end

  def install
    bin.install "cellar"
  end

  def post_install
    # Ad-hoc codesign so the binary executes on Apple Silicon without Gatekeeper quarantine
    system "codesign", "--sign", "-", bin/"cellar"

    # Build a minimal Cellar.app launcher inside libexec so it can be copied to
    # ~/Applications by running `cellar install-app` (see caveats below).
    app_dir = libexec/"Cellar.app/Contents/MacOS"
    app_dir.mkpath

    (libexec/"Cellar.app/Contents/Info.plist").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key><string>CellarLauncher</string>
        <key>CFBundleIdentifier</key><string>dev.cellar.launcher</string>
        <key>CFBundleName</key><string>Cellar</string>
        <key>CFBundleVersion</key><string>#{version}</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSUIElement</key><true/>
      </dict>
      </plist>
    XML

    (app_dir/"CellarLauncher").write <<~SH
      #!/bin/bash
      # Start cellar serve if not already listening on port 8080, then open the web UI.
      CELLAR_BIN="#{opt_bin}/cellar"
      if ! lsof -i TCP:8080 -s TCP:LISTEN -t >/dev/null 2>&1; then
        "$CELLAR_BIN" serve &
        # Poll up to 10 seconds (20 x 0.5 s) for the server to accept connections
        for i in $(seq 1 20); do
          lsof -i TCP:8080 -s TCP:LISTEN -t >/dev/null 2>&1 && break
          sleep 0.5
        done
      fi
      open http://127.0.0.1:8080
    SH

    chmod 0755, app_dir/"CellarLauncher"
  end

  def caveats
    <<~EOS
      Cellar.app has been built in:
        #{opt_libexec}/Cellar.app

      To add it to your Applications folder for double-click launching, run:
        cellar install-app

      This copies Cellar.app to ~/Applications without requiring sudo.
    EOS
  end

  test do
    system "#{bin}/cellar", "--version"
  end
end
