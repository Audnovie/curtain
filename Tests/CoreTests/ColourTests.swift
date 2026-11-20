import XCTest
@testable import CurtainCore

final class ColourTests: XCTestCase {
    func testHex() {
        XCTAssertEqual(RGB(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertEqual(RGB(hex: "0a3d7a")?.hex, "#0A3D7A")
        XCTAssertEqual(RGB(hex: " #000000 ")?.hex, "#000000")
        XCTAssertNil(RGB(hex: "#12345"))
        XCTAssertNil(RGB(hex: "#GG0000"))
        XCTAssertNil(RGB(hex: "+12345"))
        XCTAssertNil(RGB(hex: ""))
        XCTAssertEqual(RGB(r: 2, g: -1, b: .nan), RGB(r: 1, g: 0, b: 0))
        XCTAssertEqual(RGB.white.hex, "#FFFFFF")
    }

    func testLabRoundTrip() {
        for hex in ["#000000", "#FFFFFF", "#D42B3A", "#0B5FA5", "#1F6F43", "#F5F1E8", "#808080", "#6D28D9"] {
            let c = RGB(hex)
            let back = ColorMath.rgb(ColorMath.lab(c))
            XCTAssertEqual(back.r, c.r, accuracy: 0.003, hex)
            XCTAssertEqual(back.g, c.g, accuracy: 0.003, hex)
            XCTAssertEqual(back.b, c.b, accuracy: 0.003, hex)
        }
        XCTAssertEqual(ColorMath.lab(.white).l, 1, accuracy: 0.001)
        XCTAssertEqual(ColorMath.lab(.black).l, 0, accuracy: 0.001)
        XCTAssertLessThan(ColorMath.lab(RGB("#808080")).chroma, 0.001)
        XCTAssertGreaterThan(ColorMath.lab(RGB("#D42B3A")).chroma, 0.15)
        XCTAssertEqual(ColorMath.lab(ColorMath.withLightness(RGB("#0B5FA5"), 0.3)).l, 0.3, accuracy: 0.03)
    }

    func testContrast() {
        XCTAssertEqual(Contrast.ratio(.white, .black), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(.white, .white), 1, accuracy: 0.0001)
        XCTAssertEqual(Contrast.text(on: RGB("#141B2D")), .white)
        XCTAssertEqual(Contrast.text(on: RGB("#F5F1E8")), Contrast.darkText)

        // A mid red on which white is not quite readable gets darkened until it is.
        let red = RGB("#EF4444")
        XCTAssertLessThan(Contrast.ratio(.white, red), Contrast.readable)
        let fixed = Contrast.readableBackground(red, for: .white)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(.white, fixed), Contrast.readable)
        XCTAssertLessThan(ColorMath.lab(fixed).distance(to: ColorMath.lab(red)), 0.2)
        // Already fine: untouched.
        XCTAssertEqual(Contrast.readableBackground(RGB("#141B2D"), for: .white), RGB("#141B2D"))

        let accent = Contrast.visibleAccent(RGB("#1F2A44"), on: RGB("#141B2D"))
        XCTAssertGreaterThanOrEqual(Contrast.ratio(accent, RGB("#141B2D")), 3)
    }

    func testEveryBuiltInThemeIsReadable() {
        XCTAssertEqual(Theme.presets.count, 10)
        XCTAssertEqual(Set(Theme.presets.map { $0.name }).count, Theme.presets.count)
        for t in Theme.presets {
            XCTAssertGreaterThanOrEqual(Contrast.ratio(t.foreground, t.background), Contrast.readable, t.name)
            if let second = t.background2 {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(t.foreground, second), Contrast.readable, t.name)
            }
            XCTAssertGreaterThanOrEqual(Contrast.ratio(t.accent, t.background), 3, t.name)
            // A typo in a colour would have turned it magenta.
            for c in [t.background, t.background2 ?? t.background, t.foreground, t.accent] {
                XCTAssertNotEqual(c, RGB(r: 1, g: 0, b: 1), t.name)
            }
        }
    }
}

final class PaletteTests: XCTestCase {
    /// A picture made of flat bands, widest first.
    private func bands(_ colours: [(String, Int)], width: Int = 40) -> (pixels: [UInt8], width: Int, height: Int) {
        var pixels: [UInt8] = []
        var rows = 0
        for (hex, height) in colours {
            let c = RGB(hex)
            for _ in 0..<(height * width) {
                pixels += [UInt8((c.r * 255).rounded()), UInt8((c.g * 255).rounded()), UInt8((c.b * 255).rounded()), 255]
            }
            rows += height
        }
        return (pixels, width, rows)
    }

