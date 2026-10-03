import Foundation

/// Sensor feature: shake to undo.
///
/// Turns raw accelerometer readings (in g, gravity included, so a phone lying
/// still reads 1 g) into "the user shook the phone". A shake is two strong jolts
/// within one second; a single bump or a step while walking does not count.
struct ShakeDetector {
    /// How hard a jolt must be, in g.
    static let thresholdG = 2.7
    /// Readings closer together than this belong to the same jolt.
    static let joltSpacingMs: Int64 = 100
    /// Both jolts must happen inside this window.
    static let windowMs: Int64 = 1000
    static let joltsNeeded = 2
    /// After a shake, ignore movement for this long so one shake undoes once.
    static let cooldownMs: Int64 = 1500

    private var jolts = 0
    private var firstJoltAt: Int64 = 0
    private var lastJoltAt: Int64?
    private var lastShakeAt: Int64?

    /// Feeds one reading; returns true when it completes a shake.
    mutating func register(x: Double, y: Double, z: Double, atMillis: Int64) -> Bool {
        let force = (x * x + y * y + z * z).squareRoot()
        guard force >= Self.thresholdG else { return false }
        if let lastShakeAt, atMillis - lastShakeAt < Self.cooldownMs { return false }
        if let lastJoltAt, atMillis - lastJoltAt < Self.joltSpacingMs { return false }

        if jolts == 0 || atMillis - firstJoltAt > Self.windowMs {
            jolts = 0
            firstJoltAt = atMillis
        }
        jolts += 1
        lastJoltAt = atMillis

        if jolts >= Self.joltsNeeded {
            jolts = 0
            lastJoltAt = nil
            lastShakeAt = atMillis
            return true
        }
        return false
    }
}
