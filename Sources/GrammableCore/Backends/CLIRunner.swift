// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

public struct CLIResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
}

/// Runs a command-line program with a timeout and Swift-concurrency cancellation.
public enum CLIRunner {

    /// An empty, private working directory so agent CLIs never pick up project files
    /// such as CLAUDE.md, AGENTS.md or GEMINI.md from wherever the app was launched.
    public static let workingDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grammable-work", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Removes terminal control sequences (colors, bracketed-paste toggles) that some CLIs print
    /// even when their output goes to a pipe.
    public static func stripTerminalCodes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
    }

    public static func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval
    ) async throws -> CLIResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLIResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = ShellEnvironment.shared.environment
                    process.currentDirectoryURL = workingDirectory

                    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

                    box.set(process)
                    if box.isCancelled {
                        continuation.resume(throwing: BackendError.cancelled)
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: BackendError.failed("Could not start \(executable): \(error.localizedDescription)"))
                        return
                    }

                    if let stdin {
                        DispatchQueue.global().async {
                            let handle = inPipe.fileHandleForWriting
                            try? handle.write(contentsOf: Data(stdin.utf8))
                            try? handle.close()
                        }
                    }

                    var outData = Data(), errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
                    }

                    let timer = DispatchWorkItem { [weak process] in
                        guard let process, process.isRunning else { return }
                        box.markTimedOut()
                        process.terminate()
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                    process.waitUntilExit()
                    timer.cancel()
                    group.wait()

                    if box.isCancelled { continuation.resume(throwing: BackendError.cancelled); return }
                    if box.didTimeOut { continuation.resume(throwing: BackendError.timedOut(timeout)); return }

                    continuation.resume(returning: CLIResult(
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self),
                        exitCode: process.terminationStatus
                    ))
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// What a line handler wants after reading one line of streamed output.
    public enum LineDecision: Sendable {
        case keepReading
        case finished(String)
        case failed(BackendError)
    }

    /// Runs a CLI that streams one JSON event per line and returns as soon as `handle` has the answer.
    ///
    /// Once the answer is in, the process is left to exit on its own while its output is drained in the
    /// background. Some CLIs (Antigravity) stall their next run when they are killed mid-turn.
    public static func runStreaming(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        handle: @escaping @Sendable (String) -> LineDecision
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ShellEnvironment.shared.environment
        process.currentDirectoryURL = workingDirectory
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let stderrBox = StderrBox()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { stderrBox.append(data) }
        }
        do {
            try process.run()
        } catch {
            throw BackendError.failed("Could not start \(executable): \(error.localizedDescription)")
        }

        let lines = outPipe.fileHandleForReading.bytes.lines
        let reader = Task<String, Error> {
            var iterator = lines.makeAsyncIterator()
            while let line = try await iterator.next() {
                switch handle(line) {
                case .keepReading: continue
                case .finished(let answer):
                    // Let the CLI wrap up by itself; keep draining so it never blocks on a full pipe.
                    Task.detached {
                        while (try? await iterator.next()) != nil {}
                    }
                    return answer
                case .failed(let error):
                    throw error
                }
            }
            process.waitUntilExit()
            let tail = stderrBox.tail
            throw BackendError.failed(
                "\(URL(fileURLWithPath: executable).lastPathComponent) exited with code \(process.terminationStatus) before answering." +
                (tail.isEmpty ? "" : "\n\(tail)"))
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await reader.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw BackendError.timedOut(timeout)
                }
                defer { group.cancelAll() }
                do {
                    return try await group.next()!
                } catch {
                    reader.cancel()
                    if process.isRunning { process.terminate() }
                    throw error
                }
            }
        } onCancel: {
            reader.cancel()
            if process.isRunning { process.terminate() }
        }
    }

    /// Turns a non-zero exit into a readable error, keeping the most useful stderr lines.
    public static func failure(_ result: CLIResult, tool: String) -> BackendError {
        let lines = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(4).joined(separator: "\n")
        let hint = tail.lowercased().contains("login") || tail.lowercased().contains("auth")
            ? "\nOpen Terminal and run `\(tool)` once to sign in." : ""
        return .failed("\(tool) exited with code \(result.exitCode).\n\(tail)\(hint)")
    }
}

/// Thread-safe holder so cancellation can terminate the running process.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var isCancelled = false
    private(set) var didTimeOut = false

    func set(_ p: Process) { lock.lock(); process = p; lock.unlock() }
    func markTimedOut() { lock.lock(); didTimeOut = true; lock.unlock() }
    func cancel() {
        lock.lock()
        isCancelled = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
}

/// Collects the end of a CLI's error output for messages.
private final class StderrBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ more: Data) {
        lock.lock(); data.append(more); if data.count > 8192 { data = data.suffix(4096) }; lock.unlock()
    }
    var tail: String {
        lock.lock(); defer { lock.unlock() }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.suffix(3).joined(separator: "\n")
    }
}
