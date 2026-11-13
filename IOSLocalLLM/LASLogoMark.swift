import SwiftUI

// MARK: - LASLogoMark
//
// The Local LLM Sketch mark: a minimal purple tile with a single stroked
// gesture — a freehand sketch line that resolves into a chat tail — plus one
// small dot for the caret. Two shapes and one fill, no illustration, no
// gradient mesh, so it stays crisp from 20 pt to 1024 pt.
//
// Drawn in code rather than shipped as a bitmap: the header, onboarding, and
// the splash all resize it, and a vector keeps every size sharp without a
// per-scale asset set. `Docs/Images/local-llm-sketch-mark.svg` is the matching
// source for the exported app icon.

struct LASLogoMark: View {

    var size: CGFloat = 38
    /// Solid brand fill. Pass `false` for a transparent tile whose stroke and
    /// line use the accent instead (used on tinted backgrounds).
    var filled: Bool = true
    /// Corner radius as a fraction of `size`. The app icon uses 0.225 to match
    /// Apple's superellipse closely enough at icon scale.
    var cornerFraction: CGFloat = 0.225

    /// The sketch-purple ramp. Light and dark get slightly different stops so
    /// the mark does not read as a flat blob on a dark page.
    private var topColor: Color { Color(red: 0.514, green: 0.361, blue: 0.976) }   // #835CF9
    private var bottomColor: Color { Color(red: 0.404, green: 0.184, blue: 0.902) } // #672FE6

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side * cornerFraction

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [topColor, bottomColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: max(1, side * 0.012))
                    }
                    .opacity(filled ? 1 : 0)

                LASLogoStroke()
                    .stroke(
                        filled ? Color.white : bottomColor,
                        style: StrokeStyle(
                            lineWidth: side * 0.085,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(side * 0.235)

                Circle()
                    .fill(filled ? Color.white : bottomColor)
                    .frame(width: side * 0.105, height: side * 0.105)
                    .offset(x: side * 0.215, y: side * 0.215)
                    .opacity(filled ? 0.92 : 1)
            }
            .frame(width: side, height: side)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One continuous gesture: a rising stroke that turns over at the top and
/// falls into a chat tail at the lower right.
private struct LASLogoStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.06, y: h * 0.70))
        path.addCurve(
            to: CGPoint(x: w * 0.46, y: h * 0.30),
            control1: CGPoint(x: w * 0.12, y: h * 0.16),
            control2: CGPoint(x: w * 0.32, y: h * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.78),
            control1: CGPoint(x: w * 0.74, y: h * 0.22),
            control2: CGPoint(x: w * 0.26, y: h * 0.92)
        )
        return path
    }
}

// MARK: - Wordmark

/// Mark + product name, used wherever the brand is introduced.
struct LASBrandLockup: View {
    var size: CGFloat = 34
    var showsSubtitle: Bool = true

    var body: some View {
        HStack(spacing: LASDesignTokens.row) {
            LASLogoMark(size: size)

            VStack(alignment: .leading, spacing: 1) {
                Text("Local LLM")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                if showsSubtitle {
                    Text("Sketch")
                        .font(.caption.weight(.semibold).monospaced())
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Local LLM Sketch")
        }
    }
}