    private func assertReadable(_ themes: [Theme], file: StaticString = #filePath, line: UInt = #line) {
        for t in themes {
            XCTAssertGreaterThanOrEqual(Contrast.ratio(t.foreground, t.background), Contrast.readable, t.name, file: file, line: line)
            if let second = t.background2 {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(t.foreground, second), Contrast.readable, t.name, file: file, line: line)
            }
            XCTAssertGreaterThanOrEqual(Contrast.ratio(t.accent, t.background), 3, t.name, file: file, line: line)
        }
        XCTAssertEqual(Set(themes.map { $0.name }).count, themes.count, "two sets share a name", file: file, line: line)
    }

    func testTwoColourPicture() {
        let p = bands([("#1E3A8A", 24), ("#0D9488", 15), ("#F8FAFC", 1)])
        let swatches = Palette.extract(pixels: p.pixels, width: p.width, height: p.height)
        XCTAssertEqual(swatches.count, 3)
        XCTAssertLessThan(ColorMath.lab(swatches[0].color).distance(to: ColorMath.lab(RGB("#1E3A8A"))), 0.02)
        XCTAssertEqual(swatches[0].share, 0.6, accuracy: 0.001)
        XCTAssertLessThan(ColorMath.lab(swatches[1].color).distance(to: ColorMath.lab(RGB("#0D9488"))), 0.02)
        XCTAssertEqual(swatches[1].share, 0.375, accuracy: 0.001)
        XCTAssertEqual(swatches.reduce(0) { $0 + $1.share }, 1, accuracy: 0.001)

        let themes = Palette.suggestions(from: swatches)
        XCTAssertGreaterThanOrEqual(themes.count, 4)
        XCTAssertEqual(themes[0].name, "Blend in")
        XCTAssertLessThan(ColorMath.lab(themes[0].background).distance(to: ColorMath.lab(RGB("#1E3A8A"))), 0.02)
        XCTAssertEqual(themes[0].foreground, .white)
        assertReadable(themes)
    }

    func testSimilarShadesBecomeOneColour() {
        // Many slightly different blues, the way a photo or a blend has them.
        var pixels: [UInt8] = []
        for y in 0..<50 {
            for x in 0..<50 {
                let wobble = (x * 7 + y * 13) % 9
                if y < 35 {
                    pixels += [UInt8(20 + wobble), UInt8(60 + wobble), UInt8(140 + wobble), 255]
                } else {
                    pixels += [UInt8(230 - wobble), UInt8(120 + wobble), UInt8(40 + wobble), 255]
                }
            }
        }
        let swatches = Palette.extract(pixels: pixels, width: 50, height: 50)
        XCTAssertEqual(swatches.count, 2)
        XCTAssertEqual(swatches[0].share, 0.7, accuracy: 0.001)
        XCTAssertGreaterThan(swatches[0].color.b, swatches[0].color.r)
        XCTAssertGreaterThan(swatches[1].color.r, swatches[1].color.b)
        assertReadable(Palette.suggestions(from: swatches))
    }

    func testOneColourAndGreyPictures() {
        let flat = bands([("#3B82F6", 30)])
        let one = Palette.extract(pixels: flat.pixels, width: flat.width, height: flat.height)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].share, 1, accuracy: 0.0001)
        let fromOne = Palette.suggestions(from: one)
        XCTAssertGreaterThanOrEqual(fromOne.count, 3)
        assertReadable(fromOne)

        let grey = bands([("#202020", 20), ("#E0E0E0", 20), ("#808080", 10)])
        let greys = Palette.extract(pixels: grey.pixels, width: grey.width, height: grey.height)
        XCTAssertEqual(greys.count, 3)
        assertReadable(Palette.suggestions(from: greys))
    }

    func testAwkwardInput() {
        XCTAssertTrue(Palette.extract(pixels: [], width: 0, height: 0).isEmpty)
        XCTAssertTrue(Palette.extract(pixels: [1, 2, 3], width: 4, height: 4).isEmpty)
        // Fully see-through pixels don't count.
        XCTAssertTrue(Palette.extract(pixels: [255, 0, 0, 0, 0, 255, 0, 10], width: 2, height: 1).isEmpty)
        let half = Palette.extract(pixels: [255, 0, 0, 0, 0, 0, 255, 255], width: 2, height: 1)
        XCTAssertEqual(half.count, 1)
        XCTAssertEqual(half[0].color.hex, "#0000FF")
        XCTAssertTrue(Palette.suggestions(from: []).isEmpty)
    }

    func testSameAnswerEveryTime() {
        var pixels: [UInt8] = []
        var seed: UInt32 = 12345
        let bases: [[UInt8]] = [[10, 20, 80], [0, 150, 140], [240, 240, 245], [200, 60, 90]]
        for _ in 0..<(60 * 60) {
            seed = seed &* 1664525 &+ 1013904223
            let pick = Int(seed >> 24) % 4
            let base = bases[pick]
            let n = UInt8((seed >> 8) & 7)
            pixels += [base[0] &+ n, base[1] &+ n, base[2] &+ n, 255]
        }
        let a = Palette.extract(pixels: pixels, width: 60, height: 60)
        let b = Palette.extract(pixels: pixels, width: 60, height: 60)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(Palette.suggestions(from: a), Palette.suggestions(from: b))
        assertReadable(Palette.suggestions(from: a))
        XCTAssertLessThanOrEqual(Palette.extract(pixels: pixels, width: 60, height: 60, count: 2).count, 2)
    }
}
