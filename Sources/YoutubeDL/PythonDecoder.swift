//
//  PythonDecoder.swift
//
//
//  Created by 안창범 on 2021/11/17.
//

import Foundation
import PythonKit

open class PythonDecoder {
    public init() {}
    
    open func decode<T: Decodable>(_ type: T.Type, from pythonObject: PythonObject) throws -> T {
        try T(from: _PythonDecoder(pythonObject: pythonObject, codingPath: []))
    }
}

struct _PythonDecoder: Decoder {
    let pythonObject: PythonObject
    
    var codingPath: [CodingKey]
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(_KeyedDecodingContainer(dict: Dictionary(pythonObject)!, codingPath: codingPath))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        _UnkeyedDecodingContainer(elements: Array(pythonObject), codingPath: codingPath)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _SingleValueDecodingContainer(pythonObject: pythonObject, codingPath: codingPath)
    }
}

struct _KeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dict: [String: PythonObject]
    
    var codingPath: [CodingKey]
    
    var allKeys: [Key] { dict.keys.compactMap(Key.init(stringValue:)) }
    
    func contains(_ key: Key) -> Bool {
        dict.keys.contains(key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let object = dict[key.stringValue] else { return true }
        return object == Python.builtins["None"]
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try value(key)
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try value(key)
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try value(key)
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        fatalError()
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try value(key)
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        fatalError()
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        fatalError()
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        fatalError()
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        fatalError()
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        fatalError()
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        fatalError()
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        fatalError()
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        fatalError()
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        fatalError()
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        try T(from: _PythonDecoder(pythonObject: dict[key.stringValue]!, codingPath: codingPath + [key]))
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        fatalError()
    }
    
    func superDecoder() throws -> Decoder {
        fatalError()
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        fatalError()
    }
    
    func value<T: ConvertibleFromPython>(_ key: Key) throws -> T {
        guard let value = T(try value(for: key)) else {
            throw DecodingError.typeMismatch(
                T.self,
                DecodingError.Context(codingPath: codingPath,
                                      debugDescription: "type mismatch",
                                      underlyingError: nil))
        }
        return value
    }
    
    func value(for key: Key) throws -> PythonObject {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath,
                                      debugDescription: "invalid key",
                                      underlyingError: nil))
        }
        return value
    }
}

struct _UnkeyedDecodingContainer: UnkeyedDecodingContainer {
    struct CodingKeys: CodingKey {
        var stringValue: String
        
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = ""
        }
    }
    
    let elements: [PythonObject]
    
    var codingPath: [CodingKey]
    
    var count: Int? { elements.count }
    
    var isAtEnd: Bool { !elements.indices.contains(currentIndex) }
    
    var currentIndex = 0
    
    var element: PythonObject {
        mutating get {
            defer { currentIndex += 1 }
            return elements[currentIndex]
        }
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        fatalError()
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        fatalError()
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        fatalError()
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        fatalError()
    }
    
    func decode(_ type: String.Type) throws -> String {
        fatalError()
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        fatalError()
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        fatalError()
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        fatalError()
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        fatalError()
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        fatalError()
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        fatalError()
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        fatalError()
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        fatalError()
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        fatalError()
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        let key = CodingKeys(intValue: currentIndex) // must be before calling element
        return try T(from: _PythonDecoder(pythonObject: element, codingPath: codingPath + [key!]))
    }
    
    func decodeIfPresent(_ type: String.Type) throws -> String? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Double.Type) throws -> Double? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Float.Type) throws -> Float? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Int.Type) throws -> Int? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: UInt.Type) throws -> UInt? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Int8.Type) throws -> Int8? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Int16.Type) throws -> Int16? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Int32.Type) throws -> Int32? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: Int64.Type) throws -> Int64? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? {
        fatalError()
    }
    
    func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? {
        fatalError()
    }
    
    func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T : Decodable {
        fatalError()
    }
    
    func decodeNil() throws -> Bool {
        fatalError()
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        fatalError()
    }
    
    func superDecoder() throws -> Decoder {
        fatalError()
    }
}

struct _SingleValueDecodingContainer: SingleValueDecodingContainer {
    let pythonObject: PythonObject
    
    var codingPath: [CodingKey]
    
    func decodeNil() -> Bool {
        fatalError()
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        fatalError()
    }
    
    func decode(_ type: String.Type) throws -> String {
        String(pythonObject)!
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        fatalError()
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        fatalError()
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        fatalError()
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        fatalError()
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        fatalError()
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        fatalError()
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        fatalError()
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        fatalError()
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        fatalError()
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        fatalError()
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        fatalError()
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        fatalError()
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        fatalError()
    }
}
