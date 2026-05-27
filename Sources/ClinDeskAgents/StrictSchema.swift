import Foundation

public enum StrictSchema {
    public static let emptySchema: JSONValue = [
        "additionalProperties": false,
        "type": "object",
        "properties": [:],
        "required": []
    ]

    public static func ensureStrictJSONSchema(_ schema: JSONValue) throws -> JSONValue {
        if schema == .object([:]) {
            return emptySchema
        }
        return try ensureStrictJSONSchema(schema, path: [], root: schema)
    }

    private static func ensureStrictJSONSchema(
        _ schema: JSONValue,
        path: [String],
        root: JSONValue
    ) throws -> JSONValue {
        guard case .object(var object) = schema else {
            throw AgentsError.invalidRunConfig("Expected JSON schema object at path \(format(path)).")
        }

        if case .object(let defs)? = object["$defs"] {
            object["$defs"] = .object(try defs.mapValuesWithKey { key, value in
                try ensureStrictJSONSchema(value, path: path + ["$defs", key], root: root)
            })
        }

        if case .object(let definitions)? = object["definitions"] {
            object["definitions"] = .object(try definitions.mapValuesWithKey { key, value in
                try ensureStrictJSONSchema(value, path: path + ["definitions", key], root: root)
            })
        }

        if object["type"] == .string("object") {
            if let additionalProperties = object["additionalProperties"] {
                if additionalProperties.isTruthy {
                    throw AgentsError.invalidRunConfig(
                        "additionalProperties should not be set for object types. Use a non-strict schema if additional properties are required."
                    )
                }
            } else {
                object["additionalProperties"] = .bool(false)
            }
        }

        if case .object(let properties)? = object["properties"] {
            object["required"] = .array(properties.keys.map(JSONValue.string))
            object["properties"] = .object(try properties.mapValuesWithKey { key, value in
                try ensureStrictJSONSchema(value, path: path + ["properties", key], root: root)
            })
        }

        if let items = object["items"], case .object = items {
            object["items"] = try ensureStrictJSONSchema(items, path: path + ["items"], root: root)
        }

        if case .array(let anyOf)? = object["anyOf"] {
            object["anyOf"] = .array(try anyOf.enumerated().map { index, value in
                try ensureStrictJSONSchema(value, path: path + ["anyOf", String(index)], root: root)
            })
        }

        if case .array(let oneOf)? = object["oneOf"] {
            let existingAnyOf: [JSONValue]
            if case .array(let anyOf)? = object["anyOf"] {
                existingAnyOf = anyOf
            } else {
                existingAnyOf = []
            }
            let convertedOneOf = try oneOf.enumerated().map { index, value in
                try ensureStrictJSONSchema(value, path: path + ["oneOf", String(index)], root: root)
            }
            object["anyOf"] = .array(existingAnyOf + convertedOneOf)
            object.removeValue(forKey: "oneOf")
        }

        if case .array(let allOf)? = object["allOf"] {
            if allOf.count == 1 {
                let ensured = try ensureStrictJSONSchema(allOf[0], path: path + ["allOf", "0"], root: root)
                guard case .object(let ensuredObject) = ensured else {
                    throw AgentsError.invalidRunConfig("Expected allOf schema object at path \(format(path)).")
                }
                object.merge(ensuredObject) { _, new in new }
                object.removeValue(forKey: "allOf")
            } else {
                object["allOf"] = .array(try allOf.enumerated().map { index, value in
                    try ensureStrictJSONSchema(value, path: path + ["allOf", String(index)], root: root)
                })
            }
        }

        if object["default"] == .null {
            object.removeValue(forKey: "default")
        }

        if let ref = object["$ref"]?.stringValue, object.count > 1 {
            let resolved = try resolveRef(root: root, ref: ref)
            guard case .object(let resolvedObject) = resolved else {
                throw AgentsError.invalidRunConfig("Expected ref \(ref) to resolve to an object.")
            }
            object.removeValue(forKey: "$ref")
            var merged = resolvedObject
            merged.merge(object) { _, new in new }
            return try ensureStrictJSONSchema(.object(merged), path: path, root: root)
        }

        return .object(object)
    }

    private static func resolveRef(root: JSONValue, ref: String) throws -> JSONValue {
        guard ref.hasPrefix("#/") else {
            throw AgentsError.invalidRunConfig("Unexpected $ref format \(ref).")
        }

        var current = root
        for key in ref.dropFirst(2).split(separator: "/").map(String.init) {
            guard let next = current[key] else {
                throw AgentsError.invalidRunConfig("Could not resolve $ref \(ref).")
            }
            current = next
        }
        return current
    }

    private static func format(_ path: [String]) -> String {
        path.isEmpty ? "<root>" : path.joined(separator: ".")
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func mapValuesWithKey(_ transform: (String, JSONValue) throws -> JSONValue) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (key, value) in self {
            result[key] = try transform(key, value)
        }
        return result
    }
}

private extension JSONValue {
    var isTruthy: Bool {
        switch self {
        case .null:
            return false
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return !value.isEmpty
        case .array(let value):
            return !value.isEmpty
        case .object(let value):
            return !value.isEmpty
        }
    }
}
