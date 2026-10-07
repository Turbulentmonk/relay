import AppKit
import Observation
import SwiftUI

@main
struct RelayApp: App {
    var body: some Scene {
        WindowGroup("Relay") {
            ConversationView().frame(minWidth: 760, minHeight: 620).preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

private enum Palette {
    static let background = Color(red: 0.10, green: 0.11, blue: 0.11)
    static let panel = Color(red: 0.13, green: 0.15, blue: 0.15)
    static let user = Color(red: 0.13, green: 0.21, blue: 0.34)
    static let codex = Color(red: 0.12, green: 0.22, blue: 0.23)
    static let claude = Color(red: 0.25, green: 0.20, blue: 0.15)
    static let accent = Color(red: 0.20, green: 0.40, blue: 0.96)
}

private enum Assistant: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex", claude = "Claude"
    var id: String { rawValue }
    var tint: Color { self == .codex ? Palette.codex : Palette.claude }
}

private struct AssistantReply: Sendable {
    let assistant: Assistant
    let text: String
}

private final class NativeCLIController: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Process?

    static func executable(for assistant: Assistant) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let paths = (environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin").split(separator: ":").map(String.init)
        let candidates = assistant == .codex
            ? paths.map { "\($0)/codex" } + ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
            : paths.map { "\($0)/claude" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    func cancel() {
        lock.lock()
        let process = child
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    func respond(_ assistant: Assistant, prompt: String) throws -> String {
        guard let executable = Self.executable(for: assistant) else {
            throw NSError(domain: "Relay", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(assistant.rawValue) CLI was not found. Install it and sign in, then reopen Relay."])
        }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PWD"] ?? FileManager.default.currentDirectoryPath)
        if assistant == .codex {
            process.arguments = ["exec", "--ephemeral", "--json", "--sandbox", "read-only", prompt]
        } else {
            process.arguments = ["-p", "--output-format", "json", "--permission-mode", "plan", prompt]
        }
        var environment = ProcessInfo.processInfo.environment
        ["OPENAI_API_KEY", "CODEX_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"].forEach { environment.removeValue(forKey: $0) }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        lock.lock()
        child = process
        lock.unlock()
        defer {
            lock.lock()
            if child === process { child = nil }
            lock.unlock()
        }

        try process.run()
        let timeout = DispatchSource.makeTimerSource(queue: .global())
        timeout.schedule(deadline: .now() + 300)
        timeout.setEventHandler { [weak self] in self?.cancel() }
        timeout.resume()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        timeout.cancel()
        process.waitUntilExit()
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Relay", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(assistant.rawValue) could not complete the request." : raw])
        }
        return try Self.response(assistant, from: raw)
    }

    private static func response(_ assistant: Assistant, from output: String) throws -> String {
        if assistant == .codex {
            let messages = output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                guard let data = String(line).data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let item = event["item"] as? [String: Any],
                      item["type"] as? String == "agent_message" else { return nil }
                return item["text"] as? String
            }
            if let text = messages.last, !text.isEmpty { return text }
        } else if let data = output.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = payload["result"] as? String, !text.isEmpty {
            return text
        }
        let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else {
            throw NSError(domain: "Relay", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(assistant.rawValue) returned an empty reply."])
        }
        return fallback
    }
}

private struct Message: Identifiable {
    enum Author { case you, assistant(Assistant) }
    let id = UUID()
    let author: Author
    let text: String
}

@MainActor @Observable
private final class ConversationModel {
    var draft = ""
    var messages: [Message] = []
    var runMode = "Run with Codex + Claude"
    var isRunning = false
    var activity = "Relay is ready."
    var codexAvailable = NativeCLIController.executable(for: .codex) != nil
    var claudeAvailable = NativeCLIController.executable(for: .claude) != nil
    private var controller: NativeCLIController?

    func send() {
        guard !isRunning else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(author: .you, text: text))
        draft = ""
        isRunning = true
        activity = "Assistant is working…"
        codexAvailable = NativeCLIController.executable(for: .codex) != nil
        claudeAvailable = NativeCLIController.executable(for: .claude) != nil
        let requested: [Assistant] = runMode == "Run with Codex" ? [.codex] : runMode == "Run with Claude" ? [.claude] : [.codex, .claude]
        let selected = requested.filter { NativeCLIController.executable(for: $0) != nil }
        guard !selected.isEmpty else {
            isRunning = false
            activity = "The selected assistant CLI was not found. Install it and sign in, then reopen Relay."
            return
        }
        let history = messages.dropLast().map { message -> String in
            let name: String
            switch message.author {
            case .you: name = "You"
            case .assistant(let assistant): name = assistant.rawValue
            }
            return "\(name): \(message.text)"
        }.joined(separator: "\n\n")
        let prompt = "You are participating in Relay. Answer the user's request clearly and concisely.\n\nEarlier conversation:\n\(history)\n\nUser: \(text)"
        let runner = NativeCLIController()
        controller = runner
        Task.detached { [weak self] in
            do {
                for assistant in selected {
                    await MainActor.run {
                        guard let self else { return }
                        self.activity = "\(assistant.rawValue) is working…"
                    }
                    let reply = AssistantReply(assistant: assistant, text: try runner.respond(assistant, prompt: prompt))
                    await MainActor.run {
                        guard let self else { return }
                        self.messages.append(Message(author: .assistant(reply.assistant), text: reply.text))
                    }
                }
                await MainActor.run {
                    guard let self else { return }
                    self.activity = "Reply complete."
                    self.isRunning = false
                    self.controller = nil
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.activity = error.localizedDescription
                    self.isRunning = false
                    self.controller = nil
                }
            }
        }
    }

    func stop() {
        controller?.cancel()
        activity = "Stopping assistant…"
    }
}

private struct ConversationView: View {
    @State private var model = ConversationModel()
    @State private var showOptions = false
    @State private var showActivity = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversation").font(.headline)
                Spacer()
                Button("New Conversation") { model.messages = []; model.activity = "New conversation" }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning)
            }.padding(.horizontal, 22).padding(.vertical, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.messages.isEmpty { welcomeCard }
                        ForEach(model.messages) { MessageRow(message: $0).id($0.id) }
                    }.padding(18)
                }
                .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 13))
                .padding(.horizontal, 20)
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            composer.padding(.horizontal, 20).padding(.top, 12)
            footer.padding(.horizontal, 20).padding(.vertical, 9)
        }
        .background(Palette.background)
        .sheet(isPresented: $showOptions) { OptionsView() }
        .sheet(isPresented: $showActivity) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details & activity").font(.title2.bold())
                Text(model.activity).foregroundStyle(.secondary)
                Divider()
                Label("Codex runs read-only; Claude runs in plan mode.", systemImage: "lock.shield")
                Spacer()
            }.padding(24).frame(width: 440, height: 250).background(Palette.background)
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Relay").font(.title3.bold())
            Text("Share what you want to accomplish. Your selected assistants can work together, with Codex leading.")
                .foregroundStyle(.secondary)
            Text("Try: “Compare two ways to organize my project notes and recommend one.”")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Palette.codex.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Message").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Options…") { showOptions = true }
            }
            TextEditor(text: $model.draft)
                .scrollContentBackground(.hidden).padding(8).frame(minHeight: 92, maxHeight: 150)
                .background(Color.black.opacity(0.24))
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Describe the job for Codex and Claude…").foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Message for selected assistants")
            HStack {
                Picker("Run mode", selection: $model.runMode) {
                    Text("Run with Codex + Claude").tag("Run with Codex + Claude")
                    Text("Run with Codex").tag("Run with Codex")
                    Text("Run with Claude").tag("Run with Claude")
                }.frame(maxWidth: 260)
                Spacer()
                Button("Stop") { model.stop() }.disabled(!model.isRunning)
                Button("Send") { model.send() }.buttonStyle(.borderedProminent).tint(Palette.accent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isRunning || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(14).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Codex: \(model.codexAvailable ? "ready" : "not found")")
            Text("Claude: \(model.claudeAvailable ? "ready" : "not found")")
            Spacer(minLength: 8)
            Text(model.activity).lineLimit(1).foregroundStyle(.secondary)
            Button("Details & activity") { showActivity = true }
        }.font(.caption)
    }
}

