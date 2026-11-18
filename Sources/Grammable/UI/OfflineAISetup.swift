// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

/// Walks the user through a free, fully offline AI: install Ollama, start it, download a small model.
@MainActor
final class OfflineAISetupModel: ObservableObject {
    enum Stage: Equatable {
        case checking
        case notInstalled
        case notRunning
        case noModel
        case downloading(fraction: Double, status: String)
        case ready(models: [String])
        case failed(String)
    }

    @Published private(set) var stage: Stage = .checking
    @Published var choice = OllamaSetup.recommendedModels[0].id
    private var download: Task<Void, Never>?
    private var startedServer = false
    private let settings = AppSettings.shared

    var isDownloading: Bool {
        if case .downloading = stage { return true }
        return false
    }

    /// Re-checks Ollama. Called on appear and every few seconds while the AI Backends tab is open,
    /// so installing or opening Ollama in another window updates this card on its own.
    func refresh() {
        guard !isDownloading else { return }
        let url = settings.ollamaURL
        Task {
            let models = await OllamaSetup.installedModels(baseURL: url)
            guard !isDownloading else { return }
            if let models {
                stage = models.isEmpty ? .noModel : .ready(models: models)
            } else if case .failed = stage {
                // Keep showing the error until the user acts.
            } else {
                stage = OllamaSetup.isInstalled ? .notRunning : .notInstalled
            }
        }
    }

    func downloadOllama() {
        NSWorkspace.shared.open(OllamaSetup.downloadURL)
    }

    func startOllama() {
        if let app = OllamaSetup.appPath {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app),
                                               configuration: NSWorkspace.OpenConfiguration())
        } else if !startedServer {
            startedServer = true
            OllamaSetup.startServer()
        }
        stage = .checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }

    func downloadModel() {
        let model = choice
        let url = settings.ollamaURL
        stage = .downloading(fraction: 0, status: "Starting…")
        DiagnosticLog.log("offline AI: downloading \(model)")
        download = Task {
            do {
                try await OllamaSetup.pull(model: model, baseURL: url) { fraction, status in
                    Task { @MainActor [weak self] in
                        guard let self, self.isDownloading else { return }
                        self.stage = .downloading(fraction: fraction, status: status)
                    }
                }
                settings.setModel(model, for: .ollama)
                settings.defaultBackend = .ollama
                DiagnosticLog.log("offline AI: \(model) ready and set as default")
                stage = .ready(models: [model])
                refreshAfterDownload()
            } catch is CancellationError {
                stage = .noModel
            } catch {
                if (error as? URLError)?.code == .cancelled { stage = .noModel; return }
                DiagnosticLog.log("offline AI: download failed")
                stage = .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        stage = .noModel
    }

    func useAsDefault(model: String) {
        if settings.model(for: .ollama).isEmpty { settings.setModel(model, for: .ollama) }
        settings.defaultBackend = .ollama
    }

    func dismissError() {
        stage = .checking
        refresh()
    }

    private func refreshAfterDownload() {
        let url = settings.ollamaURL
        Task {
            if let models = await OllamaSetup.installedModels(baseURL: url), !models.isEmpty {
                stage = .ready(models: models)
            }
        }
    }
}

/// The "Free offline AI" card at the top of Settings › AI Backends.
struct OfflineAISetupView: View {
    @ObservedObject var model: OfflineAISetupModel
    @ObservedObject private var settings = AppSettings.shared
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.laptopcomputer").foregroundStyle(Brand.gradient).font(.title3)
                Text("Free offline AI").font(.headline)
                Spacer()
                stepLabel
            }
            content
        }
        .padding(.vertical, 4)
        .onChange(of: model.stage) { _ in onChange() }
    }

    @ViewBuilder private var stepLabel: some View {
        switch model.stage {
        case .notInstalled: Text("Step 1 of 3").font(.caption).foregroundStyle(.secondary)
        case .notRunning: Text("Step 2 of 3").font(.caption).foregroundStyle(.secondary)
        case .noModel, .downloading: Text("Step 3 of 3").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking for Ollama…").font(.callout) }

        case .notInstalled:
            explain("No AI on this Mac? Ollama is free and runs small AI models entirely on your Mac. Your text never leaves it, and there's no account or subscription.")
            HStack {
                Button("Download Ollama (free)") { model.downloadOllama() }.buttonStyle(.borderedProminent)
                Text("Install it, open it once, then come back here.").font(.caption).foregroundStyle(.secondary)
            }

        case .notRunning:
            explain("Ollama is installed but not running.")
            Button("Start Ollama") { model.startOllama() }.buttonStyle(.borderedProminent)

        case .noModel:
            explain("Ollama is running. Pick a model to download. You only do this once.")
            Picker("Model", selection: $model.choice) {
                ForEach(OllamaSetup.recommendedModels) { choice in
                    Text("\(choice.name) · \(choice.size) — \(choice.note)").tag(choice.id)
                }
            }
            .labelsHidden()
            Button("Download and Use") { model.downloadModel() }.buttonStyle(.borderedProminent)

        case .downloading(let fraction, let status):
            ProgressView(value: fraction)
            HStack {
                Text("\(Int(fraction * 100))% · \(status)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelDownload() }.controlSize(.small)
            }

        case .ready(let models):
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Ollama is ready with \(models.joined(separator: ", ")).").font(.callout)
                Spacer()
                if settings.defaultBackend != .ollama {
                    Button("Use as Default") { model.useAsDefault(model: models[0]) }
                } else {
                    Text("Default").font(.caption).foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            Button("Try Again") { model.dismissError() }
        }
    }

    private func explain(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
