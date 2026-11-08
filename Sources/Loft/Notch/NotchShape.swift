import SwiftUI

/// The iPhone-style island silhouette: flared top corners that merge into the bezel,
/// rounded bottom corners. Derived from DynamicNotchKit (MIT).
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    /// When set (open panel on a notched display) only this much of the top band is drawn, centred
    /// on the notch; the body widens below `headHeight`. Menu bar items beside the notch stay visible.
    var headWidth: CGFloat? = nil
    var headHeight: CGFloat = 0
    var bodyTopRadius: CGFloat = 18

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14, headWidth: CGFloat? = nil, headHeight: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.headWidth = headWidth
        self.headHeight = headHeight
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(topCornerRadius, bottomCornerRadius), .init(headWidth ?? -1, headHeight)) }
        set {
            topCornerRadius = newValue.first.first; bottomCornerRadius = newValue.first.second
            headWidth = newValue.second.first < 0 ? nil : newValue.second.first; headHeight = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if let hw = headWidth, hw < rect.width - 8, headHeight > 0, rect.height > headHeight + 8 {
            return hangingPath(in: rect, headWidth: hw)
        }
        var p = Path()
        let t = min(topCornerRadius, rect.width / 4)
        let b = min(bottomCornerRadius, rect.height, rect.width / 2 - t)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }

    /// Notch-wide head with the usual flares, concave fillets into a full-width body with rounded corners.
    private func hangingPath(in rect: CGRect, headWidth hw: CGFloat) -> Path {
        var p = Path()
        let hx0 = rect.midX - hw / 2, hx1 = rect.midX + hw / 2
        let hh = rect.minY + headHeight
        let t = min(topCornerRadius, hw / 4)
        let wing = hx0 - rect.minX - t                        // horizontal room between head side and body edge
        let f = max(0, min(10, headHeight / 2, wing / 2))     // concave fillet at the junction
        let r = max(0, min(bodyTopRadius, wing - f, (rect.maxY - hh) / 2))
        let b = min(bottomCornerRadius, (rect.maxY - hh) / 2, rect.width / 2)
        p.move(to: CGPoint(x: hx0, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: hx0 + t, y: rect.minY + t), control: CGPoint(x: hx0 + t, y: rect.minY))
        p.addLine(to: CGPoint(x: hx0 + t, y: hh - f))
        p.addQuadCurve(to: CGPoint(x: hx0 + t - f, y: hh), control: CGPoint(x: hx0 + t, y: hh))
        p.addLine(to: CGPoint(x: rect.minX + r, y: hh))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: hh + r), control: CGPoint(x: rect.minX, y: hh))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + b, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - b), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: hh + r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: hh), control: CGPoint(x: rect.maxX, y: hh))
        p.addLine(to: CGPoint(x: hx1 - t + f, y: hh))
        p.addQuadCurve(to: CGPoint(x: hx1 - t, y: hh - f), control: CGPoint(x: hx1 - t, y: hh))
        p.addLine(to: CGPoint(x: hx1 - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: hx1, y: rect.minY), control: CGPoint(x: hx1 - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Lays two views around the hardware notch with equal room on both sides, each hugging the notch
/// edge, so the pill stays centred on the notch and nothing is ever drawn under it.
struct NotchSides: Layout {
    var gap: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let a = subviews.indices.contains(0) ? subviews[0].sizeThatFits(.unspecified) : .zero
        let b = subviews.indices.contains(1) ? subviews[1].sizeThatFits(.unspecified) : .zero
        let w = max(a.width, b.width)
        return CGSize(width: w * 2 + gap, height: proposal.height ?? max(a.height, b.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if subviews.indices.contains(0) {
            let a = subviews[0].sizeThatFits(.unspecified)
            subviews[0].place(at: CGPoint(x: bounds.midX - gap / 2, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(a))
        }
        if subviews.indices.contains(1) {
            let b = subviews[1].sizeThatFits(.unspecified)
            subviews[1].place(at: CGPoint(x: bounds.midX + gap / 2, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(b))
        }
    }
}

/// Floating pill used on displays without a notch.
struct PillShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.height / 2, 22))
    }
}
