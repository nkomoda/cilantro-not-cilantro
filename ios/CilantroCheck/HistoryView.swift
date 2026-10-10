import SwiftData
import SwiftUI

/// Checks from the last 7 days (plus older answered ones not exported yet), newest first, grouped by day.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CheckRecord.date, order: .reverse) private var records: [CheckRecord]

    @State private var exportDocument: ZipDocument?
    @State private var exportingRecords: [CheckRecord] = []
    @State private var showExporter = false
    @State private var exportError: String?

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No checks yet",
                    systemImage: "clock",
                    description: Text("Photos you check are kept here for \(History.retentionDays) days.")
                )
            } else {
                List {
                    Section {
                        summary
                    }
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(dayTitle(group.day)) {
                            ForEach(group.records) { record in
                                NavigationLink(value: record) {
                                    HistoryRow(record: record)
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { group.records[$0] }.forEach(context.delete)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: CheckRecord.self) { HistoryDetailView(record: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomeButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export", systemImage: "square.and.arrow.up", action: export)
                    .disabled(pendingExport.isEmpty)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: TrainingExport.defaultFilename
        ) { result in
            switch result {
            case .success:
                exportingRecords.forEach { $0.exportedAt = .now }
                History.prune(context)
            case .failure(let error):
                exportError = error.localizedDescription
            }
            exportingRecords = []
            exportDocument = nil
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var pendingExport: [CheckRecord] { records.filter(\.needsExport) }

    @ViewBuilder
    private var summary: some View {
        let judged = records.compactMap(\.modelWasRight)
        if judged.isEmpty {
            Text("After eating, answer \"was there cilantro?\" on a check to see how accurate the model is.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            let right = judged.filter { $0 }.count
            LabeledContent("Model accuracy") {
                Text("\(right) of \(judged.count) right (\(Double(right) / Double(judged.count), format: .percent.precision(.fractionLength(0))))")
            }
        }
        if !pendingExport.isEmpty {
            Label("\(pendingExport.count) answered photo\(pendingExport.count == 1 ? "" : "s") ready to export for training", systemImage: "square.and.arrow.up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func export() {
        let records = pendingExport
        do {
            exportDocument = ZipDocument(data: try TrainingExport.makeZip(records))
            exportingRecords = records
            showExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var groupedByDay: [(day: Date, records: [CheckRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

private struct HistoryRow: View {
    let record: CheckRecord

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = record.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                ResultLabel(prediction: record.prediction)
                    .font(.headline)
                Text("\(record.date.formatted(.dateTime.hour().minute())) · \(answerStatus)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var answerStatus: String {
        switch (record.feedback, record.modelWasRight) {
        case (nil, _): "Not answered"
        case (.hidden, _): "Hidden cilantro"
        case (_, true?): "Model was right"
        case (_, false?): "Model was wrong"
        default: ""
        }
    }
}

private struct HistoryDetailView: View {
    let record: CheckRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = record.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                ResultLabel(prediction: record.prediction)
                    .font(.title2.bold())
                Text("Cilantro probability: \(record.cilantroProbability, format: .percent.precision(.fractionLength(0)))")
                    .foregroundStyle(.secondary)
                Text(record.date, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .foregroundStyle(.secondary)
                FeedbackPicker(record: record)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomeButton()
            }
        }
    }
}

/// "🌿 Cilantro detected" / "✅ No cilantro", shared by the main screen and history.
struct ResultLabel: View {
    let prediction: Prediction

    var body: some View {
        Text(prediction.hasCilantro ? "🌿 Cilantro detected" : "✅ No cilantro")
    }
}
