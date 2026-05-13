//
//  PatternChartView.swift
//  opencarefitness
//
//  Combined bar chart (planned incline profile) + line chart overlay
//  (real-time power or HR) using Swift Charts.
//

import SwiftUI
import Charts

// MARK: - Pattern Profile Chart (Workout View)

struct PatternChartView: View {
    let pattern: WorkoutPattern
    let progress: Double // 0.0–1.0
    let currentWatts: Int
    let wattsHistory: [Double] // normalized 0–1 values
    let difficultyMultiplier: Double

    private let sampleCount = 20

    var body: some View {
        let samples = pattern.previewSamples(count: sampleCount, multiplier: difficultyMultiplier)
        let currentIndex = Int(progress * Double(sampleCount))

        Chart {
            // Background bars: planned incline profile
            ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Time", index),
                    y: .value("Incline", value)
                )
                .foregroundStyle(
                    index == currentIndex
                        ? Color.neonCyan.opacity(0.8)
                        : Color.white.opacity(index < currentIndex ? 0.08 : 0.15)
                )
                .cornerRadius(2)
            }

            // Foreground line: watts history
            if !wattsHistory.isEmpty {
                ForEach(Array(wattsHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Power", value * 15.0) // scale to incline range
                    )
                    .foregroundStyle(Color.neonCyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Current position marker
            if currentIndex > 0 && currentIndex < sampleCount {
                PointMark(
                    x: .value("Time", currentIndex),
                    y: .value("Incline", samples[currentIndex])
                )
                .foregroundStyle(.white)
                .symbolSize(60)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...16)
        .chartLegend(.hidden)
    }
}

// MARK: - Mini Pattern Preview (Setup Cards)

struct PatternPreviewChart: View {
    let pattern: WorkoutPattern
    var accentColor: Color = .neonCyan
    var isSelected: Bool = false
    var difficulty: WorkoutDifficulty = .medium

    var body: some View {
        let samples = pattern.previewSamples(count: 10, difficulty: difficulty)

        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("T", String(index)),
                    y: .value("V", value)
                )
                .foregroundStyle(
                    isSelected
                        ? accentColor.opacity(0.7)
                        : Color.white.opacity(0.2)
                )
                .cornerRadius(1)
            }
            // Baseline so an all-zero pattern (Plat at Facile) still reads as
            // a chart — a thin horizontal rule at y=0.
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(isSelected ? accentColor.opacity(0.5) : Color.white.opacity(0.15))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...16)
        .chartLegend(.hidden)
    }
}
