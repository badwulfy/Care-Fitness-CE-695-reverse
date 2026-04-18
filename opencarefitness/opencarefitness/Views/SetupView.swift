//
//  SetupView.swift
//  opencarefitness
//
//  Pre-workout configuration: pattern selection, goal type/duration,
//  and start button.
//

import SwiftUI

struct SetupView: View {
    @Bindable var engine: PatternEngine
    var bleManager: BluetoothManager
    var onStart: () -> Void

    @State private var durationMinutes: Int = 10

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 300), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("Préparation")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                    Text("Choisis ton programme et configure ta séance.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // MARK: - Pattern Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(WorkoutPattern.allCases) { pattern in
                        PatternCard(
                            pattern: pattern,
                            isSelected: engine.selectedPattern == pattern,
                            difficulty: engine.difficulty
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                engine.selectedPattern = pattern
                            }
                        }
                    }
                }

                // MARK: - Difficulty Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Niveau de difficulté")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(WorkoutDifficulty.allCases, id: \.rawValue) { diff in
                            GoalTypeButton(
                                title: diff.rawValue,
                                isSelected: engine.difficulty == diff
                            ) {
                                withAnimation { engine.difficulty = diff }
                            }
                        }
                    }
                }

                // MARK: - Goal Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Type d'objectif")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    // Goal type picker
                    HStack(spacing: 8) {
                        ForEach(WorkoutGoalType.allCases, id: \.rawValue) { goal in
                            GoalTypeButton(
                                title: goal.rawValue,
                                isSelected: engine.goalType == goal
                            ) {
                                withAnimation { engine.goalType = goal }
                            }
                        }
                    }
                }

                // Duration selector (only for duration goal)
                if engine.goalType == .duration {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Durée de l'objectif")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(durationMinutes) min")
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .neonGlow(.neonCyan)
                                .lineLimit(1)
                        }

                        // Quick duration buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach([10, 20, 30, 40, 50, 60], id: \.self) { mins in
                                    Button {
                                        withAnimation {
                                            durationMinutes = mins
                                            engine.goalDurationSeconds = mins * 60
                                        }
                                    } label: {
                                        Text("\(mins)")
                                            .font(.callout.weight(.bold).monospacedDigit())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                durationMinutes == mins
                                                    ? Color.neonCyan.opacity(0.2)
                                                    : Color.white.opacity(0.05)
                                            )
                                            .foregroundStyle(
                                                durationMinutes == mins
                                                    ? Color.neonCyan
                                                    : .secondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(
                                                        durationMinutes == mins
                                                            ? Color.neonCyan.opacity(0.4)
                                                            : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20) // Space for the symmetrical fade
                        }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.08),
                                    .init(color: .black, location: 0.92),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                    .padding(24)
                    .glassPanel()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }

                // MARK: - Start Button
                HStack {
                    Spacer()

                    Button(action: {
                        engine.goalDurationSeconds = durationMinutes * 60
                        onStart()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                                .font(.title2)
                            Text("DÉMARRER")
                                .font(.title3.weight(.bold))
                                .tracking(2)
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 18)
                        .background(Color.neonCyan)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                        .shadow(color: Color.neonCyan.opacity(0.4), radius: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(bleManager.connectionState != .connected)
                    .opacity(bleManager.connectionState == .connected ? 1.0 : 0.4)

                    Spacer()
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Pattern Card

private struct PatternCard: View {
    let pattern: WorkoutPattern
    let isSelected: Bool
    let difficulty: WorkoutDifficulty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: pattern.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.neonCyan : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.neonCyan)
                }
            }

            Text(pattern.rawValue)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            PatternPreviewChart(
                pattern: pattern,
                isSelected: isSelected,
                difficulty: difficulty
            )
            .frame(height: 60)

            Text(pattern.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .glassPanel(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected ? Color.neonCyan.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected
                        ? Color.neonCyan.opacity(0.2)
                        : Color.white.opacity(0.05)
                )
                .foregroundStyle(isSelected ? Color.neonCyan : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.neonCyan.opacity(0.3) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Setup — iPhone") {
    SetupView(
        engine: PatternEngine(),
        bleManager: BluetoothManager(),
        onStart: { }
    )
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Setup — iPad Landscape", traits: .landscapeLeft) {
    SetupView(
        engine: PatternEngine(),
        bleManager: BluetoothManager(),
        onStart: { }
    )
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
