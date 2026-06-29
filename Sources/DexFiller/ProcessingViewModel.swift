import DexFillerCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProcessingViewModel: ObservableObject {
    enum State {
        case idle
        case processing
        case completed
        case error(String)
    }

    @Published var state: State = .idle
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var records: [PokemonRecord] = []
    @Published var flaggedRecords: [PokemonRecord] = []
    @Published var result: ProcessingResult?
    @Published var videoURL: URL?
    @Published var showingReview: Bool = false

    private var pipeline: ProcessingPipeline?
    private var processingTask: Task<Void, Never>?

    func importVideo(from url: URL) {
        videoURL = url
        state = .idle
        records = []
        flaggedRecords = []
        result = nil
    }

    func startProcessing() {
        guard let videoURL else { return }

        state = .processing
        progress = 0
        progressMessage = "Starting..."

        let pipeline = ProcessingPipeline()
        self.pipeline = pipeline

        let onProgress: @Sendable (ProcessingProgress) -> Void = { [weak self] progressUpdate in
            Task { @MainActor in
                self?.progress = progressUpdate.fractionComplete
                self?.progressMessage = progressUpdate.phase

                if case .extracting(let done, let total) = progressUpdate {
                    self?.progressMessage = "Extracting data (\(done)/\(total) Pokemon)"
                }
                if case .sampling(let done, let total) = progressUpdate {
                    self?.progressMessage = "Sampling frames (\(done)/\(total))"
                }
            }
        }

        processingTask = Task {
            do {
                let processingResult = try await pipeline.process(videoURL: videoURL, onProgress: onProgress)
                self.records = processingResult.records
                self.flaggedRecords = processingResult.flaggedRecords
                self.result = processingResult
                self.state = .completed
                self.progress = 1.0
                self.progressMessage = "Complete"
            } catch {
                self.state = .error(error.localizedDescription)
                self.progressMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        state = .idle
        progressMessage = "Cancelled"
    }

    func exportCSV() {
        guard !records.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = "pokemon_export.csv"
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let pipeline = ProcessingPipeline()
                    try pipeline.exportCSV(self.records, to: url)
                } catch {
                    self.state = .error("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func csvPreview(limit: Int = 5) -> String {
        guard !records.isEmpty else { return "" }
        let pipeline = ProcessingPipeline()
        let subset = Array(records.prefix(limit))
        return pipeline.formatCSV(subset)
    }
}
