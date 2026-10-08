import os

/// Intervals show up in Instruments → "Points of Interest" (and any template once you add the os_signpost instrument).
enum Signposts {
    static let signposter = OSSignposter(subsystem: "com.example.PolyAnimLab", category: .pointsOfInterest)
}
