import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var image: UIImage?
    @State private var prediction: Prediction?
    @State private var errorMessage: String?
    @State private var isClassifying = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?

    // Loaded once, lazily. Holds the error if the model hasn't been trained yet.
    private static let detector = Result { try CilantroDetector() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                preview
                resultView
                Spacer()
                buttons
            }
            .padding()
            .navigationTitle("Cilantro?")
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in setImage(picked) }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Label("Take or choose a photo of your food", systemImage: "fork.knife")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
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
                Text(prediction.hasCilantro ? "🌿 Cilantro detected" : "✅ No cilantro")
                    .font(.title2.bold())
                Text("Cilantro probability: \(prediction.cilantroProbability, format: .percent.precision(.fractionLength(0)))")
                    .foregroundStyle(.secondary)
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
        errorMessage = nil
        Task { await classify(picked) }
    }

    private func classify(_ picked: UIImage) async {
        isClassifying = true
        defer { isClassifying = false }
        do {
            prediction = try await Self.detector.get().classify(picked)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
