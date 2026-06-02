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
        // Local daily-aggregate bucket (see Daily aggregation below).
        static let aggTabViews   = "TelemetryAggTabViews"     // [String:Int]
        static let aggActions    = "TelemetryAggActions"      // [String:Int]
        static let aggLaunches   = "TelemetryAggLaunches"     // Int
        static let aggForeground = "TelemetryAggForegroundSeconds" // Double
        static let aggBucketDay  = "TelemetryAggBucketDay"    // yyyy-MM-dd the bucket belongs to
        static let lastFlushDay  = "TelemetryAggLastFlushDay" // yyyy-MM-dd last pushed
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

    // MARK: - Daily aggregation
    //
    // Instead of POSTing one event per click/tab-switch (noisy, and a privacy
    // footprint), the app counts UI interactions LOCALLY into a per-day bucket in
    // UserDefaults, then pushes a single `daily_aggregate` event at most once per
    // day (on launch, when a calendar day has elapsed since the last push). The
    // server stores the rolled-up counts; no per-interaction timing ever leaves
    // the device. This mirrors the open.mp Launcher's averaging approach.

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Roll the bucket over to today if it belongs to an earlier day, discarding
    /// any stale partial counts that were never flushed (best-effort telemetry).
    private func ensureBucketIsToday() {
        if defaults.string(forKey: Keys.aggBucketDay) != today {
            defaults.set(today, forKey: Keys.aggBucketDay)
            defaults.removeObject(forKey: Keys.aggTabViews)
            defaults.removeObject(forKey: Keys.aggActions)
            defaults.set(0, forKey: Keys.aggLaunches)
            defaults.set(0.0, forKey: Keys.aggForeground)
        }
    }

    private func bump(_ key: String, name: String, by n: Int = 1) {
        guard enabled else { return }
        ensureBucketIsToday()
        var dict = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        dict[name, default: 0] += n
        defaults.set(dict, forKey: key)
    }

    /// Record that a sidebar tab / page was opened.
    func recordTab(_ name: String) { bump(Keys.aggTabViews, name: name) }

    /// Record a UI action click (start/stop/save/install/delete/…).
    func recordAction(_ name: String) { bump(Keys.aggActions, name: name) }

    /// Record an app launch (count) for the day.
    func recordLaunch() {
        guard enabled else { return }
        ensureBucketIsToday()
        defaults.set(defaults.integer(forKey: Keys.aggLaunches) + 1, forKey: Keys.aggLaunches)
    }

    /// Add foreground time (seconds) to the day's total — call when the app
    /// resigns active / quits with the elapsed active interval.
    func addForegroundTime(_ seconds: Double) {
        guard enabled, seconds > 0 else { return }
        ensureBucketIsToday()
        let total = defaults.double(forKey: Keys.aggForeground) + seconds
        defaults.set(total, forKey: Keys.aggForeground)
    }

    /// Push the day's aggregate at most once per day. Call on launch (after the
    /// app's stores are loaded so `serverCounts` is accurate). If the last push
    /// was today, this is a no-op. `serverCounts` is a daily snapshot (e.g.
    /// ["macos": 3, "windows": 1]).
    func flushDailyIfNeeded(serverCounts: [String: Int]) {
        guard canSend else { return }
        // Already pushed today? Nothing to do.
        if defaults.string(forKey: Keys.lastFlushDay) == today { return }

        let tabViews = (defaults.dictionary(forKey: Keys.aggTabViews) as? [String: Int]) ?? [:]
        let actions  = (defaults.dictionary(forKey: Keys.aggActions) as? [String: Int]) ?? [:]
        let launches = defaults.integer(forKey: Keys.aggLaunches)
        let fg       = defaults.double(forKey: Keys.aggForeground)
        let bucketDay = defaults.string(forKey: Keys.aggBucketDay) ?? today

        // Avg foreground per launch (the app calculates the average; only the
        // rolled-up numbers are sent, never individual sessions).
        let avgSessionSeconds = launches > 0 ? fg / Double(launches) : 0

        // Only push if there's something to report (avoids empty daily rows).
        let hasData = !tabViews.isEmpty || !actions.isEmpty || launches > 0
        if !hasData {
            defaults.set(today, forKey: Keys.lastFlushDay)
            return
        }

        send("daily_aggregate", properties: [
            "bucket_day": bucketDay,
            "tab_views": tabViews,
            "actions": actions,
            "launches": launches,
            "foreground_seconds": Int(fg.rounded()),
            "avg_session_seconds": Int(avgSessionSeconds.rounded()),
            "server_counts": serverCounts,
        ])

        // Mark pushed + start a fresh bucket for the new day.
        defaults.set(today, forKey: Keys.lastFlushDay)
        defaults.removeObject(forKey: Keys.aggTabViews)
        defaults.removeObject(forKey: Keys.aggActions)
        defaults.set(0, forKey: Keys.aggLaunches)
        defaults.set(0.0, forKey: Keys.aggForeground)
        defaults.set(today, forKey: Keys.aggBucketDay)
    }
}
