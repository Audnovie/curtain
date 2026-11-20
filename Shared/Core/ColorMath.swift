// Colour arithmetic: how light a colour looks, whether text is readable on it,
// and a colour space (OKLab) in which "nearby" matches what the eye sees.

import Foundation

/// A colour in OKLab. `l` is lightness from 0 (black) to 1 (white).
public struct Lab: Equatable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// How colourful it is. Greys are near 0, vivid colours around 0.2 or more.
    public var chroma: Double { (a * a + b * b).squareRoot() }

    public func distance(to o: Lab) -> Double {
        let dl = l - o.l, da = a - o.a, db = b - o.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

public enum ColorMath {
    static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func fromLinear(_ c: Double) -> Double {
        let x = min(1, max(0, c))
        return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    public static func lab(_ c: RGB) -> Lab {
        let r = toLinear(c.r), g = toLinear(c.g), b = toLinear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    public static func rgb(_ c: Lab) -> RGB {
        let l0 = c.l + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m0 = c.l - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s0 = c.l - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l = l0 * l0 * l0, m = m0 * m0 * m0, s = s0 * s0 * s0
        return RGB(r: fromLinear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   g: fromLinear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   b: fromLinear(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    /// The same hue, with a new lightness. Colour is eased off near black and white, where a
    /// screen can't show it anyway.
    public static func withLightness(_ c: RGB, _ lightness: Double) -> RGB {
        var x = lab(c)
        let target = min(1, max(0, lightness))
        var edge = 1.0
        if target < 0.15 { edge = target / 0.15 }
        if target > 0.9 { edge = (1 - target) / 0.1 }
        let keep = 0.3 + 0.7 * min(1, max(0, edge))
        x.l = target
        x.a *= keep
        x.b *= keep
        return rgb(x)
    }

    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let x = lab(a), y = lab(b)
        return rgb(Lab(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t))
    }
}

/// Readability of text on a background, measured the way WCAG does.
public enum Contrast {
    /// What counts as readable for normal-size text.
    public static let readable = 4.5

    public static func luminance(_ c: RGB) -> Double {
        0.2126 * ColorMath.toLinear(c.r) + 0.7152 * ColorMath.toLinear(c.g) + 0.0722 * ColorMath.toLinear(c.b)
    }

    /// From 1 (the same colour) to 21 (black on white).
    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    public static let darkText = RGB("#14171C")

    /// White or near-black, whichever reads better on `background`.
    public static func text(on background: RGB) -> RGB {
        ratio(.white, background) >= ratio(darkText, background) ? .white : darkText
    }

    /// For a colour that may still be adjusted: white text wherever white is close to readable
    /// (the background is then darkened a touch to get it there), dark text only on light colours.
    /// White on a mid blue or red looks right; near-black on them looks muddy, even when the
    /// numbers favour it.
    public static func preferredText(on background: RGB) -> RGB {
        ratio(.white, background) >= 3.0 ? .white : darkText
    }

    /// Nudges `background` lighter or darker, keeping its hue, until `text` is readable on it.
    public static func readableBackground(_ background: RGB, for text: RGB, minimum: Double = readable) -> RGB {
        if ratio(text, background) >= minimum { return background }
        let darken = luminance(text) > luminance(background)
        var l = ColorMath.lab(background).l
        var best = background
        var steps = 0
        while steps < 60 {
            l += darken ? -0.015 : 0.015
            if l <= 0 || l >= 1 { break }
            best = ColorMath.withLightness(background, l)
            if ratio(text, best) >= minimum { return best }
            steps += 1
        }
        return darken ? .black : .white
    }

    /// A version of `accent` that stands out against `background` (for the bar's blocks).
    public static func visibleAccent(_ accent: RGB, on background: RGB, minimum: Double = 3.0) -> RGB {
        if ratio(accent, background) >= minimum { return accent }
        let lighten = luminance(background) < 0.4
        var l = ColorMath.lab(accent).l
        var steps = 0
        while steps < 60 {
            l += lighten ? 0.02 : -0.02
            if l <= 0.02 || l >= 0.98 { break }
            let c = ColorMath.withLightness(accent, l)
            if ratio(c, background) >= minimum { return c }
            steps += 1
        }
        return text(on: background)
    }
}
