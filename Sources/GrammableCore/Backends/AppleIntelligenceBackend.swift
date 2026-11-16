// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device foundation model (macOS 26+). Free, private and offline.
/// Compiled in only when building with an SDK that ships the FoundationModels framework
/// (Xcode 26 or later); older toolchains build a stub that reports "unavailable".
public struct AppleIntelligenceBackend: AIBackend {
    public let id = BackendID.apple

    public init() {}

    public func checkAvailability() async -> BackendStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability { return .available("Apple on-device model") }
            return .missing("Apple Intelligence is unavailable: \(String(describing: availability)).")
        }
        return .missing("Requires macOS 26 or later.")
        #else
        return .missing("This build of Grammable was compiled without Apple Intelligence support (needs Xcode 26+). \(id.setupHint)")
        #endif
    }

    public func complete(_ request: AIRequest) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw BackendError.unavailable("Apple Intelligence is not available on this Mac. \(id.setupHint)")
            }
            let session = LanguageModelSession(instructions: PromptBuilder.systemPrompt)
            let response = try await session.respond(
                to: PromptBuilder.userPrompt(instructions: request.instructions, text: request.text)
            )
            return response.content
        }
        #endif
        throw BackendError.unavailable("Apple Intelligence requires macOS 26 or later. \(id.setupHint)")
    }
}
