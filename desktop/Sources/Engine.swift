import Foundation

/// One Ruby engine process for one site. All callbacks run on the main queue.
final class EngineProcess {
    static let readyPrefix = "JEKYLL_CANVAS_READY "
    static let timeout: TimeInterval = 90

    enum Outcome {
        case ready(URL)
        case failed(String)   // exited before ready / timeout
        case died(Int32)      // exited after ready
    }

    let sitePath: String
    private let process = Process()
    private let pipe = Pipe()
    private let stdinPipe = Pipe()   // held open; closing it (app death) lets the engine notice EOF
    private var buffer = Data()
    private var timeoutItem: DispatchWorkItem?
    private(set) var isReady = false
    private var stopping = false
    private var finished = false

    private(set) var logLines: [String] = []   // last 500 lines
    var onLog: ((String) -> Void)?
    var onOutcome: ((Outcome) -> Void)?

    static func engineDir() -> String {
        if let env = ProcessInfo.processInfo.environment["JEKYLL_CANVAS_ENGINE"], !env.isEmpty {
            return env
        }
        return (Bundle.main.resourcePath ?? ".") + "/engine"
    }

    init(sitePath: String) {
        self.sitePath = sitePath
    }

    var isRunning: Bool { process.isRunning }
    var processIdentifier: Int32 { process.processIdentifier }

    func start() {
        // Paths travel through the environment only, never interpolated into the script.
        // A login shell does not read ~/.zshrc, where version managers are usually
        // initialised, so put their shims (and Homebrew) on PATH explicitly.
        let script = """
        for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/share/mise/shims" "$HOME/.asdf/shims" "$HOME/.rbenv/shims"; do
          [ -d "$d" ] && PATH="$d:$PATH"
        done
        export PATH
        cd "$JC_SITE" || exit 2
        if [ -f Gemfile ]; then exec bundle exec ruby -I"$JC_ENGINE/lib" "$JC_ENGINE/exe/jekyll-canvas-server" --site "$JC_SITE"
        else exec ruby -I"$JC_ENGINE/lib" "$JC_ENGINE/exe/jekyll-canvas-server" --site "$JC_SITE"; fi
        """
        var env = ProcessInfo.processInfo.environment
        env["JC_SITE"] = sitePath
        env["JC_ENGINE"] = EngineProcess.engineDir()
        env["JC_EXIT_ON_STDIN_EOF"] = "1"

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.environment = env
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = stdinPipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            // Give the readability handler a moment to deliver the tail of the output.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.exited(status) }
        }

        do {
            try process.run()
        } catch {
            appendLog("Impossibile eseguire /bin/zsh: \(error.localizedDescription)")
            finish(.failed(logLines.joined(separator: "\n")))
            return
        }
        logErr("engine started pid=\(process.processIdentifier) site=\(sitePath)")

        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isReady, !self.finished else { return }
            self.appendLog("Timeout: il motore non ha risposto entro \(Int(EngineProcess.timeout)) secondi.")
            self.finish(.failed(self.logLines.joined(separator: "\n")))
            self.terminate()
        }
        timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + EngineProcess.timeout, execute: item)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handleLine(String(decoding: lineData, as: UTF8.self))
        }
    }

    private func handleLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        appendLog(line)
        if !isReady, !finished, line.hasPrefix(EngineProcess.readyPrefix) {
            let urlString = line.dropFirst(EngineProcess.readyPrefix.count).trimmingCharacters(in: .whitespaces)
            if let url = URL(string: urlString) {
                isReady = true
                timeoutItem?.cancel()
                logErr("ready url=\(urlString)")
                finish(.ready(url))
            }
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        logErr("engine| " + line)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
        onLog?(line)
    }

    private func exited(_ status: Int32) {
        timeoutItem?.cancel()
        if !buffer.isEmpty {
            let rest = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            handleLine(rest)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        logErr("engine exited status=\(status) site=\(sitePath)")
        if stopping { return }
        if isReady {
            finish(.died(status), force: true)
        } else if !finished {
            appendLog("Il processo è terminato con codice \(status) prima di essere pronto.")
            finish(.failed(logLines.joined(separator: "\n")))
        }
    }

    private func finish(_ outcome: Outcome, force: Bool = false) {
        if finished && !force { return }
        finished = true
        onOutcome?(outcome)
    }

    /// SIGTERM now, SIGKILL after 3 s if still alive. Callbacks are silenced.
    func stop() {
        stopping = true
        timeoutItem?.cancel()
        onLog = nil
        onOutcome = nil
        terminate()
    }

    private func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            if let self = self, self.process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// Blocking variant for app quit: SIGTERM, wait up to `grace`, then SIGKILL.
    func stopSynchronously(grace: TimeInterval = 3) {
        stopping = true
        timeoutItem?.cancel()
        onLog = nil
        onOutcome = nil
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        let deadline = Date().addingTimeInterval(grace)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(pid, SIGKILL) }
    }
}
