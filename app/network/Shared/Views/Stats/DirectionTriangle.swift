//
//  DirectionTriangle.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/9/26.
//

import SwiftUI

/**
 * An equilateral triangle centered in `rect`, pointing up or down.
 */
func equilateralTrianglePath(in rect: CGRect, pointsUp: Bool) -> Path {
    var path = Path()
    let cx = rect.midX
    // equilateral: height is base * sqrt(3)/2
    let height = rect.width * 0.866
    let top = rect.midY - height / 2
    let bottom = rect.midY + height / 2
    if pointsUp {
        path.move(to: CGPoint(x: cx, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom))
    } else {
        path.move(to: CGPoint(x: cx, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.minX, y: top))
    }
    path.closeSubpath()
    return path
}

/**
 * A small equilateral direction triangle with slightly rounded tips,
 * used to orient egress (up) vs ingress (down). The tips are rounded by
 * filling the triangle and stroking it with a round line join.
 */
struct DirectionTriangle: View {
    let pointsUp: Bool
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
                // inset so the round-join stroke stays inside the frame
                .insetBy(dx: 1, dy: 1)
            let triangle = equilateralTrianglePath(in: rect, pointsUp: pointsUp)
            context.fill(triangle, with: .color(color))
            context.stroke(
                triangle,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }
}
