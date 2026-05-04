import SwiftUI

/// Returns a SwiftUI Image from raw Data, working on both iOS (UIImage) and macOS (NSImage).
func imageFromData(_ data: Data) -> Image? {
    #if canImport(UIKit)
    guard let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
    #else
    guard let ns = NSImage(data: data) else { return nil }
    return Image(nsImage: ns)
    #endif
}
