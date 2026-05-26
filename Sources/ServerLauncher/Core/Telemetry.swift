// Anonymous telemetry — posts events to a Supabase Edge Function that holds the
// DB credential server-side. This binary never contains a Supabase key; it only
// knows the public function URL (AppInfo.telemetryEndpoint).
//
// Ported from TelemetryManager.cpp, with the key removed from the client. The
// payload shape matches the `telemetry_events` table the function inserts into.
import Foundation
import Combine

@MainActor
final class Telemetry: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Keys.enabled)
            if enabled { ensureAnonymousId() }
        }
    }
    @Published var extended: Bool {
        didSet { defaults.set(extended, forKey: Keys.extended) }
    }
    /// True once the user has answered the consent prompt (either way).
    @Published var consentAsked: Bool {
        didSet { defaults.set(consentAsked, forKey: Keys.consentAsked) }
    }

    /// Health of the telemetry backend. nil = unknown/checking.
    @Published private(set) var backendReachable: Bool?

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "TelemetryEnabled"
        static let extended = "TelemetryExtended"
        static let consentAsked = "TelemetryConsentAsked"
        static let anonymousId = "TelemetryAnonymousId"
    }

    init() {
        enabled = defaults.bool(forKey: Keys.enabled)
        extended = defaults.bool(forKey: Keys.extended)
        consentAsked = defaults.bool(forKey: Keys.consentAsked)
        if enabled { ensureAnonymousId() }
    }

    var canSend: Bool {
        enabled && consentAsked && AppInfo.telemetryEndpoint != nil
    }

    /// Stable anonymous device id (UUID), created lazily on first enable.
    private func ensureAnonymousId() {
        if defaults.string(forKey: Keys.anonymousId) == nil {
            defaults.set(UUID().uuidString, forKey: Keys.anonymousId)
        }
    }
    var anonymousId: String {
        defaults.string(forKey: Keys.anonymousId) ?? ""
    }

    /// Regenerate the anonymous id so future events look like a fresh install.
    func resetAnonymousId() {
        defaults.set(UUID().uuidString, forKey: Keys.anonymousId)
        objectWillChange.send()
    }

    /// Fire-and-forget. Silent on failure — telemetry must never affect UX.
    func send(_ eventName: String, properties: [String: Any] = [:]) {
        guard canSend, let url = AppInfo.telemetryEndpoint else { return }

        var payload = baseline(eventName)
        payload["event_properties"] = properties

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { _, _, error in
            if let error { NSLog("Telemetry send failed: \(error.localizedDescription)") }
        }.resume()
    }

    /// Ping the Edge Function (CORS preflight returns 200) to learn whether the
    /// telemetry backend is reachable. Updates `backendReachable`.
    func checkBackend() {
        guard let url = AppInfo.telemetryEndpoint else {
            backendReachable = false
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "OPTIONS"
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, error in
            let ok = error == nil && (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            Task { @MainActor in self?.backendReachable = ok }
        }.resume()
    }

    private func baseline(_ eventName: String) -> [String: Any] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "anonymous_id": anonymousId,
            "event_name": eventName,
            "app_version": AppInfo.version,
            "os_name": "macOS",
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "architecture": machineArchitecture(),
            "locale": Locale.current.identifier,
            "platform": "macos",
            "extended": extended,
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "source": "openmp_server_launcher",
        ]
    }

    private func machineArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine  // "arm64" | "x86_64"
    }
}
