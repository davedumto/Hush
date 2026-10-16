import CoreGraphics
import Foundation

/// Damped-spring resize math, ported from vorssaint-utils's NotchMotion (Services/Notch/
/// NotchSupport.swift). Pure — no AppKit, no Core Animation — so NotchSilhouetteView can build
/// exact keyframes from it. Growing swings slightly past its target; shrinking never does.
enum IslandMotion {
    struct Spring: Equatable {
        /// Perceptual duration and bounce, as SwiftUI/Core Animation define them.
        var duration: TimeInterval
        var bounce: Double

        /// Progress from rest at 0 toward 1.
        func progress(at time: TimeInterval) -> Double {
            guard time > 0 else { return 0 }
            let natural = 2 * Double.pi / duration
            let damping = 1 - bounce
            if damping >= 1 { return 1 - exp(-natural * time) * (1 + natural * time) }
            let damped = natural * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * natural * time)
                * (cos(damped * time) + damping * natural / damped * sin(damped * time))
        }

        /// How far past the target the spring swings, as a share of its travel.
        var overshoot: Double {
            guard bounce > 0 else { return 0 }
            let damping = 1 - bounce
            return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
        }

        /// This spring, with only as much bounce as keeps the swing within `limit` points.
        func limited(travel: CGFloat, limit: CGFloat) -> Spring {
            guard bounce > 0, travel > 0, Double(travel) * overshoot > Double(limit) else { return self }
            let share = log(Double(max(limit, 0.01) / travel))
            return Spring(duration: duration, bounce: 1 + share / (Double.pi * Double.pi + share * share).squareRoot())
        }
    }

    static let growingWidth = Spring(duration: 0.44, bounce: 0.25)
    static let growingHeight = Spring(duration: 0.38, bounce: 0.22)
    static let shrinkingWidth = Spring(duration: 0.30, bounce: 0)
    static let shrinkingHeight = Spring(duration: 0.26, bounce: 0)
    /// The farthest a side may pass its target; the display keeps at least this much free around it.
    static let overshootLimit: CGFloat = 12
    /// Sides closer than this to their targets read as settled.
    static let settledDistance: CGFloat = 0.5

    static func spring(from: CGFloat, to: CGFloat, width: Bool) -> Spring {
        let base = to > from ? (width ? growingWidth : growingHeight) : (width ? shrinkingWidth : shrinkingHeight)
        return base.limited(travel: abs(to - from), limit: overshootLimit)
    }

    static func size(at time: TimeInterval, from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            guard start != end else { return end }
            let s = spring(from: start, to: end, width: width)
            return max(0, start + (end - start) * CGFloat(s.progress(at: time)))
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }

    /// When the size stays within `settledDistance` of its target for good. Stepped at 1/240s,
    /// matching vorssaint's own sampling rate for this search.
    static func settlingTime(from: CGSize, to: CGSize) -> TimeInterval {
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            let size = size(at: time, from: from, to: to)
            if abs(size.width - to.width) > settledDistance || abs(size.height - to.height) > settledDistance {
                settled = time + step
            }
            time += step
        }
        return settled
    }

    /// Sampled at 120Hz, ending exactly at `to`.
    static func frames(from: CGSize, to: CGSize) -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let duration = settlingTime(from: from, to: to)
        let count = max(1, Int((duration * 120).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? to : size(at: duration * $0, from: from, to: to) }
        return (sizes, keyTimes, duration)
    }

    /// Whole, equal margins around `size` so the shape keeps its exact pixels when the window
    /// returns to that size.
    static func reservation(_ reserved: CGSize, centring size: CGSize) -> CGSize {
        CGSize(width: size.width + 2 * max(0, (reserved.width - size.width) / 2).rounded(.up),
               height: max(reserved.height, size.height))
    }

    /// The largest the shape gets during the whole swing, including overshoot — what the window
    /// must be sized to before the animation starts.
    static func envelope(from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            let swing = end > start ? spring(from: start, to: end, width: width).overshoot : 0
            guard swing > 0 else { return max(start, end) }
            return (end + (end - start) * CGFloat(swing)).rounded(.up)
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
}
