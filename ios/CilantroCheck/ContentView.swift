import PhotosUI
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var prediction: Prediction?
    @State private var currentRecord: CheckRecord?
    @State private var errorMessage: String?
    @State private var isClassifying = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var path = NavigationPath()

    // Loaded once, lazily. Holds the error if the model hasn't been trained yet.
    private static let detector = Result { try CilantroDetector() }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    resultView
                }
                .padding()
            }
            // Pinned below the scrolling content so a new photo is always one tap away.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if ExpiryReminder.expiresSoon, let expiry = ExpiryReminder.expirationDate {
                        Label("App expires \(expiry.formatted(.relative(presentation: .named))). Press Run in Xcode to renew.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    buttons
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Cilantro or not cilantro?")
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in setImage(picked) }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .toolbar {
                if image != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        HomeButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.history) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history: HistoryView()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { History.prune(context) }
            }
            .task { await ExpiryReminder.schedule() }
        }
        .environment(\.goHome, GoHomeAction(action: goHome))
    }

    /// Back to the start screen: leaves History and clears the current photo.
    private func goHome() {
        path = NavigationPath()
        image = nil
        prediction = nil
        currentRecord = nil
        errorMessage = nil
        photoItem = nil
    }

    /// A square that the photo fills and is cropped to. (As an overlay, a tall photo can't
    /// stretch the square and push the rest of the screen down.)
    private var preview: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.secondary.opacity(0.1))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Label("Take or choose a photo of your food", systemImage: "fork.knife")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var resultView: some View {
        if isClassifying {
            ProgressView("Checking…")
        } else if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else if let prediction {
            VStack(spacing: 4) {
                ResultLabel(prediction: prediction)
                    .font(.title2.bold())
                Text("Cilantro probability: \(prediction.cilantroProbability, format: .percent.precision(.fractionLength(0)))")
                    .foregroundStyle(.secondary)
                if let currentRecord {
                    FeedbackPicker(record: currentRecord)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!CameraPicker.isAvailable) // the Simulator has no camera

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Library", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else { return }
        setImage(picked)
    }

    private func setImage(_ picked: UIImage) {
        image = picked
        prediction = nil
        currentRecord = nil
        errorMessage = nil
        Task { await classify(picked) }
    }

    private func classify(_ picked: UIImage) async {
        isClassifying = true
        defer { isClassifying = false }
        do {
            let result = try await Self.detector.get().classify(picked)
            prediction = result
            let record = CheckRecord(prediction: result, image: picked)
            context.insert(record)
            currentRecord = record
            History.prune(context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum Route: Hashable {
    case history
}

/// Returns to the start screen from anywhere in the app. Equatable (always equal) so passing
/// it down doesn't make every screen redraw; the action itself never changes.
struct GoHomeAction: Equatable {
    let action: () -> Void
    func callAsFunction() { action() }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var goHome = GoHomeAction(action: {})
}

struct HomeButton: View {
    @Environment(\.goHome) private var goHome

    var body: some View {
        Button("Home", systemImage: "house") { goHome() }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: CheckRecord.self, inMemory: true)
}
