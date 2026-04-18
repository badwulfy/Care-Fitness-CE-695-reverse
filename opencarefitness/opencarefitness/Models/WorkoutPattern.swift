//
//  WorkoutPattern.swift
//  opencarefitness
//
//  Predefined workout intensity patterns (9 types).
//  Each pattern returns an incline (0–15%) for a given progress (0.0–1.0).
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
    case hiit         = "HIIT"
    case fatBurn      = "Combustion"
    case rollingHills = "Collines"
    case random       = "Aléatoire"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flat:         return "equal"
        case .progression:  return "arrow.up.right"
        case .vShape:       return "chevron.down"
        case .pyramid:      return "triangle"
        case .hiit:         return "bolt.fill"
        case .fatBurn:      return "flame.fill"
        case .rollingHills: return "water.waves"
        case .random:       return "dice.fill"
        }
    }

    var description: String {
        switch self {
        case .flat:         return "Intensité constante à 0%."
        case .progression:  return "Montée progressive du début à la fin."
        case .vShape:       return "Descente puis remontée brutale en fin de séance."
        case .pyramid:      return "Montée jusqu'au milieu, puis descente symétrique."
        case .hiit:         return "Alternance de blocs intenses et de repos."
        case .fatBurn:      return "Montée rapide, haut plateau prolongé en zone aérobie."
        case .rollingHills: return "Vagues fluides alternant ascensions et descentes."
        case .random:       return "Pente aléatoire sur des cycles aléatoires."
        }
    }

    /// Returns incline percentage (0–15%) for a given progress (0.0–1.0) and difficulty.
    func incline(at progress: Double, difficulty: WorkoutDifficulty = .hard) -> Double {
        incline(at: progress, multiplier: difficulty.multiplier)
    }

    func incline(at progress: Double, multiplier: Double) -> Double {
        let t = max(0.0, min(1.0, progress))
        var base: Double = 0.0

        switch self {
        case .flat:
            base = 4.0

        case .progression:
            base = t * 15.0

        case .vShape:
            // Soft V-Shape: Descent, plateau, then steady ascent
            if t < 0.4 {
                base = 8.0 * (1.0 - t / 0.4)
            } else if t < 0.6 {
                base = 0.0
            } else {
                base = 12.0 * ((t - 0.6) / 0.4)
            }

        case .pyramid:
            if t < 0.5 {
                base = 12.0 * (t * 2.0)
            } else {
                base = 12.0 * (1.0 - (t - 0.5) * 2.0)
            }

        case .hiit:
            let cycle = (t * 8.0).truncatingRemainder(dividingBy: 1.0)
            base = cycle < 0.5 ? 12.0 : 2.0

        case .fatBurn:
            if t < 0.1 {
                base = (t / 0.1) * 8.0
            } else if t < 0.9 {
                base = 8.0
            } else {
                base = 8.0 * (1.0 - (t - 0.9) / 0.1)
            }


        case .rollingHills:
            base = 6.0 + 6.0 * sin(t * .pi * 4.0 - .pi / 2.0)

        case .random:
            let slot = Int(t * 16.0) % 16
            let precomputed: [Double] = [3, 11, 5, 12, 2, 9, 7, 10, 1, 12, 6, 8, 4, 11, 8, 0]
            base = precomputed[slot]
        }
        
        return min(15.0, base * multiplier)
    }

    /// Generate sample preview data for the setup cards using an enum.
    func previewSamples(count: Int = 10, difficulty: WorkoutDifficulty = .medium) -> [Double] {
        previewSamples(count: count, multiplier: difficulty.multiplier)
    }

    /// Generate sample preview data using a raw multiplier.
    func previewSamples(count: Int = 10, multiplier: Double) -> [Double] {
        (0..<count).map { i in
            incline(at: Double(i) / Double(count), multiplier: multiplier)
        }
    }

    /// The maximum base incline (before multiplier) for this pattern.
    var maxBaseIncline: Double {
        switch self {
        case .flat: return 4.0
        case .progression: return 15.0
        case .vShape: return 12.0
        case .pyramid: return 12.0
        case .hiit: return 12.0
        case .fatBurn: return 8.0
        case .rollingHills: return 12.0
        case .random: return 12.0
        }
    }
}
