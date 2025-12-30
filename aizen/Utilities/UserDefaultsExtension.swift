import Foundation

/// UserDefaults extension to support isolated storage for different app variants
extension UserDefaults {
    
    /// Shared UserDefaults instance that automatically uses the appropriate suite
    /// based on the app's Bundle Identifier
    static var app: UserDefaults {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            // Fallback to standard if bundle ID is not available
            return .standard
        }
        
        // Determine the suite name based on bundle ID
        // For nightly/dev builds, use a different suite to isolate settings
        let suiteName: String
        if bundleID.contains(".nightly") {
            suiteName = "win.aizen.app.nightly"
        } else {
            suiteName = "win.aizen.app"
        }
        
        // Return the UserDefaults instance for the specific suite
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
    
    /// Check if the current app is a development/nightly build
    static var isNightlyBuild: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return false
        }
        return bundleID.contains(".nightly")
    }
}
