import Foundation
import os

/// Diagnostics for UI tests and bug reports (`log stream --predicate 'subsystem == "de.mailmeg.app"'`).
enum DebugLog {
    private static let logger = Logger(subsystem: "de.mailmeg.app", category: "ui")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
