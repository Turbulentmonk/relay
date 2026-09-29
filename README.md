# Relay

Relay is a small Terminal chat where you can talk with Codex and Claude together. Their replies use different colours so they are easy to tell apart.

## What you need

- A Mac with Python 3.
- The Codex command-line tool, signed in with your ChatGPT account.
- Claude Code, signed in with your Claude account, to use both assistants. Relay can still run with Codex on its own.

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
- `/new` — start a fresh conversation
- `/quit` — close Relay

If an assistant reports that it has hit a usage or rate limit, Relay tells you which one could not respond and suggests trying again after the limit resets.

Relay asks the assistants to answer without changing files. Codex runs in read-only mode and Claude uses plan mode. It does not turn on automatic approval or full control.

## If an assistant is missing

Relay shows whether it can find each command-line tool. Codex is included in the ChatGPT app on some Macs. Claude Code must be installed separately. See the [Claude Code setup guide](https://docs.anthropic.com/en/docs/claude-code/getting-started).

## Earlier screen mock-up

`Sources/Relay/RelayApp.swift` is the first SwiftUI screen mock-up based on the supplied images. Running the Terminal version does not require Swift or Xcode.
