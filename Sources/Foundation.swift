//
//  Foundation.swift
//  PMJSON
//
//  Created by Lily Ballard on 10/9/15.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
#if os(iOS) || os(watchOS) || os(tvOS)
    import struct CoreGraphics.CGFloat
#endif

// MARK: Data Support

extension JSON {
    /// Decodes a `Data` as JSON.
    /// - Note: Invalid unicode sequences in the data are replaced with U+FFFD.
    /// - Parameter data: The data to decode. Must be UTF-8, UTF-16, or UTF-32, and may start with a BOM.
    /// - Parameter options: Options that control JSON parsing. Defaults to no options. See `JSONOptions` for details.
    /// - Returns: A `JSON` value.
    /// - Throws: `JSONParserError` if the data does not contain valid JSON.
    public static func decode(_ data: Data, options: JSONOptions = []) throws -> JSON {
        if let endian = UTF32Decoder.encodes(data) {
            return try JSON.decode(UTF32Decoder(data: data, endian: endian), options: options)
        } else if let endian = UTF16Decoder.encodes(data) {
            return try JSON.decode(UTF16Decoder(data: data, endian: endian), options: options)
        } else {
            return try JSON.decode(UTF8Decoder(data: data), options: options)
        }
    }
    
    @available(*, deprecated, message: "Use JSON.decode(_:options:) instead")
    public static func decode(_ data: Data, strict: Bool) throws -> JSON {
        return try JSON.decode(data, options: [.strict])
    }
    
    /// Encodes a `JSON` to a `Data`.
    /// - Parameter json: The `JSON` to encode.
    /// - Parameter options: Options that controls JSON encoding. Defaults to no options. See `JSONEncoderOptions` for details.
    /// - Returns: An `NSData` with the JSON representation of *json*.
    public static func encodeAsData(_ json: JSON, options: JSONEncoderOptions = []) -> Data {
        var output = _DataOutput()
        JSON.encode(json, to: &output, options: options)
        return output.finish()
    }
    
    @available(*, deprecated, message: "Use JSON.encodeAsData(_:options:) instead")
    public static func encodeAsData(_ json: JSON, pretty: Bool) -> Data {
        return encodeAsData(json, options: JSONEncoderOptions(pretty: pretty))
    }
}

extension JSON {
    /// Returns a `JSONParser` that parses the given `Data` as JSON.
    /// - Note: Invalid unicode sequences in the data are replaced with U+FFFD.
    /// - Parameter data: The data to parse. Must be UTF-8, UTF-16, or UTF-32, and may start with a BOM.
    /// - Parameter options: Options that control JSON parsing. Defaults to no options. See `JSONParserOptions` for details.
    /// - Returns: A `JSONParser` value.
    public static func parser(for data: Data, options: JSONParserOptions = []) -> JSONParser<AnySequence<UnicodeScalar>> {
        if let endian = UTF32Decoder.encodes(data) {
            return JSONParser(AnySequence(UTF32Decoder(data: data, endian: endian)), options: options)
        } else if let endian = UTF16Decoder.encodes(data) {
            return JSONParser(AnySequence(UTF16Decoder(data: data, endian: endian)), options: options)
        } else {
            return JSONParser(AnySequence(UTF8Decoder(data: data)), options: options)
        }
    }
}

internal struct _DataOutput: TextOutputStream {
    // Trying to encode directly to a `Data` or `NSMutableData` isn't all that fast.
    // Encoding the whole thing as a `String` and converting to `Data` once is 40% faster
    // than writing each chunk to a data. On the flip side, encoding everything to a
    // `String` first and then converting to `Data` doubles the memory usage. To strike a
    // balance, we encode to a `String` in chunks up to 64kb, and every time we pass that,
    // we convert it to `Data`.
    // NB: Data was slow in Swift 4. It seems to be faster now. I don't have a good way of measuring
    // the difference so we'll just optimize for the modern compiler case.

    private var buffer = String()
    private var data = Data()
    /// Maximum number of bytes in the buffer before flushing to data.
    let maxChunkSize = 64 * 1024
    
    mutating func write(_ string: String) {
        #if swift(>=4.1.9) // Swift 4.2 compiler or later, required for compiler() test
        #if compiler(>=5)
        // Measure the string in its native encoding.
        func byteLen(of string: String) -> Int {
            return string.utf8.withContiguousStorageIfAvailable({ $0.count })
                ?? string.utf16.count * 2
        }
        let writeChunkNow = byteLen(of: string) >= maxChunkSize
        if writeChunkNow || byteLen(of: buffer) >= maxChunkSize {
            data.append(contentsOf: buffer.utf8)
            buffer = ""
        }
        if writeChunkNow {
            data.append(contentsOf: string.utf8)
        } else {
            buffer.append(string)
        }
        #else
        _writeUTF16(string)
        #endif
        #else
        _writeUTF16(string)
        #endif
    }
    
