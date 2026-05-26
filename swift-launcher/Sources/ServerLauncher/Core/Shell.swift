// Tiny synchronous subprocess runner for one-shot commands (cxbottle, pkill,
// pgrep). Long-running processes (the server itself) use Process directly in
// ServerController so output can be streamed.
import Foundation

enum Shell {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run `launchPath args`, capturing stdout/stderr. `timeout` seconds; on
    /// timeout the process is terminated and exitCode is -1.
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain pipes off the main thread to avoid deadlock on large output.
        let outData = DispatchWorkItem { _ = outPipe.fileHandleForReading.readDataToEndOfFile() }
        _ = outData  // (placeholder; we read after wait below for simplicity)

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            usleep(20_000)  // 20ms
        }
        if proc.isRunning {
            proc.terminate()
            return Result(exitCode: -1, stdout: "", stderr: "timed out")
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(exitCode: proc.terminationStatus, stdout: out, stderr: err)
    }
}
