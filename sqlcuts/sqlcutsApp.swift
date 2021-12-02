//
//  sqlcutsApp.swift
//  sqlcuts
//
//  Created by Tyler James Daddio on 11/29/21.
//

import SwiftUI
import UIKit
import Intents
import GRDB

@main
struct sqlcutsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is QueryDbIntent {
            return QueryDbIntentHandler()
        }else if intent is UpdateDbIntent {
            return UpdateDbIntentHandler()
        }
        return nil
    }
}

class UpdateDbIntentHandler: NSObject, UpdateDbIntentHandling {
    
    func handle(intent: UpdateDbIntent, completion: @escaping (UpdateDbIntentResponse) -> Void) {
        let statementStr = intent.statement!
        let dbFile = intent.database!
        let dbUrl = dbFile.fileURL!
        let dbPath = dbUrl.absoluteString
        
        let parentDir = intent.directory!
        let parentDirUrl = parentDir.fileURL!
        
        if parentDirUrl != dbUrl.deletingLastPathComponent()  {
            let response = UpdateDbIntentResponse(code: .error, userActivity: nil)
            response.errorText = "Parent folder must be set to the directory that contains the selected SQLite database file."
            completion(response)
            return
        }
        
        let isParentDirSecured = parentDirUrl.startAccessingSecurityScopedResource()
        let isDbFileSecured = dbUrl.startAccessingSecurityScopedResource()
        do {
            var config = Configuration()
            config.prepareDatabase({db in
                try db.execute(sql: "PRAGMA journal_mode = TRUNCATE;")
            })
            let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            try dbQueue.write { db in
                try db.execute(sql: statementStr)
            }
            let response = UpdateDbIntentResponse(code: .success, userActivity: nil)
            completion(response)
        }catch {
            let response = UpdateDbIntentResponse(code: .error, userActivity: nil)
            response.errorText = "\(error)"
            completion(response)
        }
        if isDbFileSecured {
            dbUrl.stopAccessingSecurityScopedResource()
        }
        if isParentDirSecured {
            parentDirUrl.stopAccessingSecurityScopedResource()
        }
    }
    
    func resolveStatement(for intent: UpdateDbIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let statement = intent.statement, !statement.isEmpty else {
            return completion(.needsValue())
        }
        return completion(.success(with: statement))
    }
    
    func resolveDatabase(for intent: UpdateDbIntent, with completion: @escaping (INFileResolutionResult) -> Void) {
        guard let database = intent.database else {
            return completion(.needsValue())
        }
        return completion(.success(with: database))
    }
    
    func resolveDirectory(for intent: UpdateDbIntent, with completion: @escaping (INFileResolutionResult) -> Void) {
        guard let directory = intent.directory else {
            return completion(.needsValue())
        }
        return completion(.success(with: directory))
    }
}

class QueryDbIntentHandler: NSObject, QueryDbIntentHandling {
    
    func handle(intent: QueryDbIntent, completion: @escaping (QueryDbIntentResponse) -> Void) {
        let nullValueStr = intent.nullValue!
        let shouldQuoteOutputStrings = intent.shouldQuoteOutputStrings! == 1
        let queryStr = intent.query!
        let dbFile = intent.database!
        
        let dbUrl = dbFile.fileURL!
        let isSecuredFile = dbUrl.startAccessingSecurityScopedResource()
        do {
            var config = Configuration()
            config.readonly = true
            let dbPath = dbUrl.absoluteString
            let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: queryStr)
                let results = rows.map({r in
                    r.map({ (column, dbValue) in
                        switch dbValue.storage {
                        case .null:
                            return nullValueStr
                        case .int64(let int64):
                            return String(int64)
                        case .double(let double):
                            return String(double)
                        case .string(let string):
                            if shouldQuoteOutputStrings {
                                return String(reflecting: string)
                            }else{
                                return string
                            }
                        case .blob(let data):
                            return "Blob(\(data.description))"
                        }
                    }).joined(separator: intent.columnSeparator!)
                })
                let response = QueryDbIntentResponse(code: .success, userActivity: nil)
                response.rows = results
                completion(response)
            }
        }catch {
            let response = QueryDbIntentResponse(code: .error, userActivity: nil)
            response.errorText = "\(error)"
            completion(response)
        }
        if isSecuredFile {
            dbUrl.stopAccessingSecurityScopedResource()
        }
    }
    
    func resolveQuery(for intent: QueryDbIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let query = intent.query, !query.isEmpty else {
            return completion(.needsValue())
        }
        return completion(.success(with: query))
    }
    
    func resolveDatabase(for intent: QueryDbIntent, with completion: @escaping (INFileResolutionResult) -> Void) {
        guard let database = intent.database else {
            return completion(.needsValue())
        }
        return completion(.success(with: database))
    }
    
    func resolveColumnSeparator(for intent: QueryDbIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let columnSeparator = intent.columnSeparator, !columnSeparator.isEmpty else {
            return completion(.needsValue())
        }
        return completion(.success(with: columnSeparator))
    }
    
    func resolveShouldQuoteOutputStrings(for intent: QueryDbIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
        guard let shouldQuoteOutputStrings = intent.shouldQuoteOutputStrings else {
            return completion(.needsValue())
        }
        return completion(.success(with: shouldQuoteOutputStrings == 1))
    }
    
    func resolveNullValue(for intent: QueryDbIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let nullValue = intent.nullValue else {
            return completion(.needsValue())
        }
        return completion(.success(with: nullValue))
    }
}