    /// The pre-Swift 5 implementation of write()
    private mutating func _writeUTF16(_ string: String) {
        // Measure the string in UTF-16 because it's O(1). If this is an ASCII string, we'll
        // be off by a factor of 2 on the size, but if it's non-ASCII then we'll have an
        // accurate representation of the string's size in-memory.
        let writeChunkNow = string.utf16.count >= maxChunkSize
        if writeChunkNow || buffer.utf16.count >= maxChunkSize {
            data.append(contentsOf: buffer.utf8)
            buffer = ""
        }
        if writeChunkNow {
            data.append(contentsOf: string.utf8)
        } else {
            buffer.append(string)
        }
    }
    
    mutating func finish() -> Data {
        if !buffer.isEmpty {
            data.append(contentsOf: buffer.utf8)
            buffer = ""
        }
        // NB: We don't really care about whether this references the NSData or not, in fact we'd
        // rather the stdlib make that decision, except `data as Data` isn't compatible with Linux
        return data
    }
}

// MARK: - Convenience

extension JSON {
    /// Returns a `JSON.double` with the given value.
    public static func cgFloat(_ value: CGFloat) -> JSON {
        return .double(Double(value))
    }
    
    /// Initializes `self` as a `Double` with the given value.
    public init(_ value: CGFloat) {
        self = .double(Double(value))
    }
}

// MARK: - Objective-C Compatibility

#if os(iOS) || os(OSX) || os(watchOS) || os(tvOS)

    extension JSON {
        /// Converts a JSON-compatible Foundation object into a `JSON` value.
        /// - Throws: `JSONFoundationError` if the object is not JSON-compatible.
        public init(ns: Any) throws {
            let object = ns as AnyObject
            if object === kCFBooleanTrue {
                self = .bool(true)
                return
            } else if object === kCFBooleanFalse {
                self = .bool(false)
                return
            }
            switch object {
            case is NSNull:
                self = .null
            case let d as NSDecimalNumber:
                self = .decimal(d.decimalValue)
            case let n as NSNumber:
                let typeChar: UnicodeScalar
                let objCType = n.objCType
                if objCType[0] == 0 || objCType[1] != 0 {
                    typeChar = "?"
                } else {
                    typeChar = UnicodeScalar(UInt8(bitPattern: objCType[0]))
                }
                switch typeChar {
                case "c", "i", "s", "l", "q", "C", "I", "S", "L", "B":
                    self = .int64(n.int64Value)
                case "Q": // unsigned long long
                    let val = n.uint64Value
                    if val > UInt64(Int64.max) {
                        fallthrough
                    }
                    self = .int64(Int64(val))
                default:
                    self = .double(n.doubleValue)
                }
            case let s as String:
                self = .string(s)
            case let dict as NSDictionary:
                var obj: [String: JSON] = Dictionary(minimumCapacity: dict.count)
                for (key, value) in dict {
                    guard let key = key as? String else { throw JSONFoundationError.nonStringKey }
                    obj[key] = try JSON(ns: value)
                }
                self = .object(JSONObject(obj))
            case let array as NSArray:
                var ary: JSONArray = []
                ary.reserveCapacity(array.count)
                for elt in array {
                    ary.append(try JSON(ns: elt))
                }
                self = .array(ary)
            default:
                throw JSONFoundationError.incompatibleType
            }
        }
        
        /// Returns the JSON as a JSON-compatible Foundation object.
        public var ns: Any {
            switch self {
            case .null: return NSNull()
            case .bool(let b): return NSNumber(value: b)
            case .string(let s): return s
            case .int64(let i): return NSNumber(value: i)
            case .double(let d): return d
            case .decimal(let d): return NSDecimalNumber(decimal: d)
            case .object(let obj): return obj.ns
            case .array(let ary):
                return ary.map({$0.ns})
            }
        }
        
        /// Returns the JSON as a JSON-compatible Foundation object, discarding any nulls.
        public var nsNoNull: Any? {
            switch self {
            case .null: return nil
            case .bool(let b): return NSNumber(value: b)
            case .string(let s): return s
            case .int64(let i): return NSNumber(value: i)
            case .double(let d): return d
            case .decimal(let d): return d
            case .object(let obj): return obj.nsNoNull
            case .array(let ary):
                return ary.compactMap({$0.nsNoNull})
            }
        }
    }
    
    extension JSONObject {
        /// Returns the JSON as a JSON-compatible dictionary.
        public var ns: [AnyHashable: Any] {
            var dict: [AnyHashable: Any] = Dictionary(minimumCapacity: count)
            for (key, value) in self {
                dict[key] = value.ns
            }
            return dict
        }
        
        /// Returns the JSON as a JSON-compatible dictionary, discarding any nulls.
        public var nsNoNull: [AnyHashable: Any] {
            var dict: [AnyHashable: Any] = Dictionary(minimumCapacity: count)
            for (key, value) in self {
                if let value = value.nsNoNull {
                    dict[key] = value
                }
            }
            return dict
        }
    }
    
    /// An error that is thrown when converting from `AnyObject` to `JSON`.
    /// - SeeAlso: `JSON.init(ns:)`
    public enum JSONFoundationError: Error {
        /// Thrown when a non-JSON-compatible type is found.
        case incompatibleType
        /// Thrown when a dictionary has a key that is not a string.
        case nonStringKey
    }
    
