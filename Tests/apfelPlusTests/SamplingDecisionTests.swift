import Foundation
import ApfelCore

func runSamplingDecisionTests() {
    // #168: temperature == 0 with no explicit top_p -> deterministic greedy.
    test("resolve maps temperature:0 (no top_p) to greedy") {
        let decision = SamplingDecision.resolve(temperature: 0, topP: nil, seed: nil)
        try assertEqual(decision, .greedy)
    }

    test("resolve maps temperature:0 with a seed (no top_p) to greedy") {
        let decision = SamplingDecision.resolve(temperature: 0, topP: nil, seed: 42)
        try assertEqual(decision, .greedy)
    }

    // #168: top_p present -> nucleus(probabilityThreshold:, seed:).
    test("resolve maps top_p to nucleus carrying the seed") {
        let decision = SamplingDecision.resolve(temperature: nil, topP: 0.9, seed: 7)
        try assertEqual(decision, .nucleus(probabilityThreshold: 0.9, seed: 7))
    }

    test("resolve maps top_p to nucleus with nil seed when no seed given") {
        let decision = SamplingDecision.resolve(temperature: 0.7, topP: 0.5, seed: nil)
        try assertEqual(decision, .nucleus(probabilityThreshold: 0.5, seed: nil))
    }

    // top_p takes precedence over temperature:0 (explicit nucleus wins over greedy).
    test("resolve prefers top_p over temperature:0") {
        let decision = SamplingDecision.resolve(temperature: 0, topP: 0.8, seed: nil)
        try assertEqual(decision, .nucleus(probabilityThreshold: 0.8, seed: nil))
    }

    // Existing seed-only behavior is preserved: topK(top: 50, seed:).
    test("resolve preserves seed-only top-k(50) behavior") {
        let decision = SamplingDecision.resolve(temperature: nil, topP: nil, seed: 99)
        try assertEqual(decision, .topK(top: 50, seed: 99))
    }

    test("resolve preserves seed-only top-k(50) with a non-zero temperature") {
        let decision = SamplingDecision.resolve(temperature: 0.7, topP: nil, seed: 99)
        try assertEqual(decision, .topK(top: 50, seed: 99))
    }

    // Nothing specified -> model default.
    test("resolve returns defaultMode when nothing is specified") {
        let decision = SamplingDecision.resolve(temperature: nil, topP: nil, seed: nil)
        try assertEqual(decision, .defaultMode)
    }

    test("resolve returns defaultMode for a non-zero temperature with no seed/top_p") {
        let decision = SamplingDecision.resolve(temperature: 0.7, topP: nil, seed: nil)
        try assertEqual(decision, .defaultMode)
    }
}
