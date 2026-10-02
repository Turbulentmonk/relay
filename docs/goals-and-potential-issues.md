# Relay: Goals and Potential Issues

**Repository review:** 2 October 2026  
**Code snapshot reviewed:** `93123cd` (before this documentation update)

This page records goals and concerns visible from the repository. It is not a security audit or a promise that every proposed improvement is scheduled. The active product is the Python terminal app in `relay.py`; `Sources/Relay/RelayApp.swift` is an earlier SwiftUI mock-up and does not dispatch assistant requests.

## Current goals

1. **Keep startup predictable.** Start in both mode when both command-line tools are found, or directly in the available provider's mode when only one is installed. Keep the missing-provider message clear.
2. **Add repeatable checks.** There is no test command or CI workflow in the repository. Add small tests with mocked subprocesses for provider discovery, startup modes, response parsing, API-key environment filtering, and error handling before expanding the app.
3. **Harden terminal output and process handling.** Review assistant output and error text before printing it; consider filtering terminal control sequences and adding well-defined timeout/interruption handling for child processes.
4. **Make the access boundary easy to understand.** Preserve Codex's read-only default, clearly explain that `/access workspace-write` allows Codex to edit files under the directory where Relay was started, and keep Claude in plan mode unless the design is explicitly changed.
5. **Keep setup documentation aligned with the supported app.** The README currently describes a macOS terminal app, Python 3.10+, and locally installed/signed-in assistant CLIs. Update it whenever those requirements or startup behavior change.

## Potential issues to track

| Area | Repository observation | Why it may matter / follow-up |
| --- | --- | --- |
| Tests and CI | No test suite, test command, or GitHub Actions workflow is present. | Changes to provider selection, JSON parsing, and subprocess handling can regress without a repeatable check. Start with mocked CLI calls so tests never spend account usage or contact provider services. |
| Terminal output | `render()` and `wrap_print()` print assistant response text directly to the terminal, alongside Relay's own ANSI colour sequences. | If response text contains terminal control sequences, it may alter terminal display or mislead the user. Consider removing control characters from untrusted response/error text while retaining Relay's deliberate colours. |
| Child process lifecycle | Both providers are launched with `subprocess.run()` and have no explicit timeout. | A stuck CLI can leave Relay waiting indefinitely. Verify Ctrl+C behavior and child cleanup, then decide whether a configurable timeout or clearer cancellation flow is needed. |
| Workspace write access | Codex starts read-only. `/access workspace-write` passes that access mode to Codex for the current working directory. | Users should start Relay from the intended project folder and opt into writing deliberately. Keep the default read-only and explain the scope before any future change that broadens it. |
| Conversation lifetime | Turns are held in memory; `/new` clears them, and only the most recent 12 turn records are added as context. | Conversations do not survive a restart and older context is omitted. This is a current limitation; do not add persistence without deciding how local history should be stored and cleared. |
| Product surface | The repository contains a SwiftUI screen mock-up as well as the working Python terminal app. | The mock-up does not currently connect to either assistant. Keep that distinction prominent so users do not mistake it for a second usable app. |
| Platform and setup | The README targets macOS and Python 3.10 or newer. Codex discovery includes a ChatGPT app path specific to macOS. | Other operating systems and packaging/installers are not currently documented as supported. Verify them before advertising cross-platform support. |

## Suggested order

1. Add mocked automated checks for the core startup and provider-response paths.
2. Review terminal control-sequence handling and child-process cancellation/timeout behavior.
3. Revisit persistence or a native interface only after the user-facing scope and data-retention behavior are decided.
