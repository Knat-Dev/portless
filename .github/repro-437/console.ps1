# Runs inside a real console window. Starts portless sharing this console,
# ends it via $Mode, and records process + console-mode state.
param([string]$Cli, [string]$Out, [string]$Mode, [int]$AppPort)
$ErrorActionPreference = "Stop"
Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);
'@
function ConMode { $h = [W.K]::GetStdHandle(-10); $m = [uint32]0; [void][W.K]::GetConsoleMode($h, [ref]$m); '0x{0:X}' -f $m }
function Rec($k, $v) { "$k=$v" | Out-File -Append -Encoding ascii "$Out\result.txt" }

Remove-Item Env:CI -ErrorAction SilentlyContinue
$env:REPRO_OUT = $Out
if ($Mode -eq "graceful") { $env:DEV_EXIT_AFTER_MS = "6000" }
Rec "mode_before" (ConMode)

$dev = Join-Path $PSScriptRoot "dev.cjs"
$p = Start-Process -FilePath node -ArgumentList "`"$Cli`"", "demo", "--app-port", "$AppPort", "node", "`"$dev`"" -NoNewWindow -PassThru -RedirectStandardOutput "$Out\portless.out" -RedirectStandardError "$Out\portless.err"
Rec "portless_pid" $p.Id
for ($i = 0; $i -lt 120 -and -not (Test-Path "$Out\dev.pid"); $i++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path "$Out\dev.pid")) { Rec "error" "dev server never started"; exit 1 }
$devPid = [int](Get-Content "$Out\dev.pid")
Rec "dev_pid" $devPid
Rec "mode_running" (ConMode)

if ($Mode -eq "forcekill") {
  taskkill /F /PID $p.Id | Out-Null
} else {
  $p.WaitForExit(30000) | Out-Null
}
Start-Sleep -Seconds 2
Rec "portless_alive" ([bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue))
Rec "dev_alive" ([bool](Get-Process -Id $devPid -ErrorAction SilentlyContinue))
Rec "mode_after" (ConMode)
Rec "ready" "1"
