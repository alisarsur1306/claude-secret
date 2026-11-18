# 🔐 claude-secret

**Give Claude Code your API keys without ever showing them to Claude.**

![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![deps](https://img.shields.io/badge/dependencies-none-brightgreen)
![claude code](https://img.shields.io/badge/Claude%20Code-skill-d97757)

You paste an API key into the chat so Claude can deploy, call an API, or query a database. That
key is now in the model's context, in your session transcript on disk, and in every later
message of that conversation.

`/secret` fixes that. You type a **name**. The value goes from you straight into your OS
password vault (macOS Keychain or Windows Credential Manager), and Claude uses it **without ever
seeing it**.

```text
You:     /secret OPENAI_KEY
         ┌───────────────────────────────────────┐
         │  Paste the value for OPENAI_KEY       │   ← native hidden-input dialog
         │  [••••••••••••••••••••••••]  [Save]   │
         └───────────────────────────────────────┘
Claude:  Saved 'OPENAI_KEY' (51 chars) in macOS Keychain.

You:     list my OpenAI models
Claude:  secret run OPENAI_KEY=OPENAI_API_KEY -- curl https://api.openai.com/v1/models …
         {"data":[{"id":"gpt-…"}], …}        ← any echo of the key shows as [secret:OPENAI_API_KEY]
```

## ✨ Features

- **Never in the chat.** Values come in through a native hidden dialog, your clipboard, or a
  one-time phone link. They never pass through the conversation or the transcript, and the tool
  never puts them in a command line.
- **📱 Works from your phone.** Driving Claude Code over Remote Control? Send `/secret NAME phone`
  and get a one-time HTTPS link (single use, expires in 5 minutes). Paste on your phone and you're done.
- **🤖 Claude uses it on its own.** Ask "deploy with my Cloudflare token" and Claude finds the saved
  name and injects it as an environment variable for that one command.
- **🧹 Output is scrubbed.** Anything the command prints is checked, and the key is replaced with
  `[secret:NAME]` before Claude sees it, including its JSON-escaped, URL-encoded, hex and base64
  forms (so a `Basic` auth header gets caught too).
- **🔒 Your OS vault, not a dotfile.** It uses the macOS Keychain or Windows Credential Manager
  (DPAPI), so keys are encrypted at rest. No plaintext `.env` files and no extra service.
- **🛑 Hard to misuse.** It refuses multi-line or garbled values, reads every save back to confirm
  it, won't run under `bash -x`, and won't inject into variables like `PATH` or `LD_PRELOAD`.
- **🪶 Tiny.** Two small scripts plus an optional phone helper. Nothing to install from npm or pip.
  Review it in five minutes.

## 🚀 Install

**Easiest: just ask Claude Code**

> Install the /secret skill from https://github.com/alisarsur1306/claude-secret

**Or by hand** (macOS Terminal, or **Git Bash** on Windows):

```bash
d=$(mktemp -d) && git clone --depth 1 https://github.com/alisarsur1306/claude-secret "$d" && "$d/install.sh"
```

Then start a new Claude Code session. Run the same command again to update, or run
`install.sh --uninstall` from a clone to remove it. Your saved secrets are kept.

**Requirements:**
- macOS, or Windows with Git Bash (which Claude Code already uses on Windows).
- The phone link also needs Python 3 and `cloudflared`:
  - macOS: `brew install cloudflared`
  - Windows: `winget install Cloudflare.cloudflared`

## 🧭 Usage

| You type | What happens |
|---|---|
| `/secret NAME` | A native dialog with a hidden field opens. Paste, then Save. |
| `/secret NAME clipboard` | Copy the value first. It is read from the clipboard, which is then cleared. |
| `/secret NAME phone` | You get a one-time link for your phone (for Remote Control). |
| `/secret` | Lists saved names (never values). |
| *"use my GITHUB_TOKEN to …"* | Claude runs the command with the secret injected. |

Under the hood, Claude calls a small helper:

```bash
secret run GITHUB_TOKEN -- gh api user
secret run OPENAI_KEY=OPENAI_API_KEY -- python3 app.py     # NAME=ENV_VAR renames
secret list | secret has NAME | secret delete NAME
```

## 🛡️ Security model, honestly

**What it protects against**
- Secrets landing in the conversation, the transcript files on disk, or shell history.
- The tool itself never puts a value in a command line (`ps`). Values travel on stdin/stdout pipes
  and are handed to your command as an environment variable.
- Accidental echo: command output is redacted before Claude sees it.
- Pastejacking: multi-line or non-printable values are rejected before they reach the vault.
- Phone link abuse: the link has a random 192-bit token, works once, and expires in 5 minutes
  (enforced on every request, with a hard-stop watchdog). It binds only to `127.0.0.1` behind the
  tunnel, times out stalled connections, logs nothing, sends `no-store`/`no-referrer` headers, and
  shuts down after use.

**What it does not do**
- **It protects keys at rest, not from your own user account.** Any program running as you can
  ask the Keychain or Credential Manager for these items without a prompt. Claude is the program
  this tool is built to keep out, and the skill forbids it from reading the vault directly. On macOS
  you can make that a hard block with deny rules in `~/.claude/settings.json`:
  ```json
  "permissions": {
    "deny": [
      "Bash(security find-generic-password*)", "Bash(security find-internet-password*)",
      "Bash(security dump-keychain*)", "Bash(security export*)", "Bash(security -i*)"
    ],
    "ask": [ "Bash(*skills/secret/bin/secret run*)" ]
  }
  ```
  The `ask` rule makes Claude Code ask you before each use of a secret, which is the strongest guard
  against a prompt injection asking Claude to run a malicious script with your key. `/secret` keeps
  working with these rules, because its helper calls the Keychain itself. On Windows, reads go
  through `secret-win.ps1`, which refuses unless called by the helper. That stops accidents, but it
  is not a security boundary.
- What your command does with the key is up to the command. Redaction catches common encodings,
  but not a value that is split, reversed or written to a file and read back later. If a tool
  passes the key to a sub-process as a flag, it shows up in `ps` while that runs, so prefer tools
  that read keys from the environment or stdin.
- The phone link uses a Cloudflare quick tunnel. Traffic is HTTPS, but Cloudflare terminates TLS,
  so the value passes through Cloudflare's edge in transit.
- Clipboard mode clears the clipboard, but not a clipboard manager's history.
- Values must be one line of printable ASCII (up to 1280 characters on Windows).

## ❓ FAQ

**Why not just `/secret NAME my-key`?**
Everything typed in the message box is sent to the model and saved to the transcript before any
skill runs. No skill can intercept it, so `/secret` takes only the name.

**Can I see a saved value?**
Yes, in Keychain Access.app (search "Claude secret") or in Windows Credential Manager →
Windows Credentials (`claude-secret:NAME`). Claude won't show it to you in the chat.

**Does it work with Codex, Cursor, or other agents?**
The `secret` helper is a plain shell script, so any agent that can run shell commands can use
`secret run`. The `/secret` command and its instructions are written for Claude Code.

## 🤖 For AI agents installing this

1. Clone the repo into a temporary folder and run `install.sh` (on Windows, from Git Bash).
   Report its output.
2. Tell the user to start a new session and try `/secret NAME`.
3. Never ask the user to paste a secret value into the chat.

## License

MIT. If this kept a key out of your transcript, a ⭐ helps others find it.
