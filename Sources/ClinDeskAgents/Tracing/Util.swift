import Foundation

public enum TracingIDs {
    public static func genTraceID() -> String {
        "trace_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    public static func genSpanID() -> String {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "span_\(String(value.prefix(24)))"
    }

    public static func genGroupID() -> String {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "group_\(String(value.prefix(24)))"
    }

    public static func timeISO(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
