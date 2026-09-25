@testable import App
import Foundation
import Testing

// MARK: - ExerciseImageGenerateRequest decoding

//
// Mirrors ProgramImportRequestDecodingTests — pins that the POST body decodes
// correctly under the global `.convertFromSnakeCase` decoder. None of these
// fields hit the ID/URL-acronym pitfall (no field ends in "Id"/"Url"), so no
// CodingKeys should be needed; this test is the guardrail against someone
// later adding e.g. `exerciseID` here without one.

@Suite("ExerciseImageGenerateRequestDecoding")
struct ExerciseImageRequestDecodingTests {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test func decodesFullBody() throws {
        let json = """
        {"name":"Barbell Back Squat","equipment":"barbell","muscle_group":"quads",
         "movement_pattern":"squat","instructions":"1. Set up the bar."}
        """
        let request = try decoder().decode(ExerciseImageGenerateRequest.self, from: Data(json.utf8))
        #expect(request.name == "Barbell Back Squat")
        #expect(request.equipment == "barbell")
        #expect(request.muscleGroup == "quads")
        #expect(request.movementPattern == "squat")
        #expect(request.instructions == "1. Set up the bar.")
    }

    @Test func decodesWithOptionalFieldsMissing() throws {
        let json = #"{"name":"Push-Up","equipment":"bodyweight","muscle_group":"chest"}"#
        let request = try decoder().decode(ExerciseImageGenerateRequest.self, from: Data(json.utf8))
        #expect(request.name == "Push-Up")
        #expect(request.movementPattern == nil)
        #expect(request.instructions == nil)
    }
}

// MARK: - ExerciseImageResponseDTO.ready

@Suite("ExerciseImageResponseDTO")
struct ExerciseImageResponseDTOTests {
    @Test func readyBuildsExpectedURL() {
        let dto = ExerciseImageResponseDTO.ready(slug: "barbell-back-squat", baseURL: "https://api.example.com")
        #expect(dto.slug == "barbell-back-squat")
        #expect(dto.url == "https://api.example.com/v1/exercise-images/barbell-back-squat")
        #expect(dto.status == "ready")
    }
}
