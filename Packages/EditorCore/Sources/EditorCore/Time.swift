import CoreMedia

public extension CMTime {
    /// Rounds to the nearest frame at the project frame rate, so edits always land on whole frames.
    func snappedToFrame(rate: Int32 = Project.frameRate) -> CMTime {
        guard isNumeric else { return self }
        return convertScale(rate, method: .roundHalfAwayFromZero)
    }

    /// Duration of a single frame at the project frame rate.
    static var oneFrame: CMTime { CMTime(value: 1, timescale: Project.frameRate) }
}

public enum TimeFormat {
    /// "m:ss.t", e.g. "0:07.4". Tenths are precise enough to talk about a Short and easy to read.
    /// Rounded to the nearest tenth, so the lengths of split clips add up to the original.
    public static func string(_ time: CMTime) -> String {
        guard time.isNumeric, time > .zero else { return "0:00.0" }
        let tenths = Int(time.convertScale(10, method: .roundHalfAwayFromZero).value)
        return "\(tenths / 600):\(String(format: "%02d", (tenths / 10) % 60)).\(tenths % 10)"
    }
}

/// How a `CMTime` is stored in a project file: an exact fraction, never rounded seconds.
struct StoredTime: Codable {
    var value: Int64
    var timescale: Int32

    init(_ time: CMTime) {
        value = time.value
        timescale = time.timescale
    }

    var time: CMTime { CMTime(value: value, timescale: timescale) }
}

extension KeyedEncodingContainer {
    mutating func encode(time: CMTime, forKey key: Key) throws {
        try encode(StoredTime(time), forKey: key)
    }
}

extension KeyedDecodingContainer {
    func decodeTime(forKey key: Key) throws -> CMTime {
        try decode(StoredTime.self, forKey: key).time
    }
}

public extension CMTime {
    /// The same length the other way, e.g. a move to the left.
    static prefix func - (time: CMTime) -> CMTime {
        CMTimeMultiply(time, multiplier: -1)
    }
}

public extension CMTime {
    /// Kept between `lower` and `upper`. Unlike `CMTimeClampToRange`, an empty range (lower ==
    /// upper) gives that time rather than an invalid one.
    func clamped(_ lower: CMTime, _ upper: CMTime) -> CMTime {
        Swift.min(Swift.max(self, lower), Swift.max(lower, upper))
    }
}
