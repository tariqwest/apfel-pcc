// ============================================================================
// SchemaParser.swift — Pure JSON Schema -> SchemaIR converter
// Part of ApfelCore — no FoundationModels dependency
//
// Mirrors the subset of JSON Schema that FoundationModels'
// DynamicGenerationSchema can represent: object, string (with enum),
// number/integer, boolean, and array-of-something.
// ============================================================================

import Foundation

public enum SchemaParser {
    public enum Error: Swift.Error, Equatable {
        case invalidJSON
        case unsupportedType(String)
        case missingArrayItems
        case invalidProperty(String)
    }

    public static func parse(json: String, name: String) throws -> SchemaIR {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidJSON
        }
        return try parseObject(obj, name: name)
    }

    /// Parse a single JSON-Schema node. Defaults to `object` when `type` is
    /// absent (matches OpenAI function-schema conventions where the root
    /// object sometimes omits its type).
    private static func parseObject(_ schema: [String: Any], name: String) throws -> SchemaIR {
        // Normalize supported nullable unions / type-arrays before the type
        // switch so a node like anyOf:[X,{type:null}] or type:["string","null"]
        // parses as X. Unsupported unions throw so the caller's text-injection
        // fallback (tools) / 400 (json_schema) engages instead of silently
        // degrading to an empty object schema (#219).
        let (node, _) = try normalizeUnion(schema)
        let type = node["type"] as? String ?? "object"
        let description = node["description"] as? String

        switch type {
        case "object":
            let propsDict = node["properties"] as? [String: Any] ?? [:]
            let required = Set(node["required"] as? [String] ?? [])

            // Sort keys alphabetically so the IR is deterministic regardless
            // of JSON dictionary ordering.
            let sortedKeys = propsDict.keys.sorted()
            var properties: [SchemaIR.Property] = []
            properties.reserveCapacity(sortedKeys.count)
            for key in sortedKeys {
                guard let propSchema = propsDict[key] as? [String: Any] else {
                    throw Error.invalidProperty(key)
                }
                // A nullable property is optional regardless of the `required`
                // list (FoundationModels cannot represent "present but null").
                let (propNode, nullable) = try normalizeUnion(propSchema)
                let childIR = try parseObject(propSchema, name: key)
                let childDesc = propNode["description"] as? String
                properties.append(.init(
                    name: key,
                    description: childDesc,
                    schema: childIR,
                    isOptional: !required.contains(key) || nullable
                ))
            }
            return .object(name: name, description: description, properties: properties)

        case "string":
            let enumValues = node["enum"] as? [String]
            return .string(name: name, description: description, enumValues: enumValues)

        case "integer":
            return .integer(name: name, description: description)

        case "number":
            return .number(name: name, description: description)

        case "boolean":
            return .bool(name: name, description: description)

        case "array":
            guard let items = node["items"] as? [String: Any] else {
                throw Error.missingArrayItems
            }
            let inner = try parseObject(items, name: "\(name)_item")
            return .array(itemName: name, items: inner)

        default:
            throw Error.unsupportedType(type)
        }
    }

    /// Normalizes the supported nullable-union and type-array forms.
    ///
    /// Returns the unwrapped single-type node plus whether the original node was
    /// nullable. Only the `[X, {"type":"null"}]` (anyOf/oneOf) and
    /// `["<type>","null"]` (type array) patterns are supported; every other
    /// union (`allOf`, multi-type unions, type arrays without exactly one null)
    /// throws `unsupportedType` so callers fall back to text injection / 400.
    /// Idempotent: a node with no union is returned unchanged with `nullable: false`.
    private static func normalizeUnion(_ schema: [String: Any]) throws -> (node: [String: Any], nullable: Bool) {
        for key in ["anyOf", "oneOf"] {
            guard let raw = schema[key] else { continue }
            guard let rawArr = raw as? [Any] else { throw Error.unsupportedType(key) }
            let branches = rawArr.compactMap { $0 as? [String: Any] }
            guard branches.count == rawArr.count else { throw Error.unsupportedType(key) }
            let nonNull = branches.filter { ($0["type"] as? String) != "null" }
            let hasNull = branches.contains { ($0["type"] as? String) == "null" }
            guard branches.count == 2, hasNull, nonNull.count == 1 else {
                throw Error.unsupportedType(key)
            }
            var node = nonNull[0]
            // Preserve an outer description if the surviving branch lacks its own.
            if node["description"] == nil, let outer = schema["description"] {
                node["description"] = outer
            }
            return (node, true)
        }

        // `allOf` is an intersection we cannot represent.
        if schema["allOf"] != nil {
            throw Error.unsupportedType("allOf")
        }

        // `type` as an array: only exactly [<type>, "null"] (any order) is supported.
        if let rawType = schema["type"], !(rawType is String) {
            guard let typeArr = rawType as? [Any] else {
                throw Error.unsupportedType("type")
            }
            let types = typeArr.compactMap { $0 as? String }
            let nonNull = types.filter { $0 != "null" }
            guard types.count == typeArr.count, typeArr.count == 2,
                  types.contains("null"), nonNull.count == 1 else {
                throw Error.unsupportedType("type: [\(types.joined(separator: ","))]")
            }
            var node = schema
            node["type"] = nonNull[0]
            return (node, true)
        }

        return (schema, false)
    }
}
