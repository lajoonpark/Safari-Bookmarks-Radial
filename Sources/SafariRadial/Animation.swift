import Foundation

/// A critically damped spring, integrated per frame.
///
/// Springs (rather than eased curves) are what make the radial feel good: hover follows the
/// cursor with a little weight, and opening overshoots slightly before settling.
struct SpringValue {
    var target: Double
    private(set) var value: Double
    private var velocity: Double

    var stiffness: Double
    var damping: Double

    init(_ value: Double = 0, stiffness: Double = 360, damping: Double = 26) {
        self.target = value
        self.value = value
        self.velocity = 0
        self.stiffness = stiffness
        self.damping = damping
    }

    var isAnimating: Bool {
        abs(target - value) > 0.0005 || abs(velocity) > 0.0005
    }

    /// Advances by `dt` seconds and returns the new value.
    @discardableResult
    mutating func step(_ dt: Double) -> Double {
        // Sub-step so a hitchy frame cannot make the spring explode.
        let clamped = min(dt, 1.0 / 30.0)
        let steps = max(1, Int((clamped / (1.0 / 240.0)).rounded(.up)))
        let h = clamped / Double(steps)
        for _ in 0..<steps {
            let force = stiffness * (target - value) - damping * velocity
            velocity += force * h
            value += velocity * h
        }
        if !isAnimating {
            value = target
            velocity = 0
        }
        return value
    }

    mutating func snap(to newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0
    }
}

enum Easing {
    /// Overshoots past 1 then settles — used for the menu's open pop.
    static func outBack(_ t: Double, overshoot: Double = 1.7) -> Double {
        let c = overshoot
        let p = t - 1
        return 1 + (c + 1) * p * p * p + c * p * p
    }

    static func outCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// Decelerates hard at the end. Used for the bezel sweep, which should shoot off and settle.
    static func outQuint(_ t: Double) -> Double {
        1 - pow(1 - t, 5)
    }

    static func inCubic(_ t: Double) -> Double {
        t * t * t
    }

    static func inOutSine(_ t: Double) -> Double {
        -(cos(.pi * t) - 1) / 2
    }

    static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }
}

/// Drives per-frame redraws while anything is moving. Deliberately idle when the menu is
/// closed so the app costs nothing in the background.
final class FrameDriver {
    private var timer: Timer?
    private var tick: ((Double) -> Void)?

    var isRunning: Bool { timer != nil }

    func start(_ onTick: @escaping (Double) -> Void) {
        tick = onTick
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self, let tick = self.tick else { return }
            tick(1.0 / 120.0)
        }
        // .common keeps animation alive while a menu or resize is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tick = nil
    }
}
