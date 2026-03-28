import Foundation

struct CompanionFile {
    let filename: String
    let content: String
}

struct KnownDLL {
    let name: String              // "cnc-ddraw" — matches WineFix.placeDLL argument
    let dllFileName: String       // "ddraw.dll" — file to extract and place
    let githubOwner: String       // "FunkyFr3sh"
    let githubRepo: String        // "cnc-ddraw"
    let assetPattern: String      // "cnc-ddraw.zip" — asset name to match in release
    let description: String
    let requiredOverrides: [String: String]  // e.g. ["ddraw": "n,b"] — WINEDLLOVERRIDES needed
    let companionFiles: [CompanionFile]      // config files placed alongside the DLL
    let preferredTarget: DLLPlacementTarget  // where this DLL should be placed
    let isSystemDLL: Bool                    // whether this is a system-level DLL replacement
    let variants: [String: String]           // game-specific DLL variant overrides
}

struct KnownDLLRegistry {
    static let registry: [KnownDLL] = [
        KnownDLL(
            name: "cnc-ddraw",
            dllFileName: "ddraw.dll",
            githubOwner: "FunkyFr3sh",
            githubRepo: "cnc-ddraw",
            assetPattern: "cnc-ddraw.zip",
            description: "DirectDraw replacement for classic 2D games via OpenGL/D3D9",
            requiredOverrides: ["ddraw": "n,b"],
            companionFiles: [
                CompanionFile(
                    filename: "ddraw.ini",
                    content: "[ddraw]\nrenderer=opengl\nfullscreen=true\nhandlemouse=true\nadjmouse=true\ndevmode=0\nmaxgameticks=0\nnonexclusive=false\nsinglecpu=true"
                )
            ],
            preferredTarget: .syswow64,
            isSystemDLL: true,
            variants: [:]
        )
    ]

    /// Find a known DLL by name. Returns nil for unknown DLLs.
    static func find(name: String) -> KnownDLL? {
        registry.first { $0.name == name.lowercased() }
    }
}
