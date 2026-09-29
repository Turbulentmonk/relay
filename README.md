# Relay

Relay is a macOS desktop app concept for coordinating locally installed Claude Desktop and ChatGPT/Codex through their visible interfaces and macOS Accessibility. It does not use OpenAI or Anthropic API tokens.

## Current starter

The SwiftUI prototype follows the supplied references: a shared conversation, distinct user/Codex/Claude message styles, a composer, assistant selection, status footer, and Options for background mode, auto-approval, and full control. It currently provides the interface and local preference storage; assistant discovery and message dispatch are not implemented yet.

## Build on a Mac

Requires macOS 14 or later and Swift 6. From the repository folder, run: swift run.

## Local automation plan

The automation adapter must run on the Mac where the assistant apps are installed. It should use the macOS Accessibility API to inspect and operate app controls without activating their windows. Background mode must fail closed if an interaction would steal focus, and it must never synthesize keystrokes into whichever app the user is currently using. The operator will need to grant Relay Accessibility permission in System Settings and keep the target apps running.

No API credentials are required. Assistant sign-in and each app's own tool-approval settings remain managed by those apps.

## Safety and control modes

The prototype stores background, auto-approval, and full-control preferences locally. These controls are only UI preferences today; they do not yet change assistant permissions or automate approvals. A complete implementation should make the effective permission level visible, default to confirmation for consequential actions, and require an explicit opt-in before enabling each app's full-control mode.

## Cloud-buildable and Mac-local work

The UI, conversation model, settings, docs, and packaging can be developed in source control. App discovery, Accessibility permissions, background behavior, and compatibility with installed versions of Claude Desktop and ChatGPT/Codex must be implemented and verified on a physical Mac with those apps installed and signed in.
