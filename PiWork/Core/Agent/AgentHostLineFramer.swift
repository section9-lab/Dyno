import Foundation

struct AgentHostLineFramer {
    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var records: [Data] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var record = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            if record.last == 0x0D {
                record.removeLast()
            }
            if !record.isEmpty {
                records.append(record)
            }
        }

        return records
    }
}
