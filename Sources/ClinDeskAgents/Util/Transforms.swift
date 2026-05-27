import Foundation

public enum TransformUtils {
    public static func transformStringFunctionStyle(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> UnicodeScalar in
            switch scalar.value {
            case 65...90:
                return UnicodeScalar(scalar.value + 32)!
            case 97...122, 48...57, 95:
                return scalar
            case 32:
                return "_"
            default:
                return "_"
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
