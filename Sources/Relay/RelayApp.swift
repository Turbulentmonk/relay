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

private enum Assistant: String, CaseIterable, Identifiable {
    case codex = "Codex", claude = "Claude"
    var id: String { rawValue }
    var tint: Color { self == .codex ? Palette.codex : Palette.claude }
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
    var activity = "Relay is ready. Assistant automation is not configured yet."

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(author: .you, text: text))
        draft = ""
        activity = "Request queued locally. Assistant discovery and dispatch are not implemented yet."
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
                Label("Local automation not configured", systemImage: "desktopcomputer")
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
                Button("Stop") { model.isRunning = false }.disabled(!model.isRunning)
                Button("Send") { model.send() }.buttonStyle(.borderedProminent).tint(Palette.accent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(14).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Codex: not connected")
            Text("Claude: not connected")
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
    @AppStorage("relay.backgroundMode") private var backgroundMode = true
    @AppStorage("relay.autoApprove") private var autoApprove = false
    @AppStorage("relay.fullControl") private var fullControl = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Options").font(.title2.bold())
            Toggle("Background mode", isOn: $backgroundMode)
            Text("Keep assistant interactions in the background. Relay should never activate another app or take keyboard focus.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Auto-approve actions", isOn: $autoApprove)
            Toggle("Full control", isOn: $fullControl)
            Text("These are local preferences only. The automation adapter and each assistant app’s permissions must be configured on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 480).background(Palette.background)
    }
}