#endif // os(iOS) || os(OSX) || os(watchOS) || os(tvOS)

// MARK: - Errors

extension JSONError: LocalizedError {
    public var errorDescription: String? {
        return String(describing: self)
    }
}

extension JSONParserError: CustomNSError {
    public static let errorDomain: String = "PMJSON.JSONParserError"
    
    public var errorCode: Int {
        return code.rawValue
    }
    
    public var errorUserInfo: [String: Any] {
        return [NSLocalizedDescriptionKey: String(describing: self)]
    }
}

extension JSONDecoderError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .streamEnded: return "The JSON event stream ended."
        case .unexpectedToken: return "The JSON event stream contained more than one top-level value."
        case .exceededDepthLimit: return "The JSON event stream exceeded the nesting depth limit."
        }
    }
}

// MARK: -

private struct UTF8Decoder: Sequence {
    init(data: Data) {
        self.data = NSData(data: data)
    }
    
    func makeIterator() -> Iterator {
        return Iterator(data: data)
    }
    
    private let data: NSData
    
    fileprivate struct Iterator: IteratorProtocol {
        init(data: NSData) {
            // NB: We use NSData instead of using Data's iterator because it's significantly faster as of Xcode 8b3
            self.data = data
            let ptr = UnsafeBufferPointer(start: data.bytes.assumingMemoryBound(to: UInt8.self), count: data.length)
            iter = ptr.makeIterator()
            if ptr.count >= 3 && ptr[0] == 0xEF && ptr[1] == 0xBB && ptr[2] == 0xBF {
                // UTF-8 BOM detected. Skip it.
                _ = iter.next(); _ = iter.next(); _ = iter.next()
            }
        }
        
        mutating func next() -> UnicodeScalar? {
            switch utf8.decode(&iter) {
            case .scalarValue(let scalar): return scalar
            case .error: return "\u{FFFD}"
            case .emptyInput: return nil
            }
        }
        
        private let data: NSData
        private var iter: UnsafeBufferPointer<UInt8>.Iterator
        private var utf8 = UTF8()
    }
}

private struct UTF16Decoder: Sequence {
    /// Checks if the data appears to be UTF-16, and if so, returns the endianness.
    /// Data is treated as UTF-16 if it starts with a UTF-16 BOM, or if it starts
    /// with a non-NUL ASCII character encoded as UTF-16.
    static func encodes(_ data: Data) -> Endian? {
        guard data.count >= 2 else { return nil }
        switch (data[0], data[1]) {
        // BOM check
        case (0xFE, 0xFF): return .big
        case (0xFF, 0xFE): return .little
        // Non-NUL ASCII character
        case (0x00, 0x01...0x7F): return .big
        case (0x01...0x7F, 0x00): return .little
        default: return nil
        }
    }
    
    enum Endian {
        case big
        case little
    }
    
    init(data: Data, endian: Endian) {
        self.data = NSData(data: data)
        self.endian = endian
    }
    
    func makeIterator() -> Iterator {
        return Iterator(data: data, endian: endian)
    }
    
    private let data: NSData
    private let endian: Endian
    
