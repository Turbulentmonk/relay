#!/usr/bin/env python3
"""Relay: a small, API-key-free terminal conversation for Codex and Claude Code."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import textwrap
from dataclasses import dataclass


RESET = "\033[0m"
DIM = "\033[2m"
BLUE = "\033[38;5;81m"
TEAL = "\033[38;5;116m"
ORANGE = "\033[38;5;215m"
RED = "\033[38;5;203m"
WHITE = "\033[38;5;252m"


@dataclass
class Turn:
    speaker: str
    text: str


class AgentError(RuntimeError):
    """A readable error from one of the local assistant tools."""


def codex_command() -> str | None:
    configured = os.environ.get("RELAY_CODEX_BIN")
    if configured and os.path.isfile(os.path.expanduser(configured)):
        return os.path.expanduser(configured)
    found = shutil.which("codex")
    if found:
        return found
    bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    return bundled if os.path.isfile(bundled) else None


def wrap_print(text: str, color: str = WHITE) -> None:
    width = max(40, shutil.get_terminal_size((80, 24)).columns - 4)
    for paragraph in text.strip().splitlines():
        if paragraph.strip():
            print(color + textwrap.fill(paragraph, width=width) + RESET)
        else:
            print()


def render(speaker: str, text: str) -> None:
    colors = {"You": BLUE, "Codex": TEAL, "Claude": ORANGE}
    print(f"\n{colors.get(speaker, WHITE)}* {speaker}{RESET}")
    wrap_print(text)


def run_codex(prompt: str, access: str) -> str:
    binary = codex_command()
    if not binary:
        raise RuntimeError("Codex CLI was not found. Open ChatGPT once or set RELAY_CODEX_BIN.")
    command = [binary, "exec", "--ephemeral", "--json", "--sandbox", access, prompt]
    return run_jsonl_agent("Codex", command)


def run_claude(prompt: str) -> str:
    binary = shutil.which("claude")
    if not binary:
        raise RuntimeError("Claude Code CLI was not found. Install Claude Code and sign in with your Claude account.")
    command = [binary, "-p", "--output-format", "json", "--permission-mode", "plan", prompt]
    return run_json_agent("Claude", command)


def run_jsonl_agent(name: str, command: list[str]) -> str:
    print(f"{DIM}Waiting for {name}... (Ctrl+C to stop){RESET}", flush=True)
    result = subprocess.run(command, capture_output=True, text=True, env=provider_environment())
    if result.returncode:
        raise AgentError(agent_error_message(name, result.stderr or result.stdout, result.returncode))
    final_messages: list[str] = []
    for line in result.stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = event.get("item", {})
        if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
            final_messages.append(item["text"])
    if not final_messages:
        raise RuntimeError(f"{name} finished without returning a message.")
    return final_messages[-1].strip()


def run_json_agent(name: str, command: list[str]) -> str:
    print(f"{DIM}Waiting for {name}... (Ctrl+C to stop){RESET}", flush=True)
    result = subprocess.run(command, capture_output=True, text=True, env=provider_environment())
    if result.returncode:
        raise AgentError(agent_error_message(name, result.stderr or result.stdout, result.returncode))
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return result.stdout.strip()
    text = payload.get("result") or payload.get("message") or payload.get("text")
    if not text:
        raise AgentError(f"{name} returned a response Relay couldn't read. Try running its command-line tool directly.")
    return str(text).strip()


def agent_error_message(name: str, details: str, status: int) -> str:
    lowered = details.lower()
    limit_phrases = ("rate limit", "usage limit", "out of tokens", "quota", "too many requests", "capacity", "limit reached")
    if any(phrase in lowered for phrase in limit_phrases):
        return f"{name} couldn't respond because its service reported a usage or rate limit. Wait for the limit to reset, then try again."
    details = details.strip()
    if details:
        return f"{name} couldn't respond: {details}"
    return f"{name} couldn't respond (exit status {status}). Check that its command-line tool is signed in."


def provider_environment() -> dict[str, str]:
    """Use saved CLI sign-ins, never API-key environment variables."""
    env = os.environ.copy()
    for name in ("OPENAI_API_KEY", "CODEX_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
        env.pop(name, None)
    return env


def conversation_context(turns: list[Turn]) -> str:
    if not turns:
        return ""
    recent = turns[-12:]
    return "\n\nEarlier conversation:\n" + "\n\n".join(
        f"{turn.speaker}: {turn.text}" for turn in recent
    )


def codex_file_scope(access: str) -> str:
    if access == "workspace-write":
        return "You may read and edit files in the current working folder. Do not modify files outside that folder."
    return "You may read files but must not edit them or run commands."


def ask_turn(user_text: str, turns: list[Turn], mode: str, leader: str, access: str) -> list[Turn]:
    context = conversation_context(turns)
    file_scope = codex_file_scope(access)
    first_prompt = (
        f"You are {leader} participating in Relay, a conversation with the user and another assistant. "
        f"Answer the user's request clearly and concisely. {file_scope}\n\n"
        f"User: {user_text}{context}"
    )
    if mode == "codex":
        answer = run_codex(first_prompt, access)
        render("Codex", answer)
        return [Turn("You", user_text), Turn("Codex", answer)]

    if mode == "claude":
        answer = run_claude(
            "You are Claude participating in Relay. Answer the user's request clearly and concisely. "
            "Do not edit files or run commands.\n\n"
            f"User: {user_text}{context}"
        )
        render("Claude", answer)
        return [Turn("You", user_text), Turn("Claude", answer)]

    other = "Claude" if leader == "Codex" else "Codex"
    lead_answer = run_codex(first_prompt, access) if leader == "Codex" else run_claude(first_prompt)
    render(leader, lead_answer)
    add_prompt = (
        f"You are {other} in a group conversation. Add one useful perspective or a concrete "
        f"improvement to {leader}'s answer. Keep it concise. {file_scope}\n\n"
        f"User request: {user_text}\n\n{leader}: {lead_answer}{context}"
    )
    add_answer = run_claude(add_prompt) if other == "Claude" else run_codex(add_prompt, access)
    render(other, add_answer)
    final_prompt = (
        f"You are {leader}, concluding a group conversation. Give one concise, practical final "
        f"answer that uses {other}'s contribution where useful. {file_scope}\n\n"
        f"User request: {user_text}\n\n{leader}'s first answer: {lead_answer}\n\n{other}: {add_answer}{context}"
    )
    final = run_codex(final_prompt, access) if leader == "Codex" else run_claude(final_prompt)
    render(f"{leader} - conclusion", final)
    return [Turn("You", user_text), Turn(leader, lead_answer), Turn(other, add_answer), Turn(leader, final)]


def main() -> int:
    codex_ready = codex_command() is not None
    claude_ready = shutil.which("claude") is not None
    print(f"{WHITE}Relay{RESET} {DIM}- terminal conversation - no provider API keys{RESET}")
    print(f"Codex: {TEAL}{'ready' if codex_ready else 'not found'}{RESET}  "
          f"Claude Code: {ORANGE}{'ready' if claude_ready else 'not installed'}{RESET}")
    access = "read-only"
    print(f"Codex file access: {access}")
    print(f"{DIM}Type /help for commands.{RESET}")
    if codex_ready and claude_ready:
        mode = "both"
        leader = "Codex"
    elif codex_ready:
        mode = "codex"
        leader = "Codex"
    elif claude_ready:
        mode = "claude"
        leader = "Claude"
    else:
        mode = "both"
        leader = "Codex"
    turns: list[Turn] = []
    while True:
        try:
            user_text = input(f"\n{BLUE}You > {RESET}").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nGoodbye.")
            return 0
        if not user_text:
            continue
        if user_text.lower() in {"/help", "/?"}:
            print("/mode codex|claude|both · /lead codex|claude · /access read-only|workspace-write · /new · /clear · /status · /quit")
            continue
        if user_text == "/quit":
            return 0
        if user_text == "/new":
            turns.clear()
            print(f"{DIM}Started a new conversation.{RESET}")
            continue
        if user_text.startswith("/mode "):
            requested = user_text.split(maxsplit=1)[1].lower()
            if requested in {"codex", "claude", "both"}:
                mode = requested
                print(f"{DIM}Mode: {mode}{RESET}")
            else:
                print(f"{RED}Choose codex, claude, or both.{RESET}")
            continue
        if user_text.startswith("/lead "):
            requested = user_text.split(maxsplit=1)[1].lower()
            if requested in {"codex", "claude"}:
                leader = requested.capitalize()
                print(f"{DIM}{leader} will lead when both assistants are selected.{RESET}")
            else:
                print(f"{RED}Choose codex or claude.{RESET}")
            continue
        if user_text.startswith("/access "):
            requested = user_text.split(maxsplit=1)[1].lower()
            if requested in {"read-only", "workspace-write"}:
                access = requested
                print(f"Codex file access: {access}")
                if access == "workspace-write":
                    print(f"{DIM}Codex can now change files in the folder where Relay was started.{RESET}")
            else:
                print(f"{RED}Choose read-only or workspace-write.{RESET}")
            continue
        try:
            turns.extend(ask_turn(user_text, turns, mode, leader, access))
        except KeyboardInterrupt:
            print(f"\n{DIM}Stopped the current turn.{RESET}")
        except AgentError as error:
            print(f"{RED}Relay: {error}{RESET}", file=sys.stderr)
        except Exception as error:  # Show provider setup and CLI errors in the terminal.
            print(f"{RED}Relay: {error}{RESET}", file=sys.stderr)
    

if __name__ == "__main__":
    raise SystemExit(main())
