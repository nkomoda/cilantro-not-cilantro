// Train the cilantro classifier with Apple's Create ML (free, runs locally on macOS).
// Works with just the Xcode Command Line Tools; the full Xcode app is not required.
//
//   swift training/train.swift [split-dir] [output.mlmodel]
//
// Defaults: data/split  ->  ios/CilantroCheck/Model/CilantroClassifier.mlmodel

import CreateML
import Foundation

let args = CommandLine.arguments
let splitDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "data/split")
let outputURL = URL(fileURLWithPath: args.count > 2 ? args[2] : "ios/CilantroCheck/Model/CilantroClassifier.mlmodel")
let trainDir = splitDir.appendingPathComponent("train")
let testDir = splitDir.appendingPathComponent("test")

// Transfer learning on Apple's built-in scene feature extractor. The extractor ships
// with iOS, so the exported model is tiny (well under 1 MB).
let parameters = MLImageClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    maxIterations: 50,
    augmentation: [.crop, .flip, .exposure, .rotation],
    algorithm: .transferLearning(
        featureExtractor: .scenePrint(revision: 2),
        classifier: .logisticRegressor
    )
)

print("Training on \(trainDir.path) ...")
let start = Date()
let classifier = try MLImageClassifier(
    trainingData: .labeledDirectories(at: trainDir),
    parameters: parameters
)
print(String(format: "Done in %.0fs", Date().timeIntervalSince(start)))

func accuracy(_ metrics: MLClassifierMetrics) -> String {
    String(format: "%.1f%%", (1 - metrics.classificationError) * 100)
}

print("Training accuracy:   \(accuracy(classifier.trainingMetrics))")
print("Validation accuracy: \(accuracy(classifier.validationMetrics))")

if FileManager.default.fileExists(atPath: testDir.path) {
    let test = classifier.evaluation(on: MLImageClassifier.DataSource.labeledDirectories(at: testDir))
    print("Test accuracy:       \(accuracy(test))   <- the number that matters")
    print("\nConfusion matrix (rows = true label, columns = predicted):")
    print(test.confusion)
    print("Per-class precision / recall:")
    print(test.precisionRecall)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let metadata = MLModelMetadata(
    author: "cilantro-not-cilantro",
    shortDescription: "Classifies a food photo as cilantro or not_cilantro.",
    version: ISO8601DateFormatter().string(from: Date())
)
try classifier.write(to: outputURL, metadata: metadata)
print("\nSaved model to \(outputURL.path)")
