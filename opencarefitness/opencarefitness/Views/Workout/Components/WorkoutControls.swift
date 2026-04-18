//
//  WorkoutControls.swift
//  opencarefitness
//

import SwiftUI

struct WorkoutControls: View {
    @Environment(PatternEngine.self) private var engine
    @Environment(BluetoothManager.self) private var ble
    @Binding var showStopConfirm: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Stop button
            Button {
                showStopConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .glassPanel(cornerRadius: 28)
            }
            .buttonStyle(.plain)

            // Override indicator / Reset
            if isOverridden {
                Button {
                    withAnimation { engine.resetOffset() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("RESET")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .glassPanel(cornerRadius: 28)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }

            // Pause / Resume
            Button {
                withAnimation {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                        // Safety: drop resistance to minimum when paused
                        ble.targetResistance = 1
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                    Text(engine.isPaused ? "REPRENDRE" : "PAUSE")
                        .font(.subheadline.weight(.bold))
                        .tracking(2)
                }
                .foregroundStyle(engine.isPaused ? AnyShapeStyle(.black) : AnyShapeStyle(Color.neonYellow))
                .padding(.horizontal, 32)
                .frame(height: 56)
                .background(
                    engine.isPaused
                        ? AnyShapeStyle(Color.neonCyan)
                        : AnyShapeStyle(.clear)
                )
                .glassPanel(cornerRadius: 28)
                .overlay(
                    Capsule()
                        .stroke(
                            engine.isPaused ? Color.clear : Color.neonYellow.opacity(0.3),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var isOverridden: Bool {
        abs(engine.difficultyMultiplier - engine.difficulty.multiplier) > 0.01
    }
}
