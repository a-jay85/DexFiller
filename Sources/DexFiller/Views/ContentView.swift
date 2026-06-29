import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ProcessingViewModel()
    @State private var isDragTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("DexFiller")
                    .font(.title2.bold())
                Text("Pokemon GO Data Exporter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            List {
                if viewModel.videoURL != nil {
                    Label("Video Loaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if case .completed = viewModel.state {
                    Section("Results") {
                        if let result = viewModel.result {
                            Label("\(result.records.count) Pokemon", systemImage: "list.bullet")
                            Label("\(result.framesAnalyzed) frames", systemImage: "film")
                            if result.duplicatesRemoved > 0 {
                                Label("\(result.duplicatesRemoved) duplicates removed", systemImage: "minus.circle")
                            }
                            if !viewModel.flaggedRecords.isEmpty {
                                Button {
                                    viewModel.showingReview = true
                                } label: {
                                    Label("\(viewModel.flaggedRecords.count) need review", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer()

            if case .completed = viewModel.state {
                Button(action: viewModel.exportCSV) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch viewModel.state {
        case .idle:
            if viewModel.videoURL != nil {
                readyToProcessView
            } else {
                dropZoneView
            }

        case .processing:
            processingView

        case .completed:
            if viewModel.showingReview {
                ReviewView(
                    records: viewModel.flaggedRecords,
                    onUpdateCP: { id, cp in viewModel.updateCP(recordID: id, cp: cp) },
                    onDismiss: { viewModel.showingReview = false }
                )
            } else {
                resultsView
            }

        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                    .frame(maxWidth: 400, maxHeight: 250)

                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Drop a video file here")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Choose File") {
                        openFilePicker()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .onDrop(of: [.movie, .fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers)
            }

            Text("Supports .mov and .mp4 files")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Ready to Process

    private var readyToProcessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            if let url = viewModel.videoURL {
                Text(url.lastPathComponent)
                    .font(.title3)

                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 16) {
                Button("Change Video") {
                    openFilePicker()
                }
                .buttonStyle(.bordered)

                Button("Start Processing") {
                    viewModel.startProcessing()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.progress) {
                Text(viewModel.progressMessage)
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 400)

            Button("Cancel") {
                viewModel.cancelProcessing()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            if let result = viewModel.result {
                HStack {
                    summaryCard(title: "Pokemon", value: "\(result.records.count)", icon: "list.bullet")
                    summaryCard(title: "Avg Confidence", value: "\(Int(result.summary.averageConfidence * 100))%", icon: "chart.bar")
                    summaryCard(title: "With IVs", value: "\(result.summary.recordsWithIVs)", icon: "chart.line.uptrend.xyaxis")
                    summaryCard(title: "Time", value: String(format: "%.1fs", result.processingTime), icon: "clock")
                }
                .padding()
            }

            Divider()

            Table(viewModel.records) {
                TableColumn("Species") { record in
                    Text(record.species ?? "—")
                }
                .width(min: 80, ideal: 100)

                TableColumn("CP") { record in
                    Text(record.cp.map(String.init) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50)

                TableColumn("HP") { record in
                    Text(record.hp.map(String.init) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50)

                TableColumn("Atk") { record in
                    Text(record.attackIV.map(String.init) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 30, ideal: 35)

                TableColumn("Def") { record in
                    Text(record.defenseIV.map(String.init) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 30, ideal: 35)

                TableColumn("Sta") { record in
                    Text(record.staminaIV.map(String.init) ?? "—")
                        .monospacedDigit()
                }
                .width(min: 30, ideal: 35)

                TableColumn("IV%") { record in
                    Text(record.ivPercentage.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50)

                TableColumn("Fast Move") { record in
                    Text(record.fastMove ?? "—")
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Confidence") { record in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(confidenceColor(record.confidence))
                            .frame(width: 8, height: 8)
                        Text(String(format: "%.0f%%", record.confidence * 100))
                            .monospacedDigit()
                            .font(.caption)
                    }
                }
                .width(min: 60, ideal: 80)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Processing Error")
                .font(.title3)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Try Again") {
                viewModel.state = .idle
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func summaryCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .yellow }
        return .red
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.importVideo(from: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in
                        viewModel.importVideo(from: url)
                    }
                }
            }
            return true
        }
        return false
    }
}
