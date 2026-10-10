// Move photos that aren't food (gardens, people, animals, posters...) out of data/raw/ into
// data/rejected/<label>/ for a quick look. Uses Apple's built-in Vision image classifier.
//
//   swift scripts/filter_nonfood.swift [--dry-run]
//
// Your own app photos (app_*) are never touched. Every checked photo is listed in
// data/food_filter_checked.txt, so a photo you move back from data/rejected/ stays put.
// Rejected photos stay in attribution.csv, so `make download` won't fetch them again.

import Foundation
import Vision

let dryRun = CommandLine.arguments.contains("--dry-run")
let dataDir = URL(fileURLWithPath: "data")
let checkedList = dataDir.appendingPathComponent("food_filter_checked.txt")

let foodLabels = ["food", "herb", "vegetable", "salad", "fruit", "seasonings", "condiment", "soup", "sandwich",
                  "baked_goods", "plate", "bowl", "tableware", "utensil", "cutting_board", "cookware", "pan", "pot", "jar"]
let peopleLabels = ["people", "adult", "child", "crowd"]
// Subjects that crowd out the food: growing plants, animals, posters and cookbook pages, outdoor scenes.
let otherLabels = ["plant", "decorative_plant", "garden", "tree", "forest", "flower",
                   "animal", "cat", "dog", "bird", "insect", "caterpillar",
                   "art", "document", "screenshot",
                   "outdoor", "sky", "building", "land", "grass"]

func rejectReason(_ url: URL) throws -> String? {
    let request = VNClassifyImageRequest()
    try VNImageRequestHandler(url: url).perform([request])
    var scores: [String: Float] = [:]
    for o in request.results ?? [] { scores[o.identifier] = o.confidence }
    func top(_ labels: [String]) -> (String, Float) {
        labels.map { ($0, scores[$0] ?? 0) }.max { $0.1 < $1.1 }!
    }
    let food = top(foodLabels).1
    let people = top(peopleLabels)
    let other = top(otherLabels)

    if food < 0.05 { return "no food" }
    if people.1 >= 0.85 { return String(format: "%@ %.2f", people.0, people.1) }
    if other.1 >= 0.4 && other.1 > food + 0.1 {
        return String(format: "%@ %.2f > food %.2f", other.0, other.1, food)
    }
    return nil
}

let alreadyChecked = Set(((try? String(contentsOf: checkedList, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
var newlyChecked: [String] = []
var rejected = 0
var kept = 0

for label in ["cilantro", "not_cilantro"] {
    let rawDir = dataDir.appendingPathComponent("raw/\(label)")
    let rejectDir = dataDir.appendingPathComponent("rejected/\(label)")
    let files = try FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "jpg" && !$0.lastPathComponent.hasPrefix("app_") }
        .filter { !alreadyChecked.contains($0.lastPathComponent) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for url in files {
        let name = url.lastPathComponent
        newlyChecked.append(name)
        guard let reason = try rejectReason(url) else { kept += 1; continue }
        rejected += 1
        print("  \(label)/\(name)  (\(reason))")
        if !dryRun {
            try FileManager.default.createDirectory(at: rejectDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: rejectDir.appendingPathComponent(name))
        }
    }
}

if dryRun {
    print("Dry run: would move \(rejected) of \(rejected + kept) photos to data/rejected/")
} else {
    if !newlyChecked.isEmpty {
        let handle = try? FileHandle(forWritingTo: checkedList)
        let text = newlyChecked.joined(separator: "\n") + "\n"
        if let handle {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8)!)
            try handle.close()
        } else {
            try text.write(to: checkedList, atomically: true, encoding: .utf8)
        }
    }
    print("Moved \(rejected) of \(rejected + kept) new photos to data/rejected/. "
          + "Glance through it and move back anything that's real food.")
}
