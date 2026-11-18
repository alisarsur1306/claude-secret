#!/usr/bin/env python3
"""One-time phone page that saves a single secret into the OS credential store.

Started (detached) by `secret add NAME --phone` as:
    secret-phone.py NAME RUN_DIR BASH SECRET_SCRIPT
It:
  1. serves a tiny form on 127.0.0.1 at /s/<random 192-bit token>,
  2. exposes it through a Cloudflare quick tunnel (HTTPS, no account),
  3. accepts ONE successful save, handing the value to `secret add NAME --stdin`
     over stdin (never argv, never logged, never written to disk),
  4. shuts itself and the tunnel down on save or after TTL seconds.

Status for the caller lives in <run_dir>/<NAME>.{url,status,pid}; no values.
"""
import html
import http.server
import os
import re
import secrets
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

TTL = 300           # seconds the link stays valid
TUNNEL_WAIT = 45    # seconds to wait for cloudflared to come up
MAX_BODY = 16384

name, run_dir = sys.argv[1], sys.argv[2]
tool = sys.argv[3:5]   # [bash, secret script]: works on macOS and under Git Bash on Windows
if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,63}", name) or len(tool) != 2:
    sys.exit("usage: secret-phone.py NAME RUN_DIR BASH SECRET_SCRIPT")
token = secrets.token_urlsafe(24)
secret_path = f"/s/{token}"
files = {k: os.path.join(run_dir, f"{name}.{k}") for k in ("url", "status", "pid")}
done = threading.Event()


def write(kind, text):
    fd = os.open(files[kind], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text + "\n")


STYLE = """
:root{--bg:#f6f6f4;--card:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#d2d2d7;--acc:#0b63ce;--err:#c4291c;--ok:#1a7f37}
@media (prefers-color-scheme:dark){:root{--bg:#111;--card:#1c1c1e;--fg:#f5f5f7;--mut:#a1a1a6;--line:#3a3a3c;--acc:#4c9bff;--err:#ff6b5e;--ok:#3fb950}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 -apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;padding:16px}
main{width:100%;max-width:420px;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:24px}
h1{font-size:20px;margin:0 0 4px}p{margin:0 0 16px;color:var(--mut)}code{font:600 15px ui-monospace,monospace;color:var(--fg)}
input{width:100%;font:16px ui-monospace,monospace;padding:14px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--fg)}
button{width:100%;margin-top:12px;min-height:48px;font:600 16px -apple-system,system-ui,sans-serif;border:0;border-radius:10px;background:var(--acc);color:#fff}
button:active{opacity:.8}.err{color:var(--err);margin:12px 0 0}.ok{color:var(--ok);font-size:18px;font-weight:600}
"""


def page(body):
    return (
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        '<meta name=viewport content="width=device-width,initial-scale=1">'
        '<meta name=robots content=noindex><title>Save secret</title>'
        f"<style>{STYLE}</style></head><body><main>{body}</main></body></html>"
    )


def form_page(error=""):
    err = f'<p class=err role=alert>{html.escape(error)}</p>' if error else ""
    return page(
        f"<h1>Save secret</h1><p>Name: <code>{html.escape(name)}</code><br>"
        "Goes straight to the Mac's Keychain. Claude never sees it. This link works once.</p>"
        f'<form method=post action="{secret_path}" autocomplete=off>'
        '<label for=v style="position:absolute;left:-9999px">Secret value</label>'
        '<input id=v name=value type=password required autofocus autocapitalize=off '
        'autocorrect=off spellcheck=false placeholder="Paste value">'
        f"<button type=submit>Save to Keychain</button>{err}</form>"
    )


def msg_page(text, ok=False):
    cls = "ok" if ok else "err"
    return page(f'<p class={cls}>{html.escape(text)}</p>')


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "secret"
    sys_version = ""

    def log_message(self, *args):  # never log requests
        pass

    def reply(self, code, body):
        data = body.encode()
        self.send_response(code)
        for k, v in (
            ("Content-Type", "text/html; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Referrer-Policy", "no-referrer"),
            ("X-Robots-Tag", "noindex"),
            ("X-Frame-Options", "DENY"),
            ("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'"),
            ("Content-Length", str(len(data))),
        ):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def valid(self):
        return secrets.compare_digest(self.path, secret_path) and not done.is_set()

    def do_GET(self):
        if not self.valid():
            return self.reply(404, msg_page("This link has expired or was already used."))
        self.reply(200, form_page())

    def do_POST(self):
        if not self.valid():
            return self.reply(404, msg_page("This link has expired or was already used."))
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if not 0 < n <= MAX_BODY:
            return self.reply(400, form_page("Value too large or empty."))
        fields = urllib.parse.parse_qs(self.rfile.read(n).decode("utf-8", "replace"))
        value = (fields.get("value") or [""])[0].strip()
        if not value:
            return self.reply(200, form_page("Empty value — paste it and try again."))
        if "\n" in value or "\r" in value:
            return self.reply(200, form_page("Value must be a single line."))
        r = subprocess.run([*tool, "add", name, "--stdin"], input=value + "\n",
                           capture_output=True, text=True)
        value = fields = None
        if r.returncode != 0:
            err = (r.stderr or "").strip().removeprefix("secret: ")
            return self.reply(200, form_page(err or "Save failed — try again."))
        done.set()
        write("status", "saved: " + r.stdout.strip())
        self.reply(200, msg_page("Saved ✓ You can close this page and go back to Claude.", ok=True))


def start_tunnel(port):
    """Cloudflare quick tunnel. HOME points at an empty dir so the user's own
    ~/.cloudflared/config.yml (named tunnels) is never read or touched."""
    home = tempfile.mkdtemp(prefix="secret-cf-")
    env = dict(os.environ, HOME=home, USERPROFILE=home)  # USERPROFILE: Windows lookup
    proc = subprocess.Popen(
        ["cloudflared", "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, env=env)
    found = {"url": None}
    ready = threading.Event()

    def drain():
        for line in proc.stderr:  # keep draining so cloudflared never blocks
            m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
            if m and not found["url"]:
                found["url"] = m.group(0)
            if found["url"] and "Registered tunnel connection" in line:
                ready.set()

    threading.Thread(target=drain, daemon=True).start()
    ready.wait(TUNNEL_WAIT)
    return proc, found["url"] if ready.is_set() else None


def main():
    write("pid", str(os.getpid()))
    write("status", "starting")
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = 1
    proc, base = start_tunnel(server.server_address[1])
    try:
        if not base:
            write("status", "failed: Cloudflare tunnel did not start")
            return
        write("url", base + secret_path)
        write("status", "waiting")
        deadline = time.time() + TTL
        while not done.is_set() and time.time() < deadline:
            server.handle_request()
        if not done.is_set():
            write("status", "expired: nothing was saved")
    finally:
        server.server_close()
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
        for k in ("url", "pid"):
            try:
                os.unlink(files[k])
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    main()
