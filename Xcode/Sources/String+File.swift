//
//  String+File.swift
//  Swifter
//
//  Copyright © 2016 Damian Kołakowski. All rights reserved.
//

import Foundation

#if os(Windows)
import WinSDK
#endif

extension String {

    public enum FileError: Error {
        case error(Int32)
    }

    public class File {

        let pointer: UnsafeMutablePointer<FILE>

        public init(_ pointer: UnsafeMutablePointer<FILE>) {
            self.pointer = pointer
        }

        public func close() {
            fclose(pointer)
        }

        public func seek(_ offset: Int32) -> Bool {
            return (fseek(pointer, offset, SEEK_SET) == 0)
        }

        public func read(_ data: inout [UInt8]) throws -> Int {
            if data.count <= 0 {
                return data.count
            }
            let count = fread(&data, 1, data.count, self.pointer)
            if count == data.count {
                return count
            }
            if feof(self.pointer) != 0 {
                return count
            }
            if ferror(self.pointer) != 0 {
                throw FileError.error(errno)
            }
            throw FileError.error(0)
        }

        public func write(_ data: [UInt8]) throws {
            if data.count <= 0 {
                return
            }
            try data.withUnsafeBufferPointer {
                if fwrite($0.baseAddress, 1, data.count, self.pointer) != data.count {
                    throw FileError.error(errno)
                }
            }
        }

        public static func currentWorkingDirectory() throws -> String {
            guard let path = getcwd(nil, 0) else {
                throw FileError.error(errno)
            }
            return String(cString: path)
        }
    }

    public static var pathSeparator = "/"

    public func openNewForWriting() throws -> File {
        return try openFileForMode(self, "wb")
    }

    public func openForReading() throws -> File {
        return try openFileForMode(self, "rb")
    }

    public func openForWritingAndReading() throws -> File {
        return try openFileForMode(self, "r+b")
    }

    public func openFileForMode(_ path: String, _ mode: String) throws -> File {
        guard let file = path.withCString({ pathPointer in mode.withCString({ fopen(pathPointer, $0) }) }) else {
            throw FileError.error(errno)
        }
        return File(file)
    }

    public func exists() throws -> Bool {
        return try self.withStat {
            if $0 != nil {
                return true
            }
            return false
        }
    }

    public func directory() throws -> Bool {
        return try self.withStat {
            if let stat = $0 {
                #if os(Windows)
                // Need to disambiguate here.
                return Int32(stat.st_mode) & ucrt.S_IFMT == ucrt.S_IFDIR
                #else
                return stat.st_mode & S_IFMT == S_IFDIR
                #endif
            }
            return false
        }
    }

    public func files() throws -> [String] {
        var results = [String]()
        #if os(Windows)
        var data = WIN32_FIND_DATAW()
        let handle = self.withCString(encodedAs: UTF16.self) {
            return FindFirstFileW($0, &data)
        }
        guard handle != INVALID_HANDLE_VALUE else {
            throw FileError.error(Int32(GetLastError()))
        }
        defer { FindClose(handle) }
        let appendToResults = {
            let fileName = withUnsafePointer(to: &data.cFileName) { (ptr) -> String in
                ptr.withMemoryRebound(to: unichar.self, capacity: Int(MAX_PATH * 2)) {
                    String(utf16CodeUnits: $0, count: wcslen($0))
                }
            }
            results.append(fileName)
        }
        appendToResults()
        while FindNextFileW(handle, &data) {
            appendToResults()
        }
        #else
        guard let dir = self.withCString({ opendir($0) }) else {
            throw FileError.error(errno)
        }
        defer { closedir(dir) }
        while let ent = readdir(dir) {
            var name = ent.pointee.d_name
            let fileName = withUnsafePointer(to: &name) { (ptr) -> String? in
                #if os(Linux)
                  return String(validatingUTF8: ptr.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_reclen), { (ptrc) -> [CChar] in
                    return [CChar](UnsafeBufferPointer(start: ptrc, count: 256))
                  }))
                #else
                    var buffer = ptr.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_reclen), { (ptrc) -> [CChar] in
                      return [CChar](UnsafeBufferPointer(start: ptrc, count: Int(ent.pointee.d_namlen)))
                    })
                    buffer.append(0)
                    return String(validatingUTF8: buffer)
                #endif
            }
            if let fileName = fileName {
                results.append(fileName)
            }
        }
        #endif
        return results
    }

    private func withStat<T>(_ closure: ((stat?) throws -> T)) throws -> T {
        return try self.withCString({
            var statBuffer = stat()
            if stat($0, &statBuffer) == 0 {
                return try closure(statBuffer)
            }
            if errno == ENOENT {
                return try closure(nil)
            }
            throw FileError.error(errno)
        })
    }
}