# Relay: Goals and Potential Issues

**Repository review:** 14 October 2026

This page records goals and concerns visible from the repository. It is not a security audit or a promise that every proposed improvement is scheduled. The active product is the Python terminal app in `relay.py`; `Sources/Relay/RelayApp.swift` is an earlier SwiftUI mock-up and does not dispatch assistant requests.

## Current goals

1. **Add repeatable checks.** There is no test command or CI workflow in the repository. Add small tests with mocked subprocesses for provider discovery, startup modes, response parsing, API-key environment filtering, history handling, and error paths before expanding the app.
2. **Keep terminal output and process handling reliable.** Assistant output is sanitized before display, and provider commands have a configurable timeout plus Ctrl+C cleanup. Continue to review these paths when changing streaming or process management.
3. **Make the access boundary easy to understand.** Preserve Codex's read-only default, clearly explain that `/access workspace-write` allows Codex to edit files under the directory where Relay was started, and keep Claude in plan mode unless the design is explicitly changed.
4. **Keep setup documentation aligned with the supported app.** The README describes a macOS terminal app, Python 3.10+, and locally installed/signed-in assistant CLIs. Update it whenever those requirements or startup behavior change.

## Potential issues to track

| Area | Repository observation | Why it may matter / follow-up |
| --- | --- | --- |
| Tests and CI | No test suite, test command, or GitHub Actions workflow is present. | Changes to provider selection, JSON parsing, and subprocess handling can regress without a repeatable check. Start with mocked CLI calls so tests never spend account usage or contact provider services. |
| Terminal output | Assistant text is passed through `sanitize_terminal_text()` before it is printed, including streamed output. | Keep sanitization on every output path and review it if new terminal rendering is added. |
| Child process lifecycle | Provider commands are launched with `subprocess.Popen()`, a configurable timeout (300 seconds by default, up to 3600), and termination/kill cleanup on timeout or Ctrl+C. | Changes to streaming or cancellation should preserve the deadline and ensure child processes are reaped. |
| Workspace write access | Codex starts read-only. `/access workspace-write` passes that access mode to Codex for the current working directory. | Users should start Relay from the intended project folder and opt into writing deliberately. Keep the default read-only and explain the scope before any future change that broadens it. |
| Conversation history | Transcripts are saved locally with restrictive file permissions, retained for up to 30 days, and managed with `/history` and `/delete-history`. Only the most recent 12 turn records are added as assistant context. | History is local and may contain sensitive conversation text. Keep retention and deletion behavior clear, and preserve malformed-entry handling when changing the format. |
| Product surface | The repository contains a SwiftUI screen mock-up as well as the working Python terminal app. | The mock-up does not currently connect to either assistant. Keep that distinction prominent so users do not mistake it for a second usable app. |
| Platform and setup | The README targets macOS and Python 3.10 or newer. Codex discovery includes a ChatGPT app path specific to macOS. | Other operating systems and packaging/installers are not currently documented as supported. Verify them before advertising cross-platform support. |

## Suggested order

1. Add mocked automated checks for core startup, provider-response, history, and subprocess paths.
2. Preserve terminal sanitization and child-process cleanup as the streaming implementation evolves.
3. Revisit the native interface only after deciding its supported user-facing scope; the SwiftUI screen remains a mock-up.
