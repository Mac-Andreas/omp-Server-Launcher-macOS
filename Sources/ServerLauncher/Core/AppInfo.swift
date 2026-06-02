// App metadata — version, update repo, telemetry endpoint.
//
// No Supabase key here. Telemetry posts to a public Edge Function URL that
// holds the DB credential server-side (see supabase/functions/telemetry).
import Foundation

enum AppInfo {
    /// Bump on each release; the update check compares this to the latest
    /// GitHub release tag.
    static let version = "2.0.0"

    /// Display name (window title, About, telemetry `source`).
    static let displayName = "Open Multiplayer — Server Manager"

    /// GitHub repo to check for releases.
    /// https://api.github.com/repos/<owner>/<repo>/releases/latest
    static let updateOwner = "Mac-Andreas"
    static let updateRepo  = "omp-Server-Manager-macOS"

    /// Browser URL for the repository (footer link).
    static var repositoryURL: URL {
        URL(string: "https://github.com/\(updateOwner)/\(updateRepo)")!
    }

    /// Public live aggregate dashboard (the Mac Andreas site).
    static var dashboardURL: URL {
        URL(string: "https://mac-andreas.github.io/#dashboard")!
    }

    /// Public Supabase Edge Function that proxies telemetry inserts. The real
    /// DB key lives inside the function on Supabase, never in this binary.
    /// Override at build/run time with the TELEMETRY_ENDPOINT env var.
    static var telemetryEndpoint: URL? {
        if let s = ProcessInfo.processInfo.environment["TELEMETRY_ENDPOINT"],
           let u = URL(string: s) {
            return u
        }
        // Telemetry Edge Function on the shared MacAndreas project. The
        // function holds the DB key server-side; this is just the public URL.
        return URL(string: "https://tmenljjfshefocoqnwgi.supabase.co/functions/v1/telemetry")
    }
}
