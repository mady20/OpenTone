//
//  supabaseManager.swift
//  OpenTone
//
//  Created by Harshdeep Singh on 23/02/26.
//

import Foundation
import Supabase

// MARK: - Configuration Helpers

private enum SupabaseConfig {
    /// Reads a value from Info.plist (populated via Secrets.xcconfig).
    static func plistValue(for key: String) -> String {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty else {
            fatalError("⚠️ Missing \(key) in Info.plist. " +
                       "Make sure Secrets.xcconfig exists and the project " +
                       "build configuration references it.")
        }
        return value
    }

    static var supabaseURL: URL {
        guard let url = URL(string: plistValue(for: "SUPABASE_URL")) else {
            fatalError("⚠️ SUPABASE_URL in Info.plist is not a valid URL.")
        }
        return url
    }

    static var supabaseKey: String {
        plistValue(for: "SUPABASE_KEY")
    }
}

/// Central Supabase client — used by all DataModel managers.
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.supabaseURL,
    supabaseKey: SupabaseConfig.supabaseKey
)

// MARK: - Supabase Table Names

/// Constants for table names to avoid string typos.
enum SupabaseTable {
    static let users            = "users"
    static let activities       = "activities"
    static let callRecords      = "call_records"
    static let jamSessions      = "jam_sessions"
    static let completedSessions = "completed_sessions"
    static let roleplaySessions = "roleplay_sessions"
    static let reports          = "reports"
}
