// ============================================================================
// ModelBackend.swift - Selects which Apple Foundation Models backend serves
// a request: the on-device SystemLanguageModel or PrivateCloudComputeLanguageModel.
//
// Lives in ApfelCore (no FoundationModels import) so the parser is
// unit-testable and shared between the CLI flag and the OpenAI server's
// model-name routing.
// ============================================================================

import Foundation

/// Which Apple Foundation Models backend serves a request.
///
/// `apfel-plus` is on-device by default. Callers opt into Apple's Private Cloud
/// Compute by passing `--pcc` on the CLI or by setting the request's
/// `model` field to `apple-foundationmodel-pcc` (or the `pcc` / `apfel-plus-pcc`
/// aliases) on `/v1/chat/completions`.
public enum ModelBackend: String, Sendable, Equatable, Hashable, CustomStringConvertible {
    /// On-device SystemLanguageModel (~3B params, 4096-token context, free, offline).
    case onDevice
    /// Apple Private Cloud Compute (32K context, reasoning levels, no API keys,
    /// requires macOS 27+). Falls back to onDevice on older systems via runtime
    /// availability checks at the construction site.
    case privateCloudCompute

    /// Default backend for new sessions when the caller does not specify.
    public static let `default`: ModelBackend = .onDevice

    /// OpenAI-style model id surfaced on `/v1/models` and accepted on
    /// `/v1/chat/completions`.
    public var canonicalModelID: String {
        switch self {
        case .onDevice: return "apple-foundationmodel"
        case .privateCloudCompute: return "apple-foundationmodel-pcc"
        }
    }

    /// Short, user-facing label used in logs, `--model-info`, and `/health`.
    public var displayLabel: String {
        switch self {
        case .onDevice: return "on-device"
        case .privateCloudCompute: return "Private Cloud Compute"
        }
    }

    public var description: String { displayLabel }

    /// Parse a request's `model` field into a backend choice.
    ///
    /// Unknown values fall back to `.onDevice`: OpenAI clients routinely hard-code
    /// model ids like `gpt-4`, and apfel-plus has always served them locally rather
    /// than rejecting the request. PCC is strictly opt-in via the documented
    /// aliases.
    public static func from(modelName: String?) -> ModelBackend {
        guard let raw = modelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else {
            return .onDevice
        }
        switch raw {
        case "pcc",
             "apfel-plus-pcc",
             "apple-foundationmodel-pcc":
            return .privateCloudCompute
        default:
            return .onDevice
        }
    }
}
