//
//  WorkoutHeader.swift
//  opencarefitness
//

import SwiftUI

struct WorkoutHeader: View {
    @Environment(PatternEngine.self) private var engine
    @Binding var selectedMetric: WorkoutView.ChartMetric
    let isPad: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPad {
                // Header: Spacious single-line layout for iPad
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROFIL & TÉLÉMÉTRIE")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Picker("Metric", selection: $selectedMetric) {
                                ForEach(WorkoutView.ChartMetric.allCases) { metric in
                                    Text(metric.rawValue).tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 300)

                            Label("Projection", systemImage: "square.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Incline display
                    inclineDisplay(large: true)
                }
            } else {
                // Header: Compact two-line layout for iPhone
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("PROFIL & TÉLÉMÉTRIE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        inclineDisplay(large: false)
                    }

                    HStack(spacing: 16) {
                        Label("Projection", systemImage: "square.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))

                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(WorkoutView.ChartMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
    }
    
    private func inclineDisplay(large: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("PENTE")
                .font(.system(size: large ? 12 : 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: large ? 4 : 2) {
                Text(String(format: "%.1f", engine.currentIncline))
                    .font(.system(size: large ? 48 : 32, weight: .bold, design: .monospaced))
                    .neonGlow(.neonCyan)
                Text("%")
                    .font(.system(size: large ? 20 : 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
