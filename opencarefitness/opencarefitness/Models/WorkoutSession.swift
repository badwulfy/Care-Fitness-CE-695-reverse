//
//  WorkoutSession.swift
//  opencarefitness
//
//  SwiftData model for persisting workout history locally.
//

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var date: Date
    var patternName: String
    var durationSeconds: Int
    var distanceTotal: Int
    var caloriesTotal: Int
    var avgHeartRate: Int
    var maxHeartRate: Int
    var avgWatts: Int
    var maxWatts: Int
    var avgRPM: Int
    var maxIncline: Double

    init(
        date: Date = .now,
        patternName: String = "",
        durationSeconds: Int = 0,
        distanceTotal: Int = 0,
        caloriesTotal: Int = 0,
        avgHeartRate: Int = 0,
        maxHeartRate: Int = 0,
        avgWatts: Int = 0,
        maxWatts: Int = 0,
        avgRPM: Int = 0,
        maxIncline: Double = 0
    ) {
        self.id = UUID()
        self.date = date
        self.patternName = patternName
        self.durationSeconds = durationSeconds
        self.distanceTotal = distanceTotal
        self.caloriesTotal = caloriesTotal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.avgWatts = avgWatts
        self.maxWatts = maxWatts
        self.avgRPM = avgRPM
        self.maxIncline = maxIncline
    }
}
