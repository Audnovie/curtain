// "Match my wallpaper": find the main colours of a picture and turn them into colour sets
// for a card. The picture itself is never kept; only the colours that come out of it.

import Foundation

/// One of the main colours of a picture and how much of the picture it covers (0 to 1).
public struct Swatch: Equatable, Sendable {
    public var color: RGB
    public var share: Double

    public init(color: RGB, share: Double) {
        self.color = color
        self.share = share
    }
}

public enum Palette {
    /// The main colours of a picture, biggest first.
    /// `pixels` is RGBA, 8 bits each, row after row. A small picture is enough (100 by 100 or so).
    public static func extract(pixels: [UInt8], width: Int, height: Int, count: Int = 6) -> [Swatch] {
        let total = width * height
        guard width > 0, height > 0, pixels.count >= total * 4, count > 0 else { return [] }

        // 1. Sort the pixels into coarse bins (32 steps per channel), so that a hundred
        //    slightly different blues count as one heavy point instead of a hundred light ones.
        struct Sum {
            var r = 0.0
            var g = 0.0
            var b = 0.0
            var n = 0.0
        }
        var sums: [Int: Sum] = [:]
        var seen = 0.0
        var i = 0
        while i < total * 4 {
            let a = pixels[i + 3]
            if a >= 128 {
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                let key = (Int(r) >> 3) << 10 | (Int(g) >> 3) << 5 | (Int(b) >> 3)
                var s = sums[key] ?? Sum()
                s.r += Double(r)
                s.g += Double(g)
                s.b += Double(b)
                s.n += 1
                sums[key] = s
                seen += 1
            }
            i += 4
        }
        guard seen > 0 else { return [] }

        struct Point {
            var lab: Lab
            var weight: Double
        }
        // Sorted by key so the result never depends on dictionary order.
        let points: [Point] = sums.keys.sorted().map { key in
            let s = sums[key]!
            let c = RGB(r: s.r / s.n / 255.0, g: s.g / s.n / 255.0, b: s.b / s.n / 255.0)
            return Point(lab: ColorMath.lab(c), weight: s.n)
        }

        // 2. Starting colours: the heaviest point, then whichever point is both heavy and far
        //    from the ones already chosen.
        let k = min(count + 2, points.count)
        var centres: [Lab] = []
        var heaviest = 0
        for (n, p) in points.enumerated() where p.weight > points[heaviest].weight { heaviest = n }
        centres.append(points[heaviest].lab)
        var nearest = points.map { $0.lab.distance(to: centres[0]) }
        while centres.count < k {
            var pick = -1
            var best = 0.0
            for (n, p) in points.enumerated() {
                let score = nearest[n] * nearest[n] * p.weight.squareRoot()
                if score > best {
                    best = score
                    pick = n
                }
            }
            if pick < 0 { break }
            centres.append(points[pick].lab)
            for (n, p) in points.enumerated() {
                nearest[n] = min(nearest[n], p.lab.distance(to: points[pick].lab))
            }
        }

        // 3. Group every point with its nearest colour and move each colour to the middle
        //    of its group, a few times over.
        var weights = [Double](repeating: 0, count: centres.count)
        for _ in 0..<12 {
            var sl = [Double](repeating: 0, count: centres.count)
            var sa = sl, sb = sl, sw = sl
            for p in points {
                var bestN = 0
                var bestD = Double.greatestFiniteMagnitude
                for (n, c) in centres.enumerated() {
                    let d = p.lab.distance(to: c)
                    if d < bestD {
                        bestD = d
                        bestN = n
                    }
                }
                sl[bestN] += p.lab.l * p.weight
                sa[bestN] += p.lab.a * p.weight
                sb[bestN] += p.lab.b * p.weight
                sw[bestN] += p.weight
            }
            for n in centres.indices where sw[n] > 0 {
                centres[n] = Lab(l: sl[n] / sw[n], a: sa[n] / sw[n], b: sb[n] / sw[n])
            }
            weights = sw
        }

        // 4. Colours that ended up alike become one; slivers are dropped.
        struct Group {
            var lab: Lab
            var weight: Double
        }
        var merged: [Group] = []
        let order = centres.indices.sorted { weights[$0] != weights[$1] ? weights[$0] > weights[$1] : $0 < $1 }
        for n in order where weights[n] > 0 {
            if let m = merged.firstIndex(where: { $0.lab.distance(to: centres[n]) < 0.07 }) {
                let w = merged[m].weight + weights[n]
                let x = merged[m].lab, y = centres[n]
                merged[m].lab = Lab(l: (x.l * merged[m].weight + y.l * weights[n]) / w,
                                    a: (x.a * merged[m].weight + y.a * weights[n]) / w,
                                    b: (x.b * merged[m].weight + y.b * weights[n]) / w)
                merged[m].weight = w
            } else {
                merged.append(Group(lab: centres[n], weight: weights[n]))
            }
        }
        // Ties are broken by the colour itself, so the order never depends on chance.
        merged.sort { x, y in
            if x.weight != y.weight { return x.weight > y.weight }
            if x.lab.l != y.lab.l { return x.lab.l < y.lab.l }
            if x.lab.a != y.lab.a { return x.lab.a < y.lab.a }
            return x.lab.b < y.lab.b
        }
        var out: [Swatch] = []
        for m in merged {
            let share = m.weight / seen
            if share < 0.015 && !out.isEmpty { continue }
            out.append(Swatch(color: ColorMath.rgb(m.lab), share: share))
            if out.count == count { break }
        }
        return out
    }

