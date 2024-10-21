//
//  DatabaseError.swift
//  Browser
//
//  Created by Florian Kugler on 16.10.24.
//
import SQLite3
import Foundation

struct DatabaseError: Error {
    var line: UInt
    var code: Int32
    var message: String
}

actor Database {
    var impl: DatabaseImpl
    
    init(url: URL) throws {
        print("sqlite3 \(url.path())")
        impl = try DatabaseImpl(url: url)
    }
    
    func setup() throws {
        try impl.setup()
    }
    
    func insert(page: Page) throws {
        try impl.execute(query: "INSERT INTO PageData (id, title, url, lastUpdated, fullText, snapshot) VALUES (?, ?, ?, ?, ?, ?)", params: page.id, page.title, page.url, page.lastUpdated, page.fullText, page.snapshot)
    }
}

final class DatabaseImpl {
    var connection: OpaquePointer?
    
    init(url: URL) throws {
        var connection: OpaquePointer?
        try checkError {
            url.absoluteString.withCString { str in
                sqlite3_open(str, &connection)
            }
        }
        self.connection = connection
    }
    
    func setup() throws {
        let query = """
        CREATE TABLE PageData (
            id TEXT PRIMARY KEY NOT NULL,
            lastUpdated INTEGER NOT NULL,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            fullText TEXT,
            snapshot BLOB
        );
        """
        var statement: OpaquePointer?
        try checkError {
            query.withCString { cStr in
                sqlite3_prepare_v3(connection, nil, -1, 0, &statement, nil)
            }
        }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else {
            try checkError { code }
            return // todo throw an error as well?
        }
        try checkError { sqlite3_finalize(statement) }
        print("DONE")
    }
    
    func execute(query: String, params: Bindable...) throws {
        var statement: OpaquePointer?
        try checkError {
            query.withCString {
                sqlite3_prepare_v3(connection, $0, -1, 0, &statement, nil)
            }
        }
        for (param, ix) in zip(params, (1 as Int32)...) {
            try param.bind(statement: statement, column: ix)
        }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else {
            try checkError { code }
            return // todo throw an error as well?
        }
        try checkError { sqlite3_finalize(statement) }
    }
}

protocol Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws
}

extension Int64: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        sqlite3_bind_int64(statement, column, self)
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension String: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try checkError {
            withCString {
                sqlite3_bind_text(statement, column, $0, -1, SQLITE_TRANSIENT)
            }
        }
    }
}

extension URL: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try absoluteString.bind(statement: statement, column: column)
    }
}

extension Date: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try Int64(timeIntervalSince1970).bind(statement: statement, column: column)
    }
}

extension UUID: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try uuidString.bind(statement: statement, column: column)
    }
}

extension Data: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try checkError {
            withUnsafeBytes {
                sqlite3_bind_blob(statement, column, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT)
            }
        }
    }
}

extension Optional: Bindable where Wrapped: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        switch self {
        case .none: sqlite3_bind_null(statement, column)
        case .some(let x): try x.bind(statement: statement, column: column)
        }
    }
}


func checkError(line: UInt = #line, _ fn: () -> Int32) throws {
    let code = fn()
    guard code == SQLITE_OK else {
        let str = String(cString: sqlite3_errstr(code))
        throw DatabaseError(line: line, code: code, message: str)
    }
}


func test() {
    Task {
        do {
            let url = URL.downloadsDirectory.appending(path: "db.sqlite")
            let db = try Database(url: url)
//            try await db.setup()
            try await db.insert(page: .init(url: .init(string: "https://www.objc.io")!))
        } catch {
            print("Error", error)
        }
    }
}
