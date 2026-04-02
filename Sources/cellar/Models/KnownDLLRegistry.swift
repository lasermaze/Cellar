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
        ),
        KnownDLL(
            name: "dgvoodoo2",
            dllFileName: "DDraw.dll",
            githubOwner: "dege-diorama",
            githubRepo: "dgVoodoo2",
            assetPattern: "dgVoodoo",
            description: "DirectX 1-7 and Glide to D3D11 wrapper — essential for early 3D games (1995-2002)",
            requiredOverrides: ["ddraw": "n,b"],
            companionFiles: [
                CompanionFile(
                    filename: "dgVoodoo.conf",
                    content: "[General]\nOutputAPI = direct3d11\nFullScreenMode = true\n\n[DirectX]\nDisableAndPassThru = false\nVideoCard = dgVoodoo Virtual 3D Accelerated Card\nVRAM = 256\nFiltering = appdriven\n\n[Glide]\nVideoCard = voodoo_2"
                )
            ],
            preferredTarget: .gameDir,
            isSystemDLL: false,
            variants: ["d3d8": "D3D8.dll", "d3dimm": "D3DImm.dll", "glide": "Glide2x.dll"]
        ),
        KnownDLL(
            name: "dxwrapper",
            dllFileName: "dxwrapper.dll",
            githubOwner: "elishacloud",
            githubRepo: "dxwrapper",
            assetPattern: "dxwrapper",
            description: "DirectDraw and Direct3D 1-9 compatibility wrapper with dd7to9 conversion",
            requiredOverrides: ["ddraw": "n,b", "dinput": "n,b"],
            companionFiles: [
                CompanionFile(
                    filename: "dxwrapper.ini",
                    content: "[Compatibility]\nDd7to9 = 1\nD3d8to9 = 0\n\n[dd7to9]\nEnabled = 1\nSetSwapEffect = 2\nSetResolution = 0\n\n[dinput]\nEnabled = 1"
                )
            ],
            preferredTarget: .gameDir,
            isSystemDLL: false,
            variants: [:]
        ),
        KnownDLL(
            name: "dxvk",
            dllFileName: "d3d9.dll",
            githubOwner: "doitsujin",
            githubRepo: "dxvk",
            assetPattern: "dxvk-",
            description: "Vulkan-based D3D9/10/11 implementation — requires MoltenVK (included in Gcenx Wine builds)",
            requiredOverrides: ["d3d9": "n,b", "d3d11": "n,b", "dxgi": "n,b"],
            companionFiles: [],
            preferredTarget: .syswow64,
            isSystemDLL: true,
            variants: ["d3d10": "d3d10core.dll", "d3d11": "d3d11.dll", "dxgi": "dxgi.dll"]
        )
    ]

    /// Find a known DLL by name. Returns nil for unknown DLLs.
    static func find(name: String) -> KnownDLL? {
        registry.first { $0.name == name.lowercased() }
    }
}
