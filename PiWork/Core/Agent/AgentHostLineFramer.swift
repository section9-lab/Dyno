import Foundation

struct AgentHostLineFramer {
    private var buffer = Data()
    private var scannedByteCount = 0

    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var records: [Data] = []
        var recordStart = buffer.startIndex
        var searchStart = buffer.index(
            buffer.startIndex,
            offsetBy: min(scannedByteCount, buffer.count)
        )

        while searchStart < buffer.endIndex,
              let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) {
            var recordEnd = newlineIndex
            if recordEnd > recordStart,
               buffer[buffer.index(before: recordEnd)] == 0x0D {
                recordEnd = buffer.index(before: recordEnd)
            }
            if recordEnd > recordStart {
                records.append(Data(buffer[recordStart..<recordEnd]))
            }
            recordStart = buffer.index(after: newlineIndex)
            searchStart = recordStart
        }

        if recordStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<recordStart)
        }
        scannedByteCount = buffer.count

        return records
    }
}
