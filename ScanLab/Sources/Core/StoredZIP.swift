import Foundation

enum StoredZIP {
    enum Entry {
        case data(String, Data)
        case file(String, URL)
        var name: String { switch self { case .data(let name, _), .file(let name, _): name } }
        func bytes() throws -> Data { switch self { case .data(_, let data): data; case .file(_, let url): try Data(contentsOf: url, options: .mappedIfSafe) } }
    }
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
    static func write(entries: [Entry], to url: URL) throws {
        guard entries.count <= Int(UInt16.max), Set(entries.map(\.name)).count == entries.count else { throw LabError.invalid("Too many or duplicate ZIP entries.") }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LabError.invalid("Export already exists; it will not be overwritten.") }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw LabError.invalid("Cannot create export.") }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var central = Data(); var offset: UInt64 = 0
        for entry in entries {
            guard !entry.name.hasPrefix("/"), !entry.name.split(separator: "/").contains("..") else { throw LabError.invalid("Invalid export path.") }
            let data = try entry.bytes(), name = Data(entry.name.utf8)
            guard data.count <= Int(UInt32.max), name.count <= Int(UInt16.max), offset <= UInt64(UInt32.max) else { throw LabError.invalid("Export exceeds ZIP limits; export a smaller dataset.") }
            let size = UInt32(data.count), crc = crc32(data)
            var local = Data()
            local.put(UInt32(0x04034b50)); local.put(UInt16(20)); local.put(UInt16(0x800)); local.put(UInt16(0))
            local.put(UInt16(0)); local.put(UInt16(0x21)); local.put(crc); local.put(size); local.put(size)
            local.put(UInt16(name.count)); local.put(UInt16(0)); local.append(name)
            try handle.write(contentsOf: local); try handle.write(contentsOf: data)
            central.put(UInt32(0x02014b50)); central.put(UInt16(20)); central.put(UInt16(20))
            central.put(UInt16(0x800)); central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0x21))
            central.put(crc); central.put(size); central.put(size); central.put(UInt16(name.count))
            central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0))
            central.put(UInt32(0)); central.put(UInt32(offset)); central.append(name)
            offset += UInt64(local.count + data.count)
        }
        guard offset <= UInt64(UInt32.max), central.count <= Int(UInt32.max) else { throw LabError.invalid("Export exceeds ZIP limits.") }
        try handle.write(contentsOf: central)
        var end = Data()
        end.put(UInt32(0x06054b50)); end.put(UInt16(0)); end.put(UInt16(0))
        end.put(UInt16(entries.count)); end.put(UInt16(entries.count)); end.put(UInt32(central.count))
        end.put(UInt32(offset)); end.put(UInt16(0))
        try handle.write(contentsOf: end)
    }
}
private extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
