import CoreML
import UIKit
import Vision

struct Prediction {
    /// Probability (0...1) that the photo contains cilantro.
    let cilantroProbability: Double

    var hasCilantro: Bool { cilantroProbability >= 0.5 }
}

enum DetectorError: LocalizedError {
    case modelMissing
    case badImage
    case noResult

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "CilantroClassifier.mlmodel isn't in the app yet. Run `make train`, then rebuild."
        case .badImage:
            return "Couldn't read that image."
        case .noResult:
            return "The model didn't return a result."
        }
    }
}

/// Runs the Create ML model on-device through Vision.
///
/// The model is loaded by name at runtime (rather than through Xcode's generated
/// `CilantroClassifier` class) so the app still builds before a model has been trained.
final class CilantroDetector: @unchecked Sendable {
    private let model: VNCoreMLModel

    init() throws {
        guard let url = Bundle.main.url(forResource: "CilantroClassifier", withExtension: "mlmodelc") else {
            throw DetectorError.modelMissing
        }
        model = try VNCoreMLModel(for: MLModel(contentsOf: url))
    }

    func classify(_ image: UIImage) async throws -> Prediction {
        guard let cgImage = image.cgImage else { throw DetectorError.badImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Vision is synchronous; keep it off the main thread.
        return try await Task.detached(priority: .userInitiated) { [model] in
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])

            guard let results = request.results as? [VNClassificationObservation], !results.isEmpty else {
                throw DetectorError.noResult
            }
            let cilantro = results.first { $0.identifier == "cilantro" }?.confidence ?? 0
            return Prediction(cilantroProbability: Double(cilantro))
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
