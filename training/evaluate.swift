// Evaluate the trained model the same way the app runs it (Core ML through Vision, center crop):
// misclassified images, and how recall and false alarms change with the threshold.
//
//   swift training/evaluate.swift [labeled-dir] [model.mlmodel] [target-recall]
//
// Defaults: data/split/test  ios/CilantroCheck/Model/CilantroClassifier.mlmodel  0.95
// Run it on data/split/train to find likely mislabeled training images.

import CoreML
import Foundation
import Vision

let args = CommandLine.arguments
let dataDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "data/split/test")
let modelURL = URL(fileURLWithPath: args.count > 2 ? args[2] : "ios/CilantroCheck/Model/CilantroClassifier.mlmodel")
let targetRecall = args.count > 3 ? Double(args[3])! : 0.95
let appThreshold = 0.5

let model = try VNCoreMLModel(for: MLModel(contentsOf: MLModel.compileModel(at: modelURL)))

struct Result {
    let url: URL
    let isCilantro: Bool
    let probability: Double
}

func cilantroProbability(_ url: URL) throws -> Double {
    let request = VNCoreMLRequest(model: model)
    request.imageCropAndScaleOption = .centerCrop
    try VNImageRequestHandler(url: url).perform([request])
    let results = request.results as? [VNClassificationObservation] ?? []
    return Double(results.first { $0.identifier == "cilantro" }?.confidence ?? 0)
}

var results: [Result] = []
for label in ["cilantro", "not_cilantro"] {
    let files = try FileManager.default
        .contentsOfDirectory(at: dataDir.appendingPathComponent(label), includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
    for url in files {
        results.append(Result(url: url, isCilantro: label == "cilantro", probability: try cilantroProbability(url)))
    }
}

let positives = results.filter(\.isCilantro)
let negatives = results.filter { !$0.isCilantro }

func stats(at threshold: Double) -> (recall: Double, falseAlarm: Double, accuracy: Double) {
    let tp = positives.filter { $0.probability >= threshold }.count
    let fp = negatives.filter { $0.probability >= threshold }.count
    let correct = tp + negatives.count - fp
    return (Double(tp) / Double(positives.count), Double(fp) / Double(negatives.count),
            Double(correct) / Double(results.count))
}

func pct(_ x: Double) -> String { String(format: "%5.1f%%", x * 100) }

print("\(dataDir.path): \(positives.count) cilantro, \(negatives.count) not_cilantro\n")

let current = stats(at: appThreshold)
print("At the app's threshold (\(appThreshold)):")
print("  accuracy            \(pct(current.accuracy))")
print("  cilantro caught     \(pct(current.recall))   (recall; misses are the costly error)")
print("  false alarms        \(pct(current.falseAlarm))   (not_cilantro flagged as cilantro)\n")

print("Threshold  caught  false alarms  accuracy")
for t in stride(from: 0.05, through: 0.951, by: 0.05) {
    let s = stats(at: t)
    print(String(format: "  %.2f    ", t) + "\(pct(s.recall))   \(pct(s.falseAlarm))     \(pct(s.accuracy))")
}

// Highest threshold that still meets the target recall = fewest false alarms at that recall.
let candidates = Set(positives.map(\.probability)).sorted(by: >)
if let best = candidates.first(where: { stats(at: $0).recall >= targetRecall }) {
    let s = stats(at: best)
    print(String(format: "\nTo catch ≥%.0f%% of cilantro: threshold %.3f", targetRecall * 100, best)
          + " -> caught \(pct(s.recall)), false alarms \(pct(s.falseAlarm))")
}

let missed = positives.filter { $0.probability < appThreshold }.sorted { $0.probability < $1.probability }
let falseAlarms = negatives.filter { $0.probability >= appThreshold }.sorted { $0.probability > $1.probability }

print("\nMissed cilantro (\(missed.count)), most confident first:")
for r in missed { print(String(format: "  %.3f  ", r.probability) + r.url.path) }
print("\nFalse alarms (\(falseAlarms.count)), most confident first:")
for r in falseAlarms { print(String(format: "  %.3f  ", r.probability) + r.url.path) }
