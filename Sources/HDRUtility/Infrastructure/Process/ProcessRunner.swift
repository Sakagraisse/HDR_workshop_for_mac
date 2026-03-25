import Foundation

struct ProcessResult: Hashable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var combinedOutput: String {
        let segments = [standardOutput, standardError].filter { !$0.isEmpty }
        return segments.joined(separator: "\n")
    }
}

enum ProcessRunnerError: LocalizedError {
    case missingExecutable(URL)

    var errorDescription: String? {
        switch self {
        case let .missingExecutable(url):
            "Missing executable at \(url.path(percentEncoded: false))."
        }
    }
}

struct ProcessRunner {
    func run(executableURL: URL, arguments: [String], currentDirectoryURL: URL? = nil) async throws -> ProcessResult {
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw ProcessRunnerError.missingExecutable(executableURL)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessResult(
                    terminationStatus: process.terminationStatus,
                    standardOutput: String(decoding: stdoutData, as: UTF8.self),
                    standardError: String(decoding: stderrData, as: UTF8.self)
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
