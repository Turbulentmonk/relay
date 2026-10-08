# Relay

Relay is a small Terminal chat where you can talk with Codex and Claude together. Their replies use different colours so they are easy to tell apart.

## What Relay does

- Runs the locally installed Codex CLI, Claude Code, or both using their existing sign-ins; Relay removes supported API-key environment variables when launching them.
- In two-assistant mode, one assistant leads, the other contributes, and the lead gives a short conclusion. Choose the lead with `/lead codex` or `/lead claude`.
- Lets you switch providers with `/mode codex`, `/mode claude`, or `/mode both`, and start a fresh in-memory conversation with `/new`.
- Starts Codex with read-only access. `/access workspace-write` opts into letting Codex edit files in the directory where Relay was started. Claude runs in plan mode.

Relay includes a Python terminal app and a SwiftUI macOS app. The native app can run Codex, Claude, or both through their installed command-line tools; Codex stays read-only and Claude stays in plan mode.

## What you need

- A Mac with Python 3.10 or newer.
- At least one of the Codex command-line tool or Claude Code, signed in with its associated account. Install both to use both assistants; Relay starts with whichever provider or providers it finds.

Relay uses the sign-ins saved by those tools. It removes API-key variables when starting them, so it does not use OpenAI or Anthropic API keys. The assistants still connect to their own online services, and their normal account limits apply.

## Download and start Relay

Open Terminal and enter these commands:

```sh
git clone https://github.com/Turbulentmonk/relay.git
cd relay
python3 relay.py
```

## Use it

Type a message and press Return. When both assistants are selected, Relay has one lead assistant answer first, the other add a useful contribution, and the lead finish with a short conclusion. You choose who leads:

- `/lead claude` — Claude answers first and Codex adds a contribution
- `/lead codex` — Codex answers first and Claude adds a contribution
- `/mode codex` — use Codex only
- `/mode claude` — use Claude only
- `/mode both` — use both assistants
- `/ask codex <message>` / `/ask claude <message>` — choose one assistant for a single turn without changing the current mode
- `/new` — start a fresh conversation
- `/history` — list conversations saved on this device (up to 30 days)
- `/history open N` — reopen a conversation from the list and continue it
- `/delete-history` — permanently delete saved conversations
- `/quit` — close Relay

If an assistant reports that it has hit a usage or rate limit, Relay tells you which one could not respond and suggests trying again after the limit resets.

The terminal app streams assistant replies and stops a child process on Ctrl+C. It waits up to five minutes by default; set `RELAY_PROVIDER_TIMEOUT_SECONDS` to a whole number from 1 to 3600 to change that limit.

Codex starts in read-only mode. To let it read and edit files in the folder where Relay was started, type `/access workspace-write`. Type `/access read-only` to switch back. Start Relay from the project folder you want Codex to work in. Claude uses plan mode. Relay does not turn on full computer access.

## If an assistant is missing

Relay shows whether it can find each command-line tool. Codex is included in the ChatGPT app on some Macs. Claude Code must be installed separately. See the [Claude Code setup guide](https://docs.anthropic.com/en/docs/claude-code/getting-started).

## Current limitations and project notes

Relay saves conversation transcripts locally under the user data directory, keeps them for up to 30 days, and provides `/history` and `/delete-history` controls. No transcript is sent to Relay servers. Relay currently has no automated test suite or CI workflow. Its terminal output and child-process cancellation are listed for follow-up in [`docs/goals-and-potential-issues.md`](docs/goals-and-potential-issues.md).
