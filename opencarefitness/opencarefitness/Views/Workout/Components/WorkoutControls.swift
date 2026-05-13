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

            Spacer().frame(maxWidth: .infinity)

            // Pause / Resume
            Button {
                withAnimation {
                    if engine.isPaused {
                        engine.resume()
                        ble.targetResistance = engine.currentResistance
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(engine.isPaused ? AnyShapeStyle(.black) : AnyShapeStyle(Color.neonYellow))
                .padding(.horizontal, 24)
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
}
