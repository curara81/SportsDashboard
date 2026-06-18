#if os(watchOS)
import Foundation

/// A structured interval workout: an ordered list of steps the watch auto-advances
/// through (warmup → repeats[work + recovery] → cooldown), each step ending on a
/// distance or time goal.

enum IntervalKind {
    case warmup, work, recovery, cooldown
    var label: String {
        switch self {
        case .warmup: return "워밍업"
        case .work: return "본운동"
        case .recovery: return "회복"
        case .cooldown: return "쿨다운"
        }
    }
    /// RGB tint for the step banner.
    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .warmup: return (0.35, 0.65, 1.0)
        case .work: return (1.0, 0.35, 0.35)
        case .recovery: return (0.3, 0.85, 0.45)
        case .cooldown: return (0.7, 0.45, 1.0)
        }
    }
}

enum IntervalGoal {
    case distance(Double)    // meters
    case time(TimeInterval)  // seconds
    case open                // until the user taps Lap
}

struct IntervalStep: Identifiable {
    let id = UUID()
    let kind: IntervalKind
    let goal: IntervalGoal
    var targetPace: Double? = nil   // sec/km (optional)
}

struct IntervalWorkout: Identifiable {
    let id = UUID()
    let name: String
    let steps: [IntervalStep]   // already expanded (repeats flattened)

    /// Number of work reps, for display.
    var workReps: Int { steps.filter { $0.kind == .work }.count }
}

extension IntervalWorkout {
    static func repeatBlock(_ n: Int, work: IntervalStep, recovery: IntervalStep) -> [IntervalStep] {
        (0..<n).flatMap { _ in [work, recovery] }
    }

    /// Built-in presets (a full on-watch builder can come later).
    static let presets: [IntervalWorkout] = [
        IntervalWorkout(name: "5 × 400m", steps:
            [IntervalStep(kind: .warmup, goal: .time(600))]
            + repeatBlock(5,
                work: IntervalStep(kind: .work, goal: .distance(400)),
                recovery: IntervalStep(kind: .recovery, goal: .distance(200)))
            + [IntervalStep(kind: .cooldown, goal: .time(300))]),

        IntervalWorkout(name: "4 × 1km", steps:
            [IntervalStep(kind: .warmup, goal: .time(600))]
            + repeatBlock(4,
                work: IntervalStep(kind: .work, goal: .distance(1000)),
                recovery: IntervalStep(kind: .recovery, goal: .time(120)))
            + [IntervalStep(kind: .cooldown, goal: .time(300))]),

        IntervalWorkout(name: "피라미드", steps:
            [IntervalStep(kind: .warmup, goal: .time(600)),
             IntervalStep(kind: .work, goal: .distance(200)), IntervalStep(kind: .recovery, goal: .distance(200)),
             IntervalStep(kind: .work, goal: .distance(400)), IntervalStep(kind: .recovery, goal: .distance(200)),
             IntervalStep(kind: .work, goal: .distance(800)), IntervalStep(kind: .recovery, goal: .distance(400)),
             IntervalStep(kind: .work, goal: .distance(400)), IntervalStep(kind: .recovery, goal: .distance(200)),
             IntervalStep(kind: .work, goal: .distance(200)),
             IntervalStep(kind: .cooldown, goal: .time(300))]),
    ]
}
#endif
