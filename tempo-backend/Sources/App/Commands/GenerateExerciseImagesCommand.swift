import Fluent
import Vapor

// MARK: - GenerateExerciseImagesCommand

//
//   swift run App generate-exercise-images --file <path to Exercises.json> [--limit N] [--dry-run]
//
// Pre-generates the exercise-image library so the 147 built-in exercises
// don't all pay their first-generation latency (~10-30s) on some unlucky
// user's device. Skips slugs that already have a row. Sequential with a 1s
// delay between calls (gentle on the API, easy to Ctrl-C mid-run without
// losing already-generated images — each slug is its own committed row).
//
// `--dry-run` decodes the file, builds every prompt, and prints them —
// no network call, no DB write, no budget spent. Safe to run with no
// OPENAI_API_KEY at all.

struct GenerateExerciseImagesCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "file", short: "f", help: "Path to Exercises.json (default: Resources/ExerciseLibrary/Exercises.json)")
        var file: String?

        @Option(name: "limit", short: "l", help: "Max number of images to generate this run")
        var limit: Int?

        @Flag(name: "dry-run", help: "Print the prompts that would be sent; generate and store nothing")
        var dryRun: Bool

        init() {}
    }

    var help: String {
        "Pre-generates exercise images for Exercises.json, skipping slugs that already exist."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        // Default: the copy of the iOS library shipped in the image
        // (Resources/ExerciseLibrary), so this runs inside the deployed
        // container: `railway ssh -- ./app generate-exercise-images`.
        let filePath = signature.file
            ?? context.application.directory.resourcesDirectory + "ExerciseLibrary/Exercises.json"

        let entries: [LibraryExerciseEntry]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            entries = try JSONDecoder().decode([LibraryExerciseEntry].self, from: data)
        } catch {
            context.console.error("Failed to read/decode \(filePath): \(error)")
            return
        }

        context.console.info("Loaded \(entries.count) exercises from \(filePath).")

        if signature.dryRun {
            let limited = signature.limit.map { Array(entries.prefix($0)) } ?? entries
            runDryRun(entries: limited, context: context)
            return
        }

        let app = context.application
        let req = Request(application: app, on: app.eventLoopGroup.next())

        var generated = 0
        var skipped = 0
        var failed = 0
        var attempted = 0

        for entry in entries {
            let slug = ExerciseImageSlug.make(from: entry.name)

            if try await ExerciseImage.find(slug, on: app.db) != nil {
                skipped += 1
                context.console.info("skip  \(slug) (already generated)")
                continue
            }

            // --limit caps generation ATTEMPTS (not just successes) — a run
            // against an unconfigured/exhausted backend would otherwise never
            // stop, since every attempt "fails" and the counter never trips.
            if let limit = signature.limit, attempted >= limit {
                context.console.warning("Reached --limit \(limit); stopping.")
                break
            }
            attempted += 1

            do {
                _ = try await ExerciseImageService.shared.generateForLibrary(
                    name: entry.name,
                    equipment: entry.equipment,
                    muscleGroup: entry.muscleGroup,
                    movementPattern: entry.movementPattern,
                    instructions: entry.instructions,
                    on: req
                )
                generated += 1
                let costCents = generated * OpenAIImageGenerator.costCents
                context.console.success("generated \(slug) (\(generated) so far, ~\(costCents)c total)")
            } catch {
                failed += 1
                context.console.error("failed \(slug): \(error)")
            }

            try await Task.sleep(for: .seconds(1))
        }

        let costCents = generated * OpenAIImageGenerator.costCents
        context.console.success(
            "Done: generated \(generated), skipped \(skipped) (already existed), failed \(failed). Cost ~\(costCents)c."
        )
    }

    private func runDryRun(entries: [LibraryExerciseEntry], context: CommandContext) {
        for entry in entries {
            let slug = ExerciseImageSlug.make(from: entry.name)
            let prompt = ExerciseImagePrompt.build(
                name: entry.name,
                equipment: entry.equipment,
                muscleGroup: entry.muscleGroup,
                movementPattern: entry.movementPattern,
                instructions: entry.instructions
            )
            context.console.print("[\(slug)]")
            context.console.print(prompt)
            context.console.print("")
        }
        context.console.success("Dry run: \(entries.count) prompts printed. Nothing generated, nothing spent.")
    }
}

/// Minimal decode of Exercises.json — only the fields the prompt/slug need.
/// Extra JSON keys (secondaryMuscles, cues, demoAsset, ...) are ignored.
private struct LibraryExerciseEntry: Decodable {
    let name: String
    let muscleGroup: String
    let equipment: String
    let movementPattern: String?
    let instructions: String?
}