private struct MessageRow: View {
    let message: Message
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch message.author {
            case .you:
                Spacer(minLength: 42)
                bubble(name: "You", color: Palette.user, trailing: true)
                Circle().fill(Palette.accent).frame(width: 30, height: 30)
                    .overlay(Text("Y").fontWeight(.bold))
            case .assistant(let assistant):
                Image(systemName: assistant == .codex ? "sparkles" : "sun.max")
                    .font(.title3).foregroundStyle(assistant == .codex ? .white : .orange)
                    .frame(width: 30, height: 30).background(.white.opacity(0.08), in: Circle())
                bubble(name: assistant.rawValue, color: assistant.tint, trailing: false)
                Spacer(minLength: 42)
            }
        }
    }
    private func bubble(name: String, color: Color, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 5) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(message.text).frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
                .textSelection(.enabled)
        }
        .padding(12).frame(maxWidth: 590, alignment: trailing ? .trailing : .leading)
        .background(color).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct OptionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Options").font(.title2.bold())
            Label("Codex uses read-only access.", systemImage: "lock")
            Label("Claude uses plan mode.", systemImage: "lock")
            Text("Relay uses the sign-ins saved by each CLI and removes supported API-key variables before launching it. The native app does not grant automatic approvals or full computer control.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 480).background(Palette.background)
    }
}
