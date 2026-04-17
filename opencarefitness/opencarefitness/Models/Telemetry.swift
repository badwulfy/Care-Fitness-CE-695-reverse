//
//  Telemetry.swift
//  opencarefitness
//
//  Real-time telemetry data decoded from the elliptical BLE frames.
//

import Foundation

/// Live telemetry snapshot from the Care CE-695.
@Observable
final class Telemetry {
    var speedKmh: Double = 0.0     // km/h (Page A)
    var rpm: Int = 0               // cadence (Page B)
    var distance: Int = 0          // cumulative (unit TBD)
    var calories: Int = 0          // cumulative
    var heartRate: Int = 0         // bpm (decimal, not BCD)
    var watts: Int = 0             // instant power
    var lastUpdate: Date = .distantPast
    var isReceiving: Bool = false

    /// Decode BCD byte → decimal value.
    static func bcd(_ byte: UInt8) -> Int {
        Int(byte >> 4) * 10 + Int(byte & 0x0F)
    }

    /// Parse a 12-byte telemetry frame (header 0x20).
    func parse(data: Data) {
        guard data.count >= 12, data[0] == 0x20 else { return }

        // Checksum verification
        let calcChk = data[0..<11].reduce(0, &+) & 0xFF
        guard calcChk == data[11] else { return }

        let isPageA = data[1] == 0x00
        let b3Value = Self.bcd(data[2]) * 100 + Self.bcd(data[3])
        let dist    = Self.bcd(data[4]) * 100 + Self.bcd(data[5])
        let cal     = Self.bcd(data[6]) * 100 + Self.bcd(data[7])
        let hr      = Int(data[8]) // decimal, pas BCD
        let w       = Self.bcd(data[9]) * 100 + Self.bcd(data[10])

        if isPageA {
            speedKmh = Double(b3Value) / 10.0
        } else {
            rpm = b3Value
        }

        distance = dist
        calories = cal
        if hr > 0 { heartRate = hr }
        watts = w
        lastUpdate = Date()
        isReceiving = true
    }
}
