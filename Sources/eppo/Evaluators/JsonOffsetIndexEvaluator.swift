import Foundation

/**
 * JSON Offset Index Evaluator - Revolutionary approach for ultra-fast startup
 *
 * Strategy:
 * 1. Startup: Manually scan JSON buffer to build byte offset index of flag locations (NO JSONSerialization!)
 * 2. Runtime: Use offsets to extract individual flag JSON and parse to Swift structs on-demand
 * 3. Cache: Keep parsed Swift structs in memory for fast subsequent access
 *
 * Benefits:
 * - Lightning-fast startup (minimal scanning, no JSON deserialization overhead)
 * - Memory efficient (only cache requested flags)
 * - Swift struct performance for evaluation (after first access)
 */
public class JsonOffsetIndexEvaluator: FlagEvaluatorProtocol {
    private let flagOffsets: [String: FlagOffset]
    private let jsonData: Data
    private var flagCache: [String: UFC_Flag] = [:]
    private let flagEvaluator: FlagEvaluator
    private let cacheLock = NSLock()
    private let isConfigObfuscated: Bool

    private struct FlagOffset {
        let start: Int
        let end: Int
        let key: String
    }

    public init(jsonData: Data, obfuscated: Bool) throws {
        self.jsonData = jsonData
        self.isConfigObfuscated = obfuscated
        self.flagEvaluator = FlagEvaluator(sharder: MD5Sharder())

        // Build offset index - this is the key innovation!
        let startTime = CFAbsoluteTimeGetCurrent()
        self.flagOffsets = try Self.buildOffsetIndex(from: jsonData)
        let indexTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        NSLog("📍 Built JSON offset index for %d flags in %.2fms", flagOffsets.count, indexTime)
    }

    /**
     * Build offset index by manually scanning JSON buffer for flag keys and tracking braces
     * This is the core innovation - zero JSON deserialization, pure buffer scanning!
     */
    private static func buildOffsetIndex(from data: Data) throws -> [String: FlagOffset] {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EvaluatorError.invalidConfiguration("Invalid UTF-8 encoding")
        }

        var offsets: [String: FlagOffset] = [:]

        // Find the "flags" section start - much faster than JSONSerialization!
        guard let flagsSectionRange = jsonString.range(of: "\"flags\"") else {
            throw EvaluatorError.invalidConfiguration("Could not find flags section")
        }

        // Find the opening brace after "flags":
        let searchStart = flagsSectionRange.upperBound
        guard let flagsObjectStart = jsonString.range(of: "{", range: searchStart..<jsonString.endIndex) else {
            throw EvaluatorError.invalidConfiguration("Could not find flags object start")
        }

        // Manually scan for flag keys within the flags object
        var currentPosition = flagsObjectStart.upperBound

        while currentPosition < jsonString.endIndex {
            // Look for quoted strings (potential flag keys)
            guard let quoteStart = jsonString.range(of: "\"", range: currentPosition..<jsonString.endIndex) else {
                break
            }

            // Find the closing quote
            guard let quoteEnd = jsonString.range(of: "\"", range: jsonString.index(after: quoteStart.upperBound)..<jsonString.endIndex) else {
                currentPosition = jsonString.index(after: quoteStart.upperBound)
                continue
            }

            // Extract the potential flag key
            let flagKey = String(jsonString[quoteStart.upperBound..<quoteEnd.lowerBound])

            // Look for the colon after this key
            guard let colonRange = jsonString.range(of: ":", range: quoteEnd.upperBound..<jsonString.endIndex) else {
                currentPosition = quoteEnd.upperBound
                continue
            }

            // Look for opening brace of flag object
            guard let flagStartBrace = jsonString.range(of: "{", range: colonRange.upperBound..<jsonString.endIndex) else {
                currentPosition = colonRange.upperBound
                continue
            }

            // Find the matching closing brace
            if let flagEndBrace = findMatchingBrace(in: jsonString, startingAt: flagStartBrace.upperBound) {
                let startOffset = jsonString.distance(from: jsonString.startIndex, to: flagStartBrace.lowerBound)
                let endOffset = jsonString.distance(from: jsonString.startIndex, to: flagEndBrace) + 1

                offsets[flagKey] = FlagOffset(
                    start: startOffset,
                    end: endOffset,
                    key: flagKey
                )

                currentPosition = flagEndBrace
            } else {
                currentPosition = flagStartBrace.upperBound
            }
        }

        NSLog("📊 Successfully indexed %d flags with byte offsets using manual buffer scanning", offsets.count)
        return offsets
    }

    /**
     * Find the matching closing brace by tracking nesting levels
     */
    private static func findMatchingBrace(in string: String, startingAt position: String.Index) -> String.Index? {
        var braceCount = 1
        var currentIndex = position
        var inString = false
        var escaped = false

        while currentIndex < string.endIndex && braceCount > 0 {
            let char = string[currentIndex]

            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
            }

            if braceCount == 0 {
                return currentIndex
            }

            currentIndex = string.index(after: currentIndex)
        }

        return nil
    }

    /**
     * Lazy flag loading - extract and parse individual flags on-demand
     */
    private func getFlag(key: String) throws -> UFC_Flag? {
        // Check cache first (thread-safe)
        cacheLock.lock()
        if let cached = flagCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Get flag using offset index
        guard let flagOffset = flagOffsets[key] else {
            return nil
        }

        // Extract just this flag's JSON data
        let flagData = jsonData.subdata(in: flagOffset.start..<flagOffset.end)

        // Parse to Swift struct directly
        let decoder = JSONDecoder()
        let flag = try decoder.decode(UFC_Flag.self, from: flagData)

        // Cache the parsed flag (thread-safe)
        cacheLock.lock()
        flagCache[key] = flag
        cacheLock.unlock()

        NSLog("🔄 Loaded and cached flag: %@", key)
        return flag
    }

    // MARK: - FlagEvaluatorProtocol

    public func evaluateFlag(
        flagKey: String,
        subjectKey: String,
        subjectAttributes: SubjectAttributes,
        isConfigObfuscated: Bool,
        expectedVariationType: UFC_VariationType? = nil
    ) -> FlagEvaluation {
        do {
            guard let flag = try getFlag(key: flagKey) else {
                return FlagEvaluation.noneResult(
                    flagKey: flagKey,
                    subjectKey: subjectKey,
                    subjectAttributes: subjectAttributes,
                    flagEvaluationCode: .flagUnrecognizedOrDisabled,
                    flagEvaluationDescription: "Flag not found"
                )
            }

            return flagEvaluator.evaluateFlag(
                flag: flag,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                isConfigObfuscated: isConfigObfuscated
            )
        } catch {
            NSLog("❌ Error evaluating flag %@: %@", flagKey, error.localizedDescription)
            return FlagEvaluation.noneResult(
                flagKey: flagKey,
                subjectKey: subjectKey,
                subjectAttributes: subjectAttributes,
                flagEvaluationCode: .unknown,
                flagEvaluationDescription: "Evaluation error: \(error.localizedDescription)"
            )
        }
    }

    public func getAllFlagKeys() -> [String] {
        return Array(flagOffsets.keys)
    }

    public func getFlagVariationType(flagKey: String) -> UFC_VariationType? {
        do {
            guard let flag = try getFlag(key: flagKey) else {
                return nil
            }
            return flag.variationType
        } catch {
            NSLog("❌ Error getting variation type for flag %@: %@", flagKey, error.localizedDescription)
            return nil
        }
    }
}

/**
 * Evaluator errors
 */
enum EvaluatorError: Error {
    case invalidConfiguration(String)
}