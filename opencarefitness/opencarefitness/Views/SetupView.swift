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

                // MARK: - Pattern Grid (inside glass section)
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
                // MARK: - Duration Picker (animé)
                if engine.goalType == .duration {
                    SectionCard(title: "Durée") {
                        VStack(alignment: .leading, spacing: 16) {
                            // Large duration display
                            HStack(alignment: .center, spacing: 20) {
                                StepperButton(icon: "minus") {
                                    if durationMinutes > 1 {
                                        withAnimation(.spring(response: 0.2)) {
                                            durationMinutes -= 1
                                            engine.goalDurationSeconds = durationMinutes * 60
                                        }
                                    }
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(durationMinutes)")
                                        .font(.system(size: 52, weight: .heavy, design: .monospaced))
                                        .neonGlow(.neonCyan)
                                        .contentTransition(.numericText())
                                    Text("min")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(minWidth: 80)

                                StepperButton(icon: "plus") {
                                    withAnimation(.spring(response: 0.2)) {
                                        durationMinutes += 1
                                        engine.goalDurationSeconds = durationMinutes * 60
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach([10, 20, 30, 45, 60, 90], id: \.self) { mins in
                                        GoalChip(
                                            value: mins,
                                            suffix: "min",
                                            isSelected: durationMinutes == mins
                                        ) {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                                durationMinutes = mins
                                                engine.goalDurationSeconds = mins * 60
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                            .padding(.horizontal, -16)
                            .mask {
                                HStack(spacing: 0) {
                                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: 24)
                                    Rectangle()
                                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: 24)
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                }

                // MARK: - Distance Selection
                if engine.goalType == .distance {
                    SectionCard(title: "Distance") {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 20) {
                                StepperButton(icon: "minus") {
                                    if distanceKm > 0.5 {
                                        withAnimation(.spring(response: 0.2)) {
                                            distanceKm -= 0.5
                                            engine.goalDistanceHm = Int(distanceKm * 10)
                                        }
                                    }
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(distanceKm, format: .number.precision(.fractionLength(0...1)))
                                        .font(.system(size: 52, weight: .heavy, design: .monospaced))
                                        .neonGlow(.neonCyan)
                                        .contentTransition(.numericText())
                                    Text("km")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(minWidth: 100)

                                StepperButton(icon: "plus") {
                                    withAnimation(.spring(response: 0.2)) {
                                        distanceKm += 0.5
                                        engine.goalDistanceHm = Int(distanceKm * 10)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            // Quick-select chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach([1, 2, 4, 5, 10, 15, 21, 42], id: \.self) { km in
                                        GoalChip(
                                            value: km,
                                            suffix: "km",
                                            isSelected: Int(distanceKm) == km && distanceKm.truncatingRemainder(dividingBy: 1) == 0
                                        ) {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                                distanceKm = Double(km)
                                                engine.goalDistanceHm = km * 10
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 32)
                            }
                            .padding(.horizontal, -16)
                            .mask {
                                HStack(spacing: 0) {
                                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: 32)
                                    Rectangle()
                                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: 32)
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                }

                // MARK: - Start Button
                StartButton(ble: ble) {
                    engine.goalDurationSeconds = durationMinutes * 60
                    engine.goalDistanceHm = Int(distanceKm * 10)
                    onStart()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            // ContentView's safeAreaInset handles clearance for pill + tab bar;
            // these are just visual breathing room.
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
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

// MARK: - Pattern Card

private struct PatternCard: View {
    let pattern: WorkoutPattern
    let isSelected: Bool
    let difficulty: WorkoutDifficulty

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: pattern.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.neonCyan : .white.opacity(0.6))
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.neonCyan)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pattern.rawValue)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            PatternPreviewChart(
                pattern: pattern,
                isSelected: isSelected,
                difficulty: difficulty
            )
            .frame(height: 48)

            Text(pattern.description)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? Color.neonCyan.opacity(0.12)
                        : Color.white.opacity(0.04)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.neonCyan.opacity(0.55)
                                : Color.white.opacity(0.07),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(
            color: isSelected ? Color.neonCyan.opacity(0.15) : .clear,
            radius: 12
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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

// MARK: - Goal Chip

private struct GoalChip: View {
    let value: Int
    let suffix: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value) \(suffix)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.neonCyan.opacity(0.2)
                                : Color.white.opacity(0.06)
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected
                                        ? Color.neonCyan.opacity(0.5)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        }
                }
                .foregroundStyle(
                    isSelected ? Color.neonCyan : .white.opacity(0.45)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Start Button

private struct StartButton: View {
    var ble: BluetoothManager
    let action: () -> Void

    private var isEnabled: Bool {
        ble.connectionState == .connected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("DÉMARRER")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(isEnabled ? Color.neonCyan : Color.white.opacity(0.1))
            }
            .foregroundStyle(isEnabled ? .black : .white.opacity(0.25))
            .shadow(
                color: isEnabled ? Color.neonCyan.opacity(0.45) : .clear,
                radius: 20, y: 8
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - Stepper Button

private struct StepperButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }
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
