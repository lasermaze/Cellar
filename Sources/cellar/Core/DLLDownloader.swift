import Foundation

enum DLLError: Error {
    case unknownDLL(String)
    case downloadFailed(String)
    case extractionFailed
    case assetNotFound(String)
}

struct DLLDownloader {
    /// Download and cache a known DLL. Returns path to the cached DLL file.
    /// Uses GitHub REST API: GET /repos/{owner}/{repo}/releases/latest
    /// Checks cache first — only downloads if not already cached.
    static func downloadAndCache(_ dll: KnownDLL) throws -> URL {
        let cachedFile = CellarPaths.cachedDLLFile(dllName: dll.name, fileName: dll.dllFileName)

        // Check cache first
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            return cachedFile
        }

        // Create cache directory
        let cacheDir = CellarPaths.dllCacheDir(for: dll.name)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Fetch latest release from GitHub API
        let apiURL = URL(string: "https://api.github.com/repos/\(dll.githubOwner)/\(dll.githubRepo)/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        // Synchronous fetch using DispatchSemaphore (same pattern as AIService.callAPI)
        let responseData = try syncRequest(request)

        // Parse JSON to find asset download URL
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]]
        else {
            throw DLLError.downloadFailed("Failed to parse GitHub release JSON")
        }

        guard let asset = assets.first(where: { ($0["name"] as? String ?? "").contains(dll.assetPattern) }),
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString)
        else {
            throw DLLError.assetNotFound("No asset matching '\(dll.assetPattern)' in latest release")
        }

        // Download the zip file
        let zipRequest = URLRequest(url: downloadURL)
        let zipData = try syncRequest(zipRequest)

        // Write zip to temp file
        let tempZip = NSTemporaryDirectory() + UUID().uuidString + ".zip"
        let tempZipURL = URL(fileURLWithPath: tempZip)
        try zipData.write(to: tempZipURL)

        // Extract using /usr/bin/ditto (ships on all macOS, no SPM dep needed)
        let extractDir = NSTemporaryDirectory() + UUID().uuidString
        let extractDirURL = URL(fileURLWithPath: extractDir)
        try FileManager.default.createDirectory(at: extractDirURL, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", tempZipURL.path, extractDirURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw DLLError.extractionFailed
        }

        // Find the DLL file in extracted contents (may be in a subdirectory)
        let enumerator = FileManager.default.enumerator(at: extractDirURL, includingPropertiesForKeys: nil)
        var foundDLL: URL?
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.lowercased() == dll.dllFileName.lowercased() {
                foundDLL = fileURL
                break
            }
        }

        guard let dllSource = foundDLL else {
            throw DLLError.extractionFailed
        }

        // Copy to cache
        try FileManager.default.copyItem(at: dllSource, to: cachedFile)

        // Clean up temp files
        try? FileManager.default.removeItem(at: tempZipURL)
        try? FileManager.default.removeItem(at: extractDirURL)

        return cachedFile
    }

    /// Place a cached DLL into a game directory. Returns the destination path.
    static func place(cachedDLL: URL, into targetDir: URL) throws -> URL {
        let destination = targetDir.appendingPathComponent(cachedDLL.lastPathComponent)

        // Remove existing file if present (update scenario)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: cachedDLL, to: destination)
        return destination
    }

    /// Synchronous HTTP request using DispatchSemaphore (mirrors AIService pattern).
    private static func syncRequest(_ request: URLRequest) throws -> Data {
        final class ResultBox: @unchecked Sendable {
            var value: Result<Data, Error> = .failure(DLLError.downloadFailed("No response"))
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                box.value = .failure(error)
            } else if let data = data {
                let httpResponse = response as? HTTPURLResponse
                if let code = httpResponse?.statusCode, code >= 400 {
                    box.value = .failure(DLLError.downloadFailed("HTTP \(code)"))
                } else {
                    box.value = .success(data)
                }
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return try box.value.get()
    }
}
