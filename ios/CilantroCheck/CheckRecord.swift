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

    init(date: Date = .now, prediction: Prediction, image: UIImage) {
        self.date = date
        self.cilantroProbability = prediction.cilantroProbability
        self.imageData = image.downscaled(maxSide: 1024).jpegData(compressionQuality: 0.8) ?? Data()
        self.thumbnailData = image.downscaled(maxSide: 240).jpegData(compressionQuality: 0.7) ?? Data()
    }

    var prediction: Prediction { Prediction(cilantroProbability: cilantroProbability) }
    var image: UIImage? { UIImage(data: imageData) }
    var thumbnail: UIImage? { UIImage(data: thumbnailData) }
}

enum History {
    static let retentionDays = 7

    /// Deletes checks older than `retentionDays`.
    static func prune(_ context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else { return }
        try? context.delete(model: CheckRecord.self, where: #Predicate { $0.date < cutoff })
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
