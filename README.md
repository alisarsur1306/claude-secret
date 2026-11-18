# /secret: secrets Claude Code can use but never see

A [Claude Code](https://claude.com/claude-code) skill that saves API keys, tokens and passwords
to the **macOS Keychain** and lets Claude run commands with them, without the value ever
appearing in the chat, the session transcript, or tool output.

```
You:     /secret OPENAI_KEY
Claude:  A dialog opened. Paste the value there.
         Saved 'OPENAI_KEY' (51 chars) in macOS Keychain.

You:     list my OpenAI models
Claude:  (runs: secret run OPENAI_KEY=OPENAI_API_KEY -- curl … )
         … output, with the key shown as [secret:OPENAI_API_KEY]
```

## Why not just paste the key in chat?

Everything you type in the message box, including `/secret NAME value`, is sent to the model
and written to the session transcript on disk. No skill can intercept it first. So `/secret`
takes only the **name** and collects the value through a channel that never touches the chat.

## Install

**Ask Claude** (in any Claude Code session):

> Install the /secret skill from https://github.com/alisarsur1306/claude-secret

**Or by hand:**

```bash
gh repo clone alisarsur1306/claude-secret /tmp/claude-secret && /tmp/claude-secret/install.sh
```

Then start a new Claude Code session. Update the same way. To remove it, run `./install.sh --uninstall`
(your Keychain items are kept).

Requires macOS. The phone link also needs `python3` and `cloudflared` (`brew install cloudflared`).

## Saving a secret

| You type | What happens |
|---|---|
| `/secret NAME` | A macOS dialog with a hidden field opens on the Mac. Paste, then Save. |
| `/secret NAME clipboard` | Copy the value first. It is read from the clipboard, which is then cleared. Works from an iPhone nearby via Universal Clipboard. |
| `/secret NAME phone` | For Remote Control from your phone: Claude sends a **one-time link** (single use, 5 min). Open it on your phone, paste, Save. |
| `/secret` | Lists saved names (never values). |

Names use letters, digits and `_` (e.g. `GITHUB_TOKEN`).

## Using a secret

Just ask: "deploy with my CF token", "call the API using OPENAI_KEY". Claude finds the saved
name and runs the command through the helper:

```bash
secret run GITHUB_TOKEN -- gh api user
secret run OPENAI_KEY=OPENAI_API_KEY -- python3 script.py     # NAME=ENV_VAR renames
secret run API_KEY -- sh -c 'curl -H "Authorization: Bearer $API_KEY" https://api.example.com'
```

The value is exported only into that command's environment. Its stdout and stderr are merged,
and every occurrence of the value (and its base64 form) is replaced with `[secret:ENV]`.

Other commands: `secret list`, `secret has NAME`, `secret delete NAME`, `secret help`.
The helper lives at `~/.claude/skills/secret/bin/secret`.

## Security model, honestly

**Protected:**
- Values never pass through the chat, the transcript, or command-line arguments. They are
  written to the Keychain over stdin via `security -i`.
- Command output is redacted before Claude sees it.
- Phone link: a random 192-bit token in the URL, single use, expires after 5 minutes, binds only
  to `127.0.0.1` behind the tunnel, logs no requests, sends `no-store`/`no-referrer` headers, and
  the server and tunnel shut down after use.

**Not protected:**
- **Claude is trusted not to read the Keychain.** The skill forbids it, but nothing technically
  stops a model with shell access from running `security find-generic-password -w`. For a hard
  block, add deny rules to your Claude Code settings, for example
  `"deny": ["Bash(security find-generic-password:*)", "Bash(security dump-keychain:*)"]`.
- Redaction is line-based. A command that transforms or splits the value (e.g. reverses it)
  would not be caught.
- The phone link uses a Cloudflare quick tunnel. Traffic is HTTPS, but Cloudflare terminates
  TLS, so the value passes through Cloudflare's edge in transit.
- Values must be printable ASCII (the Keychain CLI prints other values as hex).

## For AI agents installing this

1. Clone the repo, using `gh repo clone alisarsur1306/claude-secret <tmpdir>` because it is private.
2. Run `<tmpdir>/install.sh` and report its output.
3. Tell the user to start a new session and try `/secret NAME`.
4. Never ask the user to paste a secret value into the chat.

## License

MIT — see [LICENSE](LICENSE).
