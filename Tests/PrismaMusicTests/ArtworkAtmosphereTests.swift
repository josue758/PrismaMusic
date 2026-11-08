import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PrismaMusic

final class ArtworkAtmosphereTests: XCTestCase {
    private func image(_ draw: (CGContext) -> Void) -> Data {
        let context = CGContext(
            data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testDominantPaletteComesFromTheActualImage() {
        let data = image { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            context.setFillColor(CGColor(red: 0.92, green: 0.05, blue: 0.10, alpha: 1))
            context.fill(CGRect(x: 4, y: 4, width: 60, height: 88))
            context.setFillColor(CGColor(red: 0.04, green: 0.8, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 64, y: 4, width: 28, height: 88))
        }
        let result = ArtworkPalette.extract(data, fallback: .fallback())
        XCTAssertTrue(result.extracted)
        XCTAssertGreaterThan(result.primary.red, 0.8)
        XCTAssertLessThan(result.primary.green, 0.2)
        XCTAssertGreaterThan(result.secondary.green, 0.6)
        XCTAssertGreaterThan(result.secondary.blue, 0.7)
        XCTAssertGreaterThan(result.primary.distance(to: result.secondary), 0.10)
        XCTAssertEqual(result, ArtworkPalette.extract(data, fallback: .fallback()))
    }
    func testMonochromeAndTransparentArtworkHaveDifferentFallbacks() {
        let black = image { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        let blackPalette = ArtworkPalette.extract(black, fallback: .fallback())
        XCTAssertTrue(blackPalette.extracted)
        XCTAssertLessThan(blackPalette.primary.luminance, 0.01)
        let transparent = image { _ in }
        let fallback = ArtworkPalette.fallback(album: "Marea")
        XCTAssertEqual(ArtworkPalette.extract(transparent, fallback: fallback), fallback)
        XCTAssertEqual(ArtworkPalette.extract(Data([1, 2, 3]), fallback: fallback), fallback)
    }
    func testHighlightRetainsReadableContrast() {
        for color in [
            PaletteColor(red: 0.03, green: 0.05, blue: 0.2), PaletteColor(red: 1, green: 0.9, blue: 0.7),
            PaletteColor(red: 0.7, green: 0.05, blue: 0.1),
        ] {
            let dark = color.readable(onDark: true).luminance
            XCTAssertGreaterThanOrEqual((max(dark, 0.035) + 0.05) / (min(dark, 0.035) + 0.05), 4.5)
            let light = color.readable(onDark: false).luminance
            XCTAssertGreaterThanOrEqual((max(light, 0.94) + 0.05) / (min(light, 0.94) + 0.05), 4.5)
        }
    }
    func testVersionTwoPreferencesGainVisualDefaultsWithoutLosingAudioSettings() throws {
        var old = ListeningPreferences()
        old.startSection = "favorites"
        old.eqEnabled = true
        old.selectPreset("jazz")
        old.playbackRate = 0.8
        old.compactRows = true
        old.lyricsOffset = -0.3
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        for key in [
            "adaptiveArtwork", "ambientMotion", "artworkPulse", "glassTransparency", "microInteractions", "hoverDepth",
            "showFeedback",
        ] { dictionary.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(
            ListeningPreferences.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertTrue(restored.eqEnabled)
        XCTAssertEqual(restored.eqGains, old.eqGains)
        XCTAssertEqual(restored.playbackRate, 0.8)
        XCTAssertTrue(restored.compactRows)
        XCTAssertEqual(restored.lyricsOffset, -0.3)
        XCTAssertTrue(restored.adaptiveArtwork)
        XCTAssertTrue(restored.ambientMotion)
        XCTAssertTrue(restored.artworkPulse)
        XCTAssertEqual(restored.glassTransparency, 0.65)
        XCTAssertEqual(restored.startSection, "favorites")
        XCTAssertTrue(restored.microInteractions)
        XCTAssertTrue(restored.hoverDepth)
        XCTAssertTrue(restored.showFeedback)
    }
}