    /// A colour set with `background` behind readable text. `background` is nudged darker or
    /// lighter if the text needs it. Without `second`, the blend runs to a slightly darker shade.
    public static func theme(named name: String, background: RGB, second: RGB? = nil, accentFrom: RGB? = nil) -> Theme {
        let text = Contrast.preferredText(on: background)
        let bg = Contrast.readableBackground(background, for: text)
        let bg2: RGB
        if let s = second {
            bg2 = Contrast.readableBackground(s, for: text)
        } else {
            let l = ColorMath.lab(bg).l
            bg2 = Contrast.readableBackground(ColorMath.withLightness(bg, max(0.05, l - 0.07)), for: text)
        }
        let accent = Contrast.visibleAccent(accentFrom ?? text, on: bg)
        return Theme(name: name, background: bg, background2: bg2, foreground: text, accent: accent)
    }

    /// Colour sets built from a picture's main colours. Text is readable on every one.
    public static func suggestions(from swatches: [Swatch]) -> [Theme] {
        guard let main = swatches.first else { return [] }
        var themes: [Theme] = []

        func add(_ name: String, _ background: RGB, second: RGB? = nil, accentFrom: RGB?) {
            let t = theme(named: name, background: background, second: second, accentFrom: accentFrom)
            let alike = themes.contains {
                ColorMath.lab($0.background).distance(to: ColorMath.lab(t.background)) < 0.045
                    && ColorMath.lab($0.background2 ?? $0.background)
                        .distance(to: ColorMath.lab(t.background2 ?? t.background)) < 0.06
            }
            if !alike { themes.append(t) }
        }

        func differs(_ a: RGB, _ b: RGB) -> Bool {
            ColorMath.lab(a).distance(to: ColorMath.lab(b)) >= 0.08
        }
        // How colourful a swatch is, weighed against how much of the picture it covers.
        func vividness(_ s: Swatch) -> Double { ColorMath.lab(s.color).chroma * s.share.squareRoot() }

        let others = swatches.dropFirst().filter { differs($0.color, main.color) }
        let second = others.first
        let vividOther = others.filter { ColorMath.lab($0.color).chroma >= 0.04 }.max { vividness($0) < vividness($1) }
        let colourful = swatches.filter { ColorMath.lab($0.color).chroma >= 0.04 }
        let vivid = vividOther ?? colourful.max { vividness($0) < vividness($1) }
        let lightest = swatches.max { ColorMath.lab($0.color).l < ColorMath.lab($1.color).l } ?? main
        let darkest = swatches.min { ColorMath.lab($0.color).l < ColorMath.lab($1.color).l } ?? main

        add("Blend in", main.color, accentFrom: vividOther?.color ?? second?.color)
        if let v = vividOther {
            add("Stand out", v.color, accentFrom: main.color)
        }
        if let s = second {
            add("Two-tone", main.color, second: s.color, accentFrom: vividOther?.color)
            add("Second colour", s.color, accentFrom: main.color)
        }
        let deepBase = (vivid ?? darkest).color
        add("Deep", ColorMath.withLightness(deepBase, 0.24), accentFrom: ColorMath.withLightness(deepBase, 0.8))
        let lightBase = (vivid ?? lightest).color
        add("Light", ColorMath.withLightness(lightBase, 0.94), accentFrom: ColorMath.withLightness(lightBase, 0.5))
        return themes
    }
}
