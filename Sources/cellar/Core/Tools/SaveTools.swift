import Foundation

// MARK: - Save Tools Extension

extension AgentTools {

    // MARK: 10. save_recipe

    func saveRecipe(input: JSONValue) -> String {
        guard let name = input["name"]?.asString, !name.isEmpty else {
            return jsonResult(["error": "name is required"])
        }
        let notes = input["notes"]?.asString

        // Build recipe from current accumulated state
        let executableFilename = URL(fileURLWithPath: executablePath).lastPathComponent

        let recipe = Recipe(
            id: gameId,
            name: name,
            version: "1.0.0",
            source: "ai-agent",
            executable: executableFilename,
            wineTested: nil,
            environment: accumulatedEnv,
            registry: [],
            launchArgs: [],
            notes: notes,
            setupDeps: installedDeps.isEmpty ? nil : Array(installedDeps).sorted(),
            installDir: nil,
            retryVariants: nil
        )

        do {
            try RecipeEngine.saveUserRecipe(recipe)
            let recipePath = CellarPaths.userRecipeFile(for: gameId).path
            return jsonResult([
                "status": "ok",
                "recipe_path": recipePath,
                "game_id": gameId,
                "environment_vars_saved": accumulatedEnv.count
            ])
        } catch {
            return jsonResult(["error": "Failed to save recipe: \(error.localizedDescription)"])
        }
    }

    // MARK: 15. query_successdb

    func querySuccessdb(input: JSONValue) -> String {
        // Priority order: game_id (exact), tags, engine, graphics_api, symptom

        if let queryGameId = input["game_id"]?.asString, !queryGameId.isEmpty {
            if let record = SuccessDatabase.queryByGameId(queryGameId) {
                let dict = successRecordToDict(record)
                return jsonResult(["query_type": "game_id", "matches": [dict]])
            } else {
                return jsonResult(["query_type": "game_id", "matches": [] as [Any], "note": "No record found for game_id '\(queryGameId)'"])
            }
        }

        if let tagsArray = input["tags"]?.asArray {
            let tags = tagsArray.compactMap { $0.asString }
            if !tags.isEmpty {
                let records = Array(SuccessDatabase.queryByTags(tags).prefix(5))
                let dicts = records.map { successRecordToDict($0) }
                return jsonResult(["query_type": "tags", "matches": dicts])
            }
        }

        if let engine = input["engine"]?.asString, !engine.isEmpty {
            let records = Array(SuccessDatabase.queryByEngine(engine).prefix(5))
            let dicts = records.map { successRecordToDict($0) }
            return jsonResult(["query_type": "engine", "matches": dicts])
        }

        if let api = input["graphics_api"]?.asString, !api.isEmpty {
            let records = Array(SuccessDatabase.queryByGraphicsApi(api).prefix(5))
            let dicts = records.map { successRecordToDict($0) }
            return jsonResult(["query_type": "graphics_api", "matches": dicts])
        }

        if let symptom = input["symptom"]?.asString, !symptom.isEmpty {
            let results = Array(SuccessDatabase.queryBySymptom(symptom).prefix(3))
            let dicts: [[String: Any]] = results.map { (record, score) in
                var dict = successRecordToDict(record)
                dict["relevance_score"] = score
                return dict
            }
            return jsonResult(["query_type": "symptom", "matches": dicts])
        }

        if let similarGames = input["similar_games"]?.asObject {
            let engine = similarGames["engine"]?.asString
            let graphicsApi = similarGames["graphics_api"]?.asString
            let tags = similarGames["tags"]?.asArray?.compactMap { $0.asString } ?? []
            let symptom = similarGames["symptom"]?.asString

            let results = SuccessDatabase.queryBySimilarity(
                engine: engine, graphicsApi: graphicsApi, tags: tags, symptom: symptom
            )
            let dicts: [[String: Any]] = results.map { (record, score) in
                var dict = successRecordToDict(record)
                dict["similarity_score"] = score
                return dict
            }
            return jsonResult(["query_type": "similar_games", "matches": dicts])
        }

        return jsonResult(["error": "No query parameters provided. Specify game_id, tags, engine, graphics_api, symptom, or similar_games."])
    }

    // MARK: 16. save_success

