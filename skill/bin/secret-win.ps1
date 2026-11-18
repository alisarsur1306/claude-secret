# Windows backend for `secret` (called by the bash script under Git Bash).
# Stores values in Windows Credential Manager (generic credentials, DPAPI-encrypted,
# this machine only) under target "claude-secret:NAME".
#
#   write NAME     value on stdin
#   read NAME      value on stdout (only when CLAUDE_SECRET_INTERNAL=1)
#   exists NAME    exit 0 / 3
#   delete NAME    exit 0 / 3
#   dialog NAME    hidden-input window; value on stdout, exit 1 if cancelled
#   notify MSG     tray balloon notification (names/targets only)
#   confirm MSG    Allow/Deny window; prints allow|deny, denies after 120 s
#   clip-get       clipboard text on stdout
#   clip-clear     empty the clipboard
#   spawn EXE ARG...  start a detached hidden process (for the phone link)

param([Parameter(Mandatory = $true)][string]$Op, [string]$Name, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'

# For these ops $Name is a secret name; for notify/confirm/spawn it is a message or path.
if ($Op -in 'write', 'read', 'exists', 'delete', 'dialog' -and $Name -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,63}$') { [Console]::Error.WriteLine("invalid name"); exit 2 }
$Target = "claude-secret:$Name"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ClaudeSecretCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredWriteW(ref CREDENTIAL c, int flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredReadW(string target, int type, int flags, out IntPtr c);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredDeleteW(string target, int type, int flags);
  [DllImport("advapi32.dll")]
  static extern void CredFree(IntPtr p);

  public static void Write(string target, string secret) {
    byte[] b = Encoding.Unicode.GetBytes(secret);
    CREDENTIAL c = new CREDENTIAL();
    c.Type = 1;            // CRED_TYPE_GENERIC
    c.Persist = 2;         // CRED_PERSIST_LOCAL_MACHINE (not roamed)
    c.TargetName = target;
    c.UserName = "claude-secret";
    c.CredentialBlobSize = b.Length;
    c.CredentialBlob = Marshal.AllocHGlobal(b.Length);
    try {
      Marshal.Copy(b, 0, c.CredentialBlob, b.Length);
      if (!CredWriteW(ref c, 0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    } finally {
      for (int i = 0; i < b.Length; i++) Marshal.WriteByte(c.CredentialBlob, i, 0);
      Marshal.FreeHGlobal(c.CredentialBlob);
      Array.Clear(b, 0, b.Length);
    }
  }
  public static string Read(string target) {
    IntPtr p;
    if (!CredReadW(target, 1, 0, out p)) return null;
    try {
      CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    } finally { CredFree(p); }
  }
  public static bool Delete(string target) { return CredDeleteW(target, 1, 0); }
}
'@

switch ($Op) {
  'write' {
    $v = [Console]::In.ReadToEnd().TrimEnd("`r", "`n")
    if (-not $v) { [Console]::Error.WriteLine("empty value"); exit 2 }
    [ClaudeSecretCred]::Write($Target, $v)
    exit 0
  }
  'read' {
    if ($env:CLAUDE_SECRET_INTERNAL -ne '1') { [Console]::Error.WriteLine("read is internal to secret run"); exit 2 }
    $v = [ClaudeSecretCred]::Read($Target)
    if ($null -eq $v) { exit 3 }
    [Console]::Out.Write($v)
    exit 0
  }
  'exists' { if ($null -eq [ClaudeSecretCred]::Read($Target)) { exit 3 } else { exit 0 } }
  'delete' { if ([ClaudeSecretCred]::Delete($Target)) { exit 0 } else { exit 3 } }
  'dialog' {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Claude Code - save secret'; $f.Width = 440; $f.Height = 190
    $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $l = New-Object Windows.Forms.Label
    $l.Text = "Paste the value for secret  $Name`nSaved to Windows Credential Manager. Claude never sees it."
    $l.SetBounds(12, 12, 400, 36)
    $t = New-Object Windows.Forms.TextBox
    $t.UseSystemPasswordChar = $true; $t.SetBounds(12, 56, 400, 24)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Save'; $ok.SetBounds(236, 100, 84, 30)
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $no = New-Object Windows.Forms.Button; $no.Text = 'Cancel'; $no.SetBounds(328, 100, 84, 30)
    $no.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $f.Controls.AddRange(@($l, $t, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    $f.Add_Shown({ $f.Activate(); $t.Focus() })
    if ($f.ShowDialog() -ne [Windows.Forms.DialogResult]::OK -or -not $t.Text) { exit 1 }
    [Console]::Out.Write($t.Text)
    exit 0
  }
  'notify' {
    # $Name holds the message here (names/targets only).
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $n = New-Object Windows.Forms.NotifyIcon
    $n.Icon = [Drawing.SystemIcons]::Shield; $n.Visible = $true
    $n.ShowBalloonTip(6000, 'claude-secret', $Name, [Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 7; $n.Dispose()
    exit 0
  }
  'confirm' {
    # $Name holds the question. Prints allow/deny; denies after 120 s.
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form
    $f.Text = 'claude-secret'; $f.TopMost = $true; $f.AutoSize = $true; $f.AutoSizeMode = 'GrowAndShrink'
    $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.Padding = New-Object Windows.Forms.Padding(12)
    # Wrapping label: the whole message (incl. the destination) is always visible.
    $l = New-Object Windows.Forms.Label; $l.Text = $Name; $l.AutoSize = $true
    $l.MaximumSize = New-Object Drawing.Size(520, 0); $l.Location = New-Object Drawing.Point(12, 12)
    $f.Controls.Add($l); $f.PerformLayout()
    $y = $l.Bottom + 16
    $a = New-Object Windows.Forms.Button; $a.Text = 'Allow'; $a.SetBounds(356, $y, 84, 30)
    $a.DialogResult = [Windows.Forms.DialogResult]::Yes
    $d = New-Object Windows.Forms.Button; $d.Text = 'Deny'; $d.SetBounds(448, $y, 84, 30)
    $d.DialogResult = [Windows.Forms.DialogResult]::No
    $f.Controls.AddRange(@($a, $d)); $f.AcceptButton = $d; $f.CancelButton = $d
    $t = New-Object Windows.Forms.Timer; $t.Interval = 120000
    $t.Add_Tick({ $t.Stop(); $f.DialogResult = [Windows.Forms.DialogResult]::No; $f.Close() }); $t.Start()
    $f.Add_Shown({ $f.Activate() })
    if ($f.ShowDialog() -eq [Windows.Forms.DialogResult]::Yes) { [Console]::Out.Write('allow') } else { [Console]::Out.Write('deny') }
    exit 0
  }
  'clip-get' { $c = Get-Clipboard -Raw; if ($c) { [Console]::Out.Write($c.TrimEnd("`r", "`n")) }; exit 0 }
  'clip-clear' {
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.Clipboard]::Clear()
    exit 0
  }
  'spawn' {
    # $Name holds the executable here; $Rest its arguments.
    $quoted = @($Rest | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' })
    Start-Process -WindowStyle Hidden -FilePath $Name -ArgumentList $quoted | Out-Null
    exit 0
  }
  default { [Console]::Error.WriteLine("unknown op $Op"); exit 2 }
}
