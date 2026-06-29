import DexFillerCore
import SwiftUI

/// Review mode for low-confidence Pokemon entries.
/// Shows extracted data with the option to correct fields.
struct ReviewView: View {
    let records: [PokemonRecord]
    /// Commit a manual CP correction for the record with the given id.
    var onUpdateCP: (UUID, Int?) -> Void = { _, _ in }
    let onDismiss: () -> Void

    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Label("Back to Results", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Review Flagged Entries")
                    .font(.headline)

                Spacer()

                Text("\(currentIndex + 1) of \(records.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding()

            Divider()

            if records.isEmpty {
                ContentUnavailableView(
                    "No Entries to Review",
                    systemImage: "checkmark.circle",
                    description: Text("All entries have sufficient confidence.")
                )
            } else {
                // Record detail
                let record = records[currentIndex]

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Confidence banner
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Confidence: \(String(format: "%.0f%%", record.confidence * 100))")
                                .font(.headline)
                            Spacer()
                        }
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                        // Fields grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 12) {
                            fieldRow("Species", value: record.species)
                            fieldRow("Nickname", value: record.nickname)
                            CPField(cp: record.cp) { onUpdateCP(record.id, $0) }
                                .id(record.id)
                            fieldRow("HP", value: record.hp.map(String.init))
                            fieldRow("Level", value: record.level.map { String(format: "%.1f", $0) })
                            fieldRow("Attack IV", value: record.attackIV.map(String.init))
                            fieldRow("Defense IV", value: record.defenseIV.map(String.init))
                            fieldRow("Stamina IV", value: record.staminaIV.map(String.init))
                            fieldRow("IV%", value: record.ivPercentage.map { String(format: "%.1f%%", $0 * 100) })
                            fieldRow("Fast Move", value: record.fastMove)
                            fieldRow("Charged Move 1", value: record.chargedMove1)
                            fieldRow("Charged Move 2", value: record.chargedMove2)
                            fieldRow("Weight", value: record.weight.map { String(format: "%.2f kg", $0) })
                            fieldRow("Height", value: record.height.map { String(format: "%.2f m", $0) })
                            fieldRow("Catch Date", value: record.catchDate)
                            fieldRow("Catch Location", value: record.catchLocation)
                        }

                        // Tags
                        HStack(spacing: 12) {
                            tagBadge("Shiny", active: record.shiny)
                            tagBadge("Lucky", active: record.lucky)
                            tagBadge("Shadow", active: record.shadow)
                            tagBadge("Purified", active: record.purified)
                        }
                    }
                    .padding()
                }

                Divider()

                // Navigation
                HStack {
                    Button("Previous") {
                        if currentIndex > 0 { currentIndex -= 1 }
                    }
                    .disabled(currentIndex == 0)

                    Spacer()

                    Button("Next") {
                        if currentIndex < records.count - 1 { currentIndex += 1 }
                    }
                    .disabled(currentIndex >= records.count - 1)
                }
                .padding()
            }
        }
    }

    private func fieldRow(_ label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.body.monospaced())
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Editable CP field. Carries its own draft text (re-seeded per record via
    /// `.id(record.id)`) and commits on Enter or when focus leaves. Empty clears
    /// CP to nil; only digits are accepted.
    private struct CPField: View {
        let cp: Int?
        let onCommit: (Int?) -> Void

        @State private var text: String
        @FocusState private var focused: Bool

        init(cp: Int?, onCommit: @escaping (Int?) -> Void) {
            self.cp = cp
            self.onCommit = onCommit
            _text = State(initialValue: cp.map(String.init) ?? "")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("CP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                TextField("—", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($focused)
                    .onChange(of: text) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(5))
                        if digits != newValue { text = digits }
                    }
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                    .onDisappear { commit() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }

        private func commit() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            onCommit(trimmed.isEmpty ? nil : Int(trimmed))
        }
    }

    private func tagBadge(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(active ? Color.accentColor : Color.secondary.opacity(0.3)))
            .foregroundStyle(active ? .primary : .secondary)
    }
}
