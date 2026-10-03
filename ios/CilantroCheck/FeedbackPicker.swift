import SwiftData
import SwiftUI

/// "Was there cilantro?" buttons, shown on the result screen and in history.
/// Tapping the selected answer again clears it.
struct FeedbackPicker: View {
    @Bindable var record: CheckRecord

    var body: some View {
        VStack(spacing: 8) {
            Text("After eating: was there cilantro?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Feedback.allCases, id: \.self) { option in
                    let selected = record.feedback == option
                    Button {
                        record.feedback = selected ? nil : option
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: option.systemImage)
                            Text(option.title).font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : .secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let right = record.modelWasRight {
                Text(right ? "The model got this one right." : "The model got this one wrong. Thanks, this helps retraining.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
