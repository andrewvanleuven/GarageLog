#if canImport(UIKit)
import UIKit

extension UIImage {
    func cropTo16x9() -> UIImage {
        let width = size.width
        let height = size.height
        let targetAspectRatio: CGFloat = 16.0 / 9.0

        var targetWidth = width
        var targetHeight = height

        if width / height > targetAspectRatio {
            targetWidth = height * targetAspectRatio
        } else {
            targetHeight = width / targetAspectRatio
        }

        let x = (width - targetWidth) / 2.0
        let y = (height - targetHeight) / 2.0
        let cropRect = CGRect(x: x, y: y, width: targetWidth, height: targetHeight)

        guard let cgImage = self.cgImage?.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
}
#endif
