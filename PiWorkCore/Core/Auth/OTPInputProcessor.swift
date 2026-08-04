import Foundation

public enum OTPInputProcessor {
    public struct InputResult: Equatable {
        public let code: String
        public let focusedIndex: Int
        public let isComplete: Bool

        public init(code: String, focusedIndex: Int, isComplete: Bool) {
            self.code = code
            self.focusedIndex = focusedIndex
            self.isComplete = isComplete
        }
    }

    public struct BackspaceResult: Equatable {
        public let code: String
        public let focusedIndex: Int

        public init(code: String, focusedIndex: Int) {
            self.code = code
            self.focusedIndex = focusedIndex
        }
    }

    public static func applyInput(_ raw: String, to current: String, at index: Int, length: Int) -> InputResult {
        let digits = raw.filter(\.isOTPDigit)
        guard !digits.isEmpty else {
            return InputResult(code: current, focusedIndex: index, isComplete: current.count == length)
        }

        if digits.count >= length {
            let trimmed = String(digits.prefix(length))
            return InputResult(code: trimmed, focusedIndex: length - 1, isComplete: trimmed.count == length)
        }

        var characters = Array(current)
        if index < characters.count {
            characters[index] = digits.first!
        } else {
            while characters.count < index { characters.append(" ") }
            characters.append(digits.first!)
        }
        for (offset, digit) in digits.dropFirst().enumerated() {
            let target = index + 1 + offset
            if target < length {
                if target < characters.count {
                    characters[target] = digit
                } else {
                    characters.append(digit)
                }
            }
        }

        let trimmed = String(characters.prefix(length)).trimmingCharacters(in: .whitespaces)
        let nextIndex = min(index + digits.count, length - 1)
        return InputResult(code: trimmed, focusedIndex: nextIndex, isComplete: trimmed.count == length)
    }

    public static func applyBackspace(to current: String, at index: Int) -> BackspaceResult {
        if index < current.count {
            var characters = Array(current)
            characters.remove(at: index)
            return BackspaceResult(code: String(characters), focusedIndex: index)
        }

        let previous = max(0, index - 1)
        if previous < current.count {
            var characters = Array(current)
            characters.remove(at: previous)
            return BackspaceResult(code: String(characters), focusedIndex: previous)
        }
        return BackspaceResult(code: current, focusedIndex: previous)
    }
}

private extension Character {
    var isOTPDigit: Bool {
        guard let ascii = asciiValue else { return false }
        return (0x30...0x39).contains(ascii)
    }
}
