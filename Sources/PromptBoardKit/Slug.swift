import Foundation

public enum Slug {
    public static func make(from text: String) -> String {
        let lowered = text.lowercased()
        var result = ""
        var pendingSeparator = false
        for scalar in lowered.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !result.isEmpty {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else {
                pendingSeparator = true
            }
        }
        return result.isEmpty ? "untitled" : result
    }

    public static func unique(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }
}