    fileprivate struct Iterator: IteratorProtocol {
        init(data: NSData, endian: Endian) {
            iter = DataIterator(data: data, endian: endian)
        }
        
        mutating func next() -> UnicodeScalar? {
            switch utf16.decode(&iter) {
            case .scalarValue(let scalar): return scalar
            case .error: return "\u{FFFD}"
            case .emptyInput: return nil
            }
        }
        
        private var iter: DataIterator
        private var utf16 = UTF16()
    }
    
    private struct DataIterator: IteratorProtocol {
        init(data: NSData, endian: Endian) {
            // NB: We use NSData instead of using Data's iterator because it's significantly faster as of Xcode 8b3
            self.data = data
            self.endian = endian
            let ptr = UnsafeBufferPointer(start: data.bytes.assumingMemoryBound(to: UInt16.self), count: data.length / 2)
            iter = ptr.makeIterator()
            if !ptr.isEmpty {
                switch endian {
                case .big where UInt16(bigEndian: ptr[0]) == 0xFEFF: fallthrough
                case .little where UInt16(littleEndian: ptr[0]) == 0xFEFF:
                    // Skip the BOM
                    _ = iter.next()
                default: break
                }
            }
            trailingFFFD = data.length % 2 != 0
        }
        
        mutating func next() -> UInt16? {
            switch (iter.next(), endian) {
            case (let x?, .big): return UInt16(bigEndian: x)
            case (let x?, .little): return UInt16(littleEndian: x)
            case (nil, _) where trailingFFFD:
                trailingFFFD = false
                return 0xFFFD
            default: return nil
            }
        }
        
        private let data: NSData
        private let endian: Endian
        private var iter: UnsafeBufferPointer<UInt16>.Iterator
        private var trailingFFFD: Bool
    }
}

private struct UTF32Decoder: Sequence {
    /// Checks if the data appears to be UTF-32, and if so, returns the endianness.
    /// Data is treated as UTF-32 if it starts with a UTF-32 BOM, or if it starts
    /// with a non-NUL ASCII character encoded as UTF-32.
    static func encodes(_ data: Data) -> Endian? {
        guard data.count >= 4 else { return nil }
        switch (data[0], data[1], data[2], data[3]) {
        // BOM check
        case (0x00, 0x00, 0xFE, 0xFF): return .big
        case (0xFF, 0xFE, 0x00, 0x00): return .little
        // Non-NUL ASCII character
        case (0x00, 0x00, 0x00, 0x01...0x7F): return .big
        case (0x01...0x7F, 0x00, 0x00, 0x00): return .little
        default: return nil
        }
    }
    
    enum Endian {
        case big
        case little
    }
    
    init(data: Data, endian: Endian) {
        self.data = NSData(data: data)
        self.endian = endian
    }
    
    func makeIterator() -> Iterator {
        return Iterator(data: data, endian: endian)
    }
    
    private let data: NSData
    private let endian: Endian
    
    fileprivate struct Iterator: IteratorProtocol {
        init(data: NSData, endian: Endian) {
            iter = DataIterator(data: data, endian: endian)
        }
        
        mutating func next() -> UnicodeScalar? {
            switch utf32.decode(&iter) {
            case .scalarValue(let scalar): return scalar
            case .error: return "\u{FFFD}"
            case .emptyInput: return nil
            }
        }
        
        private var iter: DataIterator
        private var utf32 = UTF32()
    }
    
    private struct DataIterator: IteratorProtocol {
        init(data: NSData, endian: Endian) {
            // NB: We use NSData instead of using Data's iterator because it's significantly faster as of Xcode 8b3
            self.data = data
            self.endian = endian
            let ptr = UnsafeBufferPointer(start: data.bytes.assumingMemoryBound(to: UInt32.self), count: data.length / 4)
            iter = ptr.makeIterator()
            if !ptr.isEmpty {
                switch endian {
                case .big where UInt32(bigEndian: ptr[0]) == 0xFEFF: fallthrough
                case .little where UInt32(littleEndian: ptr[0]) == 0xFEFF:
                    // Skip the BOM
                    _ = iter.next()
                default: break
                }
            }
            trailingFFFD = data.length % 4 != 0
        }
        
        mutating func next() -> UInt32? {
            switch (iter.next(), endian) {
            case (let x?, .big): return UInt32(bigEndian: x)
            case (let x?, .little): return UInt32(littleEndian: x)
            case (nil, _) where trailingFFFD:
                trailingFFFD = false
                return 0xFFFD
            default: return nil
            }
        }
        
        private let data: NSData
        private let endian: Endian
        private var iter: UnsafeBufferPointer<UInt32>.Iterator
        private var trailingFFFD: Bool
    }
}
