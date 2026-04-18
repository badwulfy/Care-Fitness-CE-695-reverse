//
//  SetupView.swift
//  opencarefitness
//
//  Pre-workout configuration: pattern selection, difficulty, goal type/duration,
//  and start button — designed with Liquid Glass best practices.
//

import SwiftUI

struct SetupView: View {
    @Environment(PatternEngine.self) private var engine
    @Environment(BluetoothManager.self) private var ble
    
    var onStart: () -> Void

    @State private var durationMinutes: Int = 10
    @State private var distanceKm: Double = 5.0

    // Computed grid layout:
    // 4 columns on iPad prevents severely stretched cards, 2 columns on iPhone.
    private var columns: [GridItem] {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        }
        #endif
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Hero Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Préparation")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Choisis ton programme et configure ta séance.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                // MARK: - Pattern Grid
                SectionCard(title: "Programme") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(WorkoutPattern.allCases) { pattern in
                            PatternCard(
                                pattern: pattern,
                                isSelected: engine.selectedPattern == pattern,
                                difficulty: engine.difficulty
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    engine.selectedPattern = pattern
                                }
                            }
                        }
                    }
                }

                // MARK: - Difficulty
                SectionCard(title: "Niveau de difficulté") {
                    HStack(spacing: 8) {
                        ForEach(WorkoutDifficulty.allCases, id: \.rawValue) { diff in
                            GoalTypeButton(
                                title: diff.rawValue,
                                isSelected: engine.difficulty == diff
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    engine.difficulty = diff
                                }
                            }
                        }
                    }
                }

                // MARK: - Goal Type
                SectionCard(title: "Type d'objectif") {
                    HStack(spacing: 8) {
                        ForEach(WorkoutGoalType.allCases, id: \.rawValue) { goal in
                            GoalTypeButton(
                                title: goal.rawValue,
                                isSelected: engine.goalType == goal
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    engine.goalType = goal
                                }
                            }
                        }
                    }
                }

                // MARK: - Duration Selector
                if engine.goalType == .duration {
                    SectionCard(title: "Durée") {
                        GoalSelector(
                            title: "Durée",
                            value: durationBinding,
                            unit: "min",
                            range: 1...120,
                            step: 1,
                            quickSelects: [10, 20, 30, 45, 60, 90],
                            format: { "\(Int($0))" },
                            onUpdate: { engine.goalDurationSeconds = Int($0) * 60 }
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: - Distance Selector
                if engine.goalType == .distance {
                    SectionCard(title: "Distance") {
                        GoalSelector(
                            title: "Distance",
                            value: $distanceKm,
                            unit: "km",
                            range: 0.5...100,
                            step: 0.5,
                            quickSelects: [1, 2, 4, 5, 10, 15, 21, 42],
                            format: { String(format: "%.1f", $0) },
                            onUpdate: { engine.goalDistanceHm = Int($0 * 10) }
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: - Start Button
                StartButton {
                    engine.goalDurationSeconds = Int(durationMinutes) * 60
                    engine.goalDistanceHm = Int(distanceKm * 10)
                    onStart()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
    
    // Helper to bridge @State to Double for GoalSelector
    private var durationBinding: Binding<Double> {
        Binding(
            get: { Double(durationMinutes) },
            set: { durationMinutes = Int($0) }
        )
    }
}

// MARK: - Section Card

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.5)

            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - Goal Type Button

private struct GoalTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.neonCyan.opacity(0.18)
                                : Color.white.opacity(0.06)
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected
                                        ? Color.neonCyan.opacity(0.4)
                                        : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        }
                }
                .foregroundStyle(isSelected ? Color.neonCyan : .white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Setup — iPhone") {
    SetupView(onStart: { })
        .environment(PatternEngine())
        .environment(BluetoothManager())
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Setup — iPad Landscape", traits: .landscapeLeft) {
    SetupView(onStart: { })
        .environment(PatternEngine())
        .environment(BluetoothManager())
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