    func saveSuccess(input: JSONValue) -> String {
        guard let gameName = input["game_name"]?.asString, !gameName.isEmpty else {
            return jsonResult(["error": "game_name is required"])
        }

        let exeFilename = URL(fileURLWithPath: executablePath).lastPathComponent
        let executableInfo = ExecutableInfo(path: exeFilename, type: "unknown", peImports: nil)

        let workingDirNotes = input["working_directory_notes"]?.asString
        let workingDir: WorkingDirectoryInfo? = workingDirNotes != nil
            ? WorkingDirectoryInfo(requirement: "must_be_exe_parent", notes: workingDirNotes)
            : nil

        let dllOverrides: [DLLOverrideRecord] = (input["dll_overrides"]?.asArray ?? []).compactMap { item in
            guard let dll = item["dll"]?.asString, let mode = item["mode"]?.asString else { return nil }
            return DLLOverrideRecord(dll: dll, mode: mode, placement: item["placement"]?.asString, source: item["source"]?.asString)
        }

        let gameConfigFiles: [GameConfigFile] = (input["game_config_files"]?.asArray ?? []).compactMap { item in
            guard let path = item["path"]?.asString, let purpose = item["purpose"]?.asString else { return nil }
            var settings: [String: String]? = nil
            if let settingsObj = item["critical_settings"]?.asObject {
                settings = [:]
                for (k, v) in settingsObj {
                    if let str = v.asString { settings?[k] = str }
                }
            }
            return GameConfigFile(path: path, purpose: purpose, criticalSettings: settings)
        }

        let registryRecords: [RegistryRecord] = (input["registry"]?.asArray ?? []).compactMap { item in
            guard let key = item["key"]?.asString,
                  let valueName = item["value_name"]?.asString,
                  let data = item["data"]?.asString else { return nil }
            return RegistryRecord(key: key, valueName: valueName, data: data, purpose: item["purpose"]?.asString)
        }

        let gameSpecificDlls: [GameSpecificDLL] = (input["game_specific_dlls"]?.asArray ?? []).compactMap { item in
            guard let filename = item["filename"]?.asString,
                  let source = item["source"]?.asString,
                  let placement = item["placement"]?.asString else { return nil }
            return GameSpecificDLL(filename: filename, source: source, placement: placement, version: item["version"]?.asString)
        }

        let pitfalls: [PitfallRecord] = (input["pitfalls"]?.asArray ?? []).compactMap { item in
            guard let symptom = item["symptom"]?.asString,
                  let cause = item["cause"]?.asString,
                  let fix = item["fix"]?.asString else { return nil }
            return PitfallRecord(symptom: symptom, cause: cause, fix: fix, wrongFix: item["wrong_fix"]?.asString)
        }

        let tags: [String] = (input["tags"]?.asArray ?? []).compactMap { $0.asString }

        let formatter = ISO8601DateFormatter()
        let verifiedAt = formatter.string(from: Date())

        let record = SuccessRecord(
            schemaVersion: 1,
            gameId: gameId,
            gameName: gameName,
            gameVersion: input["game_version"]?.asString,
            source: input["source"]?.asString,
            engine: input["engine"]?.asString,
            graphicsApi: input["graphics_api"]?.asString,
            verifiedAt: verifiedAt,
            wineVersion: nil,
            bottleType: input["bottle_type"]?.asString,
            os: nil,
            executable: executableInfo,
            workingDirectory: workingDir,
            environment: accumulatedEnv,
            dllOverrides: dllOverrides,
            gameConfigFiles: gameConfigFiles,
            registry: registryRecords,
            gameSpecificDlls: gameSpecificDlls,
            pitfalls: pitfalls,
            resolutionNarrative: input["resolution_narrative"]?.asString,
            tags: tags
        )

        do {
            try SuccessDatabase.save(record)
            let savedPath = CellarPaths.successdbFile(for: gameId).path

            // Backward compatibility: also save as user recipe
            let recipeExeName = URL(fileURLWithPath: executablePath).lastPathComponent
            let recipe = Recipe(
                id: gameId,
                name: gameName,
                version: "1.0.0",
                source: "ai-agent",
                executable: recipeExeName,
                wineTested: nil,
                environment: accumulatedEnv,
                registry: [],
                launchArgs: [],
                notes: input["resolution_narrative"]?.asString,
                setupDeps: installedDeps.isEmpty ? nil : Array(installedDeps).sorted(),
                installDir: nil,
                retryVariants: nil
            )
            try? RecipeEngine.saveUserRecipe(recipe)

            return jsonResult([
                "status": "ok",
                "saved_to": savedPath,
                "game_id": gameId,
                "environment_vars": accumulatedEnv.count,
                "dll_overrides": dllOverrides.count,
                "pitfalls": pitfalls.count,
                "tags": tags
            ])
        } catch {
            return jsonResult(["error": "Failed to save success record: \(error.localizedDescription)"])
        }
    }

    // MARK: - Success Record Helper

    /// Convert a SuccessRecord to a dictionary for JSON output via jsonResult.
    func successRecordToDict(_ record: SuccessRecord) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(record),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["game_id": record.gameId, "game_name": record.gameName]
        }
        return dict
    }
}
