//
//  WorkoutPattern.swift
//  opencarefitness
//
//  Predefined workout intensity patterns. Each pattern returns an incline
//  (0–15%) for a given progress (0.0–1.0) and a difficulty multiplier.
//
//  All patterns peak at <= 11.5% base incline so that even at the highest
//  difficulty multiplier (1.3 / Extreme) the shape isn't clipped by the
//  hardware ceiling of 15%.
//

import Foundation

enum WorkoutGoalType: String, CaseIterable, Codable {
    case free     = "Libre"
    case duration = "Durée"
    case distance = "Distance"
}

enum WorkoutDifficulty: String, CaseIterable, Codable {
    case easy     = "Facile"
    case medium   = "Moyen"
    case hard     = "Difficile"
    case extreme  = "Extrême"

    var multiplier: Double {
        switch self {
        case .easy:     return 0.4
        case .medium:   return 0.7
        case .hard:     return 1.0
        case .extreme:  return 1.3
        }
    }
}

enum WorkoutPattern: String, CaseIterable, Identifiable, Codable {
    case flat         = "Plat"
    case progression  = "Progression"
    case vShape       = "Vallon"
    case pyramid      = "Pyramide"
    case hiit         = "Intervalles"
    case fatBurn      = "Endurance"
    case rollingHills = "Collines"
    case random       = "Variable"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flat:         return "equal"
        case .progression:  return "arrow.up.right"
        case .vShape:       return "arrow.uturn.up"
        case .pyramid:      return "triangle"
        case .hiit:         return "bolt.fill"
        case .fatBurn:      return "flame.fill"
        case .rollingHills: return "water.waves"
        case .random:       return "dice.fill"
        }
    }

    var description: String {
        switch self {
        case .flat:         return "Sans inclinaison. Idéal pour récupération ou échauffement."
        case .progression:  return "Montée progressive du début à la fin."
        case .vShape:       return "Descente symétrique jusqu'au creux, puis remontée."
        case .pyramid:      return "Montée jusqu'au milieu, puis descente symétrique."
        case .hiit:         return "Alternance de blocs intenses et de blocs de récupération."
        case .fatBurn:      return "Échauffement, plateau aérobie, bloc tempo central, retour, cooldown."
        case .rollingHills: return "Petites collines successives qui s'enchaînent."
        case .random:       return "Pente variable, nouvelle séquence à chaque séance."
        }
    }

    // MARK: - Incline

    /// Returns incline percentage (0–15%) for a given progress and difficulty.
    func incline(at progress: Double, difficulty: WorkoutDifficulty = .hard) -> Double {
        incline(at: progress, multiplier: difficulty.multiplier)
    }

    /// `seed` is used by the `random` pattern to produce a different sequence
    /// per session. Other patterns ignore it.
    func incline(at progress: Double, multiplier: Double, seed: UInt64 = 0) -> Double {
        let t = max(0.0, min(1.0, progress))
        var base: Double = 0.0

        switch self {
        case .flat:
            base = 0.0

        case .progression:
            base = t * 11.5

        case .vShape:
            // Symmetric inverse of pyramid: descend to floor, then climb back.
            if t < 0.5 {
                base = 11.5 * (1.0 - t * 2.0)
            } else {
                base = 11.5 * ((t - 0.5) * 2.0)
            }

        case .pyramid:
            if t < 0.5 {
                base = 11.5 * (t * 2.0)
            } else {
                base = 11.5 * (1.0 - (t - 0.5) * 2.0)
            }

        case .hiit:
            // Real HIIT proportions: short sprint (~25% of cycle) + long recovery.
            let cycle = (t * 8.0).truncatingRemainder(dividingBy: 1.0)
            base = cycle < 0.25 ? 11.5 : 1.0

        case .fatBurn:
            // Stepped tempo: warmup → zone 2 → tempo block (middle) → zone 2 → cooldown.
            switch t {
            case ..<0.10: base = (t / 0.10) * 5.0                // ramp 0 → 5
            case ..<0.35: base = 5.0                             // zone 2
            case ..<0.40: base = 5.0 + ((t - 0.35) / 0.05) * 3.0 // ramp 5 → 8
            case ..<0.60: base = 8.0                             // tempo block
            case ..<0.65: base = 8.0 - ((t - 0.60) / 0.05) * 3.0 // ramp 8 → 5
            case ..<0.90: base = 5.0                             // zone 2 again
            default:      base = 5.0 * (1.0 - (t - 0.90) / 0.10) // cooldown 5 → 0
            }

        case .rollingHills:
            // 5 hills, moderate amplitude (3 → 8%) so it stays a rolling ride —
            // never punitive, never flat, distinct from HIIT spikes.
            base = 5.5 + 2.5 * sin(t * .pi * 10.0 - .pi / 2.0)

        case .random:
            let slot = min(15, Int(t * 16.0))
            base = Self.randomValue(slot: slot, seed: seed)
        }

        return min(15.0, base * multiplier)
    }

    /// Deterministic per-(seed, slot) value in [0, 11.5]. SplitMix-style hash
    /// so a session seed produces a unique-looking sequence without state.
    private static func randomValue(slot: Int, seed: UInt64) -> Double {
        var x = (UInt64(bitPattern: Int64(slot)) &+ 1) &* 0x9E3779B97F4A7C15 &+ seed
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 12)   // 0…11
    }

    // MARK: - Preview / chart axis

    /// Sample preview for setup cards. Uses a fixed seed for visual stability.
    func previewSamples(count: Int = 10, difficulty: WorkoutDifficulty = .medium) -> [Double] {
        previewSamples(count: count, multiplier: difficulty.multiplier)
    }

    func previewSamples(count: Int = 10, multiplier: Double) -> [Double] {
        (0..<count).map { i in
            incline(at: Double(i) / Double(count), multiplier: multiplier, seed: 42)
        }
    }

    /// Maximum base incline (pre-multiplier) — used by PatternEngine to cap
    /// manual increments and by chart code to size the y-axis.
    var maxBaseIncline: Double {
        switch self {
        case .flat:         return 0.0
        case .progression:  return 11.5
        case .vShape:       return 11.5
        case .pyramid:      return 11.5
        case .hiit:         return 11.5
        case .fatBurn:      return 8.0
        case .rollingHills: return 8.0
        case .random:       return 11.5
        }
    }
}
