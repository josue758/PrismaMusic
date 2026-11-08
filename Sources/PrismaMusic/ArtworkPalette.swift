import Foundation
import ImageIO
import SwiftUI

struct PaletteColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    var saturation: Double {
        let hi = max(red, green, blue)
        return hi == 0 ? 0 : (hi - min(red, green, blue)) / hi
    }
    var luminance: Double {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func distance(to other: Self) -> Double {
        pow(red - other.red, 2) + pow(green - other.green, 2) + pow(blue - other.blue, 2)
    }
    func mixed(with other: Self, amount: Double) -> Self {
        .init(
            red: red * (1 - amount) + other.red * amount, green: green * (1 - amount) + other.green * amount,
            blue: blue * (1 - amount) + other.blue * amount)
    }
    func readable(onDark: Bool) -> Self {
        let background: Double = onDark ? 0.035 : 0.94
        var value = self
        let target = PaletteColor(red: onDark ? 1 : 0, green: onDark ? 1 : 0, blue: onDark ? 1 : 0)
        for _ in 0..<24 {
            let contrast = (max(value.luminance, background) + 0.05) / (min(value.luminance, background) + 0.05)
            if contrast >= 4.5 { break }
            value = value.mixed(with: target, amount: 0.09)
        }
        return value
    }
}
struct ArtworkPalette: Equatable, Sendable {
    var primary: PaletteColor
    var secondary: PaletteColor
    var tertiary: PaletteColor
    var extracted = false
    var colors: [Color] { [primary.color, secondary.color, tertiary.color] }
    static func seed(_ album: String) -> Int { album.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3 }
    static func fallback(album: String = "Prisma") -> Self {
        switch seed(album) {
        case 0:
            return .init(
                primary: .init(red: 0.53, green: 0.32, blue: 0.80),
                secondary: .init(red: 0.91, green: 0.22, blue: 0.50),
                tertiary: .init(red: 0.10, green: 0.06, blue: 0.24))
        case 1:
            return .init(
                primary: .init(red: 0.07, green: 0.67, blue: 0.69),
                secondary: .init(red: 0.61, green: 0.88, blue: 0.81),
                tertiary: .init(red: 0.015, green: 0.16, blue: 0.19))
        default:
            return .init(
                primary: .init(red: 0.93, green: 0.37, blue: 0.28), secondary: .init(red: 1, green: 0.77, blue: 0.51),
                tertiary: .init(red: 0.26, green: 0.06, blue: 0.11))
        }
    }
    /// Quantize a 48px thumbnail, retain distinct dominant colors and prefer chromatic pixels.
    /// Decoding and sampling are performed once per artwork, away from the UI and audio threads.
    static func extract(_ data: Data, fallback: Self) -> Self {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 48,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return fallback }
        let width = 48
        let height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard
                let context = CGContext(
                    data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return fallback }
        var bins: [Int: (count: Double, r: Double, g: Double, b: Double)] = [:]
        var opaque = 0.0
        var mean = PaletteColor(red: 0, green: 0, blue: 0)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.7 else { continue }
            let color = PaletteColor(
                red: min(1, Double(pixels[offset]) / 255 / alpha),
                green: min(1, Double(pixels[offset + 1]) / 255 / alpha),
                blue: min(1, Double(pixels[offset + 2]) / 255 / alpha))
            opaque += 1
            mean.red += color.red
            mean.green += color.green
            mean.blue += color.blue
            // Ignore pure borders when the artwork contains usable interior colors.
            if color.luminance < 0.009 || color.luminance > 0.94 { continue }
            let key = (Int(color.red * 15) << 8) | (Int(color.green * 15) << 4) | Int(color.blue * 15)
            let weight = 0.35 + color.saturation * 1.65
            let old = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (
                old.count + weight, old.r + color.red * weight, old.g + color.green * weight,
                old.b + color.blue * weight
            )
        }
        let ranked = bins.sorted {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }.map { value in
            PaletteColor(
                red: value.value.r / value.value.count, green: value.value.g / value.value.count,
                blue: value.value.b / value.value.count)
        }
        guard let first = ranked.first else {
            guard opaque > 0 else { return fallback }
            let neutral = PaletteColor(red: mean.red / opaque, green: mean.green / opaque, blue: mean.blue / opaque)
            return .init(
                primary: neutral, secondary: neutral.mixed(with: .init(red: 0.5, green: 0.5, blue: 0.5), amount: 0.4),
                tertiary: neutral.mixed(with: .init(red: 0, green: 0, blue: 0), amount: 0.6), extracted: true)
        }
        let second =
            ranked.first { $0.distance(to: first) > 0.10 }
            ?? first.mixed(with: .init(red: 1, green: 1, blue: 1), amount: 0.25)
        let third =
            ranked.first { $0.distance(to: first) > 0.10 && $0.distance(to: second) > 0.10 }
            ?? first.mixed(with: .init(red: 0, green: 0, blue: 0), amount: 0.45)
        return .init(primary: first, secondary: second, tertiary: third, extracted: true)
    }
}
