---
name: secret
description: Save a secret (API key, token, password) to the macOS Keychain through a hidden-input dialog, the clipboard, or a one-time phone link (for Remote Control), and run commands with it injected as an env var — the value never enters the chat, the transcript or tool output. Use for "/secret NAME", "save my token", "store this API key", "use my GITHUB_TOKEN", "תשמור סוד/טוקן", or whenever a command needs a credential the user saved earlier. macOS only.
argument-hint: NAME [phone|clipboard]  (never the value)
---

# /secret — Keychain-backed secrets Claude can use but never see

Tool: `~/.claude/skills/secret/bin/secret` (call it `$S` below). Values live in the macOS login
Keychain (service `claude-secret`, account = NAME). Only names are ever printed.

## Why the value must never be typed in chat

Anything typed in the message box — including `/secret NAME abc123` — is sent to the model and
written to the session transcript on disk (`~/.claude/projects/**.jsonl`). The only safe ways in
are the hidden dialog, the clipboard, or the one-time phone link, where the value goes straight from
the user to the Keychain.

## On `/secret <args>`

1. **Args are a single name** (e.g. `/secret GITHUB_TOKEN`): run `$S add GITHUB_TOKEN`. A macOS dialog
   with a hidden field pops up; tell the user in one line to paste the value there. Report the
   tool's one-line result (name + length only).
   If the user is on their phone (Remote Control), use the phone flow (step 3) instead, since the
   dialog appears on the Mac where nobody can see it.
2. **Args are a name + `clipboard`** (`/secret GITHUB_TOKEN clipboard`): the user copied the value
   first. Run `$S add GITHUB_TOKEN --clipboard` (it reads then clears the clipboard). With an
   iPhone near the Mac on the same Apple ID, Universal Clipboard makes this work from the phone too.
3. **Args are a name + `phone`** (`/secret GITHUB_TOKEN phone`), or the user is on their phone:
   1. Run `$S add GITHUB_TOKEN --phone`. It prints a one-time HTTPS link (Cloudflare quick tunnel,
      single use, expires in 5 min).
   2. Send the user the link as a **bare URL on its own line** (not a `[text](url)` markdown link —
      some Remote Control views drop it) and tell them to paste the value into the hidden field
      and tap Save.
   3. Run `$S wait GITHUB_TOKEN` with `run_in_background: true` (you are notified when it ends; do
      not poll), then report its one-line result. On `expired`, offer a new link.
   The link carries a random token, so it is safe to show in chat; once used or expired it is dead.
   Cloudflare terminates TLS, so the value passes through Cloudflare's edge in transit.
4. **No args**: run `$S list` and show the names, plus how to add one.
5. **Args contain anything that looks like a value** (a second token that is not `clipboard`/`phone`, or a
   single token that looks like a key, e.g. `sk-…`, `ghp_…`, long random string):
   - Do **not** store, repeat, echo, or quote it — not even partially.
   - Tell the user: that value is now in this conversation and its transcript, so treat it as
     exposed and rotate it at the provider; then save the new one with `/secret NAME` (dialog).
6. Names: letters, digits, `_`; must not start with a digit. Suggest an UPPER_SNAKE name if the
   user gave none.

## Using a saved secret

When the user asks for something that needs a credential (e.g. "deploy with my CF token", "call the
API using OPENAI_KEY"), check `$S list` for a matching name and use it yourself via `$S run` —
no need to ask them for the value. If none matches, ask them to save one (`/secret NAME`, or the
phone link when they're remote).

```bash
$S run GITHUB_TOKEN -- gh api user
$S run OPENAI_KEY=OPENAI_API_KEY -- python3 script.py           # NAME=ENV_VAR to rename
$S run CF_TOKEN=CLOUDFLARE_API_TOKEN DB_PASS -- ./deploy.sh      # several at once
$S run API_KEY -- sh -c 'curl -sH "Authorization: Bearer $API_KEY" https://api.example.com/me'
```

- The secret is exported only into that command's environment. stdout and stderr are merged and
  every injected value (and its base64 form) is replaced with `[secret:ENV]` before printing.
- Reference the value as `$ENV` **inside** `sh -c '…'` with single quotes, so the expansion
  happens in the child shell and never in the visible command line.
- Check a name exists without reading it: `$S has NAME`. List names: `$S list`.

## Hard rules (the redaction is a safety net, not permission)

- Never run `security find-generic-password … -w`, `security dump-keychain -d`, or anything that
  prints a value.
- Never run `$S run X -- env|printenv|echo|cat|set`, or anything that prints, encodes (hex,
  rev, url-encode, split), writes to a file, or sends the value anywhere except the service it is for.
- Never paste a value into code, config, commits, or tool arguments; the command reads it from env.
- `$S delete NAME` deletes a Keychain item permanently — confirm with the user first. Use
  `delete`, not `rm`: Claude Code's removal safety check blocks `<variable> rm …`.
- Call the tool by its full path (`~/.claude/skills/secret/bin/secret`); `$S` here is shorthand.
- If the user asks you to show a secret, decline and point them to Keychain Access.app
  (search "Claude secret: NAME").

## Limits

- macOS only (Keychain). On Windows/Linux the tool exits with a clear error.
- Values must be printable ASCII (Keychain returns other values as hex).
- Redaction is line-based; a value split across lines or transformed by the command is not caught.
