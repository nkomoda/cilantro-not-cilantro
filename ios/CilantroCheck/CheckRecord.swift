import Foundation
import SwiftData
import UIKit

/// One photo that went through the cilantro check. Stored on-device only.
@Model
final class CheckRecord {
    var date: Date
    var cilantroProbability: Double
    /// Downscaled JPEG (max 1024px) for the detail view. Kept outside the database file.
    @Attribute(.externalStorage) var imageData: Data
    /// Small JPEG for the history list.
    var thumbnailData: Data
    /// The user's answer to "Was there cilantro?" (a `Feedback` raw value), or nil if not answered yet.
    var feedbackRaw: String?
    /// When this check was last included in a training export. Reset when the answer changes.
    var exportedAt: Date?

    init(date: Date = .now, prediction: Prediction, image: UIImage) {
        self.date = date
        self.cilantroProbability = prediction.cilantroProbability
        self.imageData = image.downscaled(maxSide: 1024).jpegData(compressionQuality: 0.8) ?? Data()
        self.thumbnailData = image.downscaled(maxSide: 240).jpegData(compressionQuality: 0.7) ?? Data()
    }

    var prediction: Prediction { Prediction(cilantroProbability: cilantroProbability) }
    var image: UIImage? { UIImage(data: imageData) }
    var thumbnail: UIImage? { UIImage(data: thumbnailData) }

    var feedback: Feedback? {
        get { feedbackRaw.flatMap(Feedback.init(rawValue:)) }
        set {
            feedbackRaw = newValue?.rawValue
            exportedAt = nil  // a changed answer should be exported again
        }
    }

    /// Whether the model's guess matched the user's answer. Nil when unanswered, or when the
    /// cilantro was hidden (the model can only judge what's visible in the photo).
    var modelWasRight: Bool? {
        switch feedback {
        case .visible: prediction.hasCilantro
        case .absent: !prediction.hasCilantro
        case .hidden, nil: nil
        }
    }

    var needsExport: Bool { feedback != nil && exportedAt == nil }
}

/// The user's answer after eating: was there actually cilantro?
enum Feedback: String, CaseIterable {
    case visible   // cilantro, and you can see it in the photo -> training data
    case hidden    // cilantro, but not visible in the photo -> not used for training
    case absent    // no cilantro -> training data

    var title: String {
        switch self {
        case .visible: "Yes, visible"
        case .hidden: "Yes, hidden"
        case .absent: "No"
        }
    }

    var systemImage: String {
        switch self {
        case .visible: "leaf.fill"
        case .hidden: "eye.slash"
        case .absent: "xmark.circle"
        }
    }
}

enum History {
    static let retentionDays = 7

    /// Deletes checks older than `retentionDays`, except answered ones that haven't been
    /// exported yet. Those are training data, so they wait for the next export.
    static func prune(_ context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else { return }
        try? context.delete(model: CheckRecord.self, where: #Predicate {
            $0.date < cutoff && ($0.feedbackRaw == nil || $0.exportedAt != nil)
        })
        try? context.save()
    }
}

extension UIImage {
    /// Returns an upright copy whose longest side is at most `maxSide` points.
    func downscaled(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
