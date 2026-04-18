//
//  StartButton.swift
//  opencarefitness
//

import SwiftUI

struct StartButton: View {
    @Environment(BluetoothManager.self) private var ble
    let action: () -> Void

    private var isEnabled: Bool {
        ble.effectiveConnectionState == .connected
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
