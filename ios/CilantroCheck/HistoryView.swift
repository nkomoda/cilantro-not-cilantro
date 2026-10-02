import SwiftData
import SwiftUI

/// Checks from the last 7 days, newest first, grouped by day.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CheckRecord.date, order: .reverse) private var records: [CheckRecord]

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
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(dayTitle(group.day)) {
                            ForEach(group.records) { record in
                                NavigationLink {
                                    HistoryDetailView(record: record)
                                } label: {
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
        .navigationTitle("Last \(History.retentionDays) Days")
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
                Text(record.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "🌿 Cilantro detected" / "✅ No cilantro", shared by the main screen and history.
struct ResultLabel: View {
    let prediction: Prediction

    var body: some View {
        Text(prediction.hasCilantro ? "🌿 Cilantro detected" : "✅ No cilantro")
    }
}
