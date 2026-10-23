# Isolated tests for auto-upload.ps1. Uses local bare repos only; never touches GitHub.
# Run: powershell.exe -NoProfile -File scripts\auto-upload\tests\run-tests.ps1
# Windows PowerShell 5.1 compatible. Keep this file ASCII-only.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$SrcDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$Tmp = Join-Path $env:TEMP ('au test ' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$script:Pass = 0; $script:Fail = 0; $script:Failures = @()
$MainName = 'yuuka-ai-channel-os-portfolio'
$AutoName = $MainName + '-auto'

function G { param([string]$Dir, [string[]]$A) $ErrorActionPreference = 'Continue'; $o = & git.exe -c core.quotepath=false -C $Dir @A 2>&1; if ($LASTEXITCODE -ne 0) { throw ("git " + ($A -join ' ') + " failed: " + ($o -join "`n")) }; return ($o -join "`n") }
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-Output ("PASS  " + $name) }
    else { $script:Fail++; $script:Failures += $name; Write-Output ("FAIL  " + $name + "  " + $detail) }
}
function WriteFile([string]$path, [string]$text) {
    $d = Split-Path -Parent $path
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

# Fixture: bare origin + main clone + linked auto worktree with the real script installed and pushed.
function New-Fixture([string]$tag, [switch]$NoInit, [switch]$NoEnable) {
    $base = Join-Path $Tmp $tag
    New-Item -ItemType Directory -Path $base | Out-Null
    $origin = Join-Path $base 'origin.git'
    G $base @('init', '-q', '--bare', '-b', 'main', $origin) | Out-Null
    $seed = Join-Path $base 'seed'
    G $base @('clone', '-q', $origin, $seed) | Out-Null
    G $seed @('config', 'user.name', 'tester'); G $seed @('config', 'user.email', 'tester@example.invalid')
    WriteFile (Join-Path $seed 'package.json') '{"name":"fx","private":true,"scripts":{"lint":"node tools/check.js lint","build":"node tools/check.js build"}}'
    WriteFile (Join-Path $seed 'tools\check.js') @'
const fs = require('fs');
const kind = process.argv[2];
if (kind === 'lint' && process.env.AU_FAIL_LINT) process.exit(1);
if (kind === 'build') {
  if (process.env.AU_FAIL_BUILD) process.exit(1);
  if (process.env.AU_MUTATE) fs.appendFileSync('src/app.txt', 'mutated\n');
  if (process.env.AU_SLEEP_BUILD) { const t = Date.now(); while (Date.now() - t < Number(process.env.AU_SLEEP_BUILD)) {} }
}
'@
    WriteFile (Join-Path $seed 'src\app.txt') "hello`n"
    WriteFile (Join-Path $seed 'src\old.txt') "old`n"
    WriteFile (Join-Path $seed '.gitignore') "node_modules`ndist`n.env`n.env.*`n!.env.example`n"
    G $seed @('add', '-A') | Out-Null; G $seed @('commit', '-q', '-m', 'chore: seed'); G $seed @('push', '-q', 'origin', 'main')
    $mainDir = Join-Path $base $MainName
    G $base @('clone', '-q', $origin, $mainDir) | Out-Null
    G $mainDir @('config', 'user.name', 'tester'); G $mainDir @('config', 'user.email', 'tester@example.invalid')
    $auto = Join-Path $base $AutoName
    G $mainDir @('worktree', 'add', '-q', '-b', 'auto/claude', $auto, 'main') | Out-Null
    $dst = Join-Path $auto 'scripts\auto-upload'
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item (Join-Path $SrcDir 'auto-upload.ps1') $dst
    $cfg = Get-Content -Raw (Join-Path $SrcDir 'config.json') | ConvertFrom-Json
    $cfg.expectedOrigin = $origin
    $cfg.audit.mode = 'disabled'
    [IO.File]::WriteAllText((Join-Path $dst 'config.json'), ($cfg | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    G $auto @('add', '--', 'scripts/auto-upload/auto-upload.ps1', 'scripts/auto-upload/config.json') | Out-Null
    G $auto @('commit', '-q', '-m', 'chore: install automation'); G $auto @('push', '-q', 'origin', 'auto/claude')
    $fx = [pscustomobject]@{ Base = $base; Origin = $origin; Main = $mainDir; Auto = $auto; Script = (Join-Path $dst 'auto-upload.ps1'); Seed = $seed }
    Invoke-AU $fx @('approve', '-Yes') | Out-Null
    if (-not $NoEnable) { Invoke-AU $fx @('enable') | Out-Null }
    if (-not $NoInit) { Invoke-AU $fx @('run') | Out-Null }
    return $fx
}

function Invoke-AU($fx, [string[]]$A, [string]$StdIn = $null, [string]$Script = $null) {
    $ErrorActionPreference = 'Continue'
    if (-not $Script) { $Script = $fx.Script }
    $args2 = @('-NoProfile', '-File', $Script) + $A
    if ($StdIn) { $out = $StdIn | & powershell.exe @args2 2>&1 } else { $out = & powershell.exe @args2 2>&1 }
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = (($out | ForEach-Object { "$_" }) -join "`n") }
}
function Last($fx) {
    $gd = (G $fx.Auto @('rev-parse', '--absolute-git-dir')).Trim()
    $p = Join-Path $gd 'auto-upload\last-status.json'
    if (Test-Path $p) { return (Get-Content -Raw $p | ConvertFrom-Json) }
    return $null
}
function StateFile($fx, [string]$name) { return (Join-Path ((G $fx.Auto @('rev-parse', '--absolute-git-dir')).Trim()) ('auto-upload\' + $name)) }
function RemoteSha($fx) { $l = (G $fx.Auto @('ls-remote', '--heads', 'origin', 'auto/claude')).Trim(); if ($l) { return ($l -split '\s+')[0] }; return '' }
function Head($fx) { return (G $fx.Auto @('rev-parse', 'HEAD')).Trim() }
function Count($fx) { return [int](G $fx.Auto @('rev-list', '--count', 'HEAD')).Trim() }
function Hook($fx, [string]$cwd = $null, [bool]$active = $false) {
    if (-not $cwd) { $cwd = $fx.Auto }
    $json = (@{ session_id = 't'; cwd = $cwd; hook_event_name = 'Stop'; stop_hook_active = $active } | ConvertTo-Json -Compress)
    return (Invoke-AU $fx @('hook') $json)
}
function ClearEnv { foreach ($n in 'AU_FAIL_LINT', 'AU_FAIL_BUILD', 'AU_MUTATE', 'AU_SLEEP_BUILD') { Remove-Item "Env:$n" -ErrorAction SilentlyContinue } }

try {
    # ---- unit: dot-sourced functions
    . (Join-Path $SrcDir 'auto-upload.ps1')
    $fake = 'AKIA' + 'IOSFODNN7EXAMPLE'
    $ghTok = 'ghp_' + ('a1B2c3D4e5' * 4)
    $pk = '-----BEGIN ' + 'RSA PRIVATE KEY-----'
    $assign = 'api_key = "' + 'abcd1234efgh5678' + '"'
    Check 'unit: aws key detected' ((@(Find-SecretHits -Text "x = $fake" -Label f)).Count -ge 1)
    Check 'unit: github token detected' ((@(Find-SecretHits -Text "t=$ghTok" -Label f)).Count -ge 1)
    Check 'unit: private key block detected' ((@(Find-SecretHits -Text $pk -Label f)).Count -ge 1)
    Check 'unit: credential assignment detected' ((@(Find-SecretHits -Text $assign -Label f)).Count -ge 1)
    Check 'unit: hit text never contains the value' (((@(Find-SecretHits -Text "x = $fake" -Label f)) -join ' ') -notmatch 'IOSFODNN')
    Check 'unit: plain code is clean' ((@(Find-SecretHits -Text 'const total = items.length + 1; // token count' -Label f)).Count -eq 0)
    Check 'unit: lockfile integrity lines skipped' ((@(Find-SecretHits -Text '"integrity": "sha512-AKIAIOSFODNN7EXAMPLEAKIAIOSFODNN7EXAMPLE=="' -Label f -IsLockFile $true)).Count -eq 0)
    $base = @{ a = @{ severity = 'high'; advisories = @('1'); viaPackages = @('b'); nodes = @('node_modules/a') } }
    Check 'unit: audit identical passes' ((@(Compare-Audit $base $base)).Count -eq 0)
    $worse = @{ a = @{ severity = 'critical'; advisories = @('1'); viaPackages = @('b'); nodes = @('node_modules/a') } }
    Check 'unit: audit severity worsened blocks' ((@(Compare-Audit $worse $base)).Count -ge 1)
    $newpkg = @{ a = $base.a; z = @{ severity = 'low'; advisories = @('9'); viaPackages = @(); nodes = @() } }
    Check 'unit: audit new package blocks' ((@(Compare-Audit $newpkg $base)).Count -ge 1)
    $newadv = @{ a = @{ severity = 'high'; advisories = @('1', '2'); viaPackages = @('b'); nodes = @('node_modules/a') } }
    Check 'unit: audit new advisory blocks' ((@(Compare-Audit $newadv $base)).Count -ge 1)
    $newpath = @{ a = @{ severity = 'high'; advisories = @('1'); viaPackages = @('b'); nodes = @('node_modules/a', 'node_modules/x/a') } }
    Check 'unit: audit new install path blocks' ((@(Compare-Audit $newpath $base)).Count -ge 1)
    $better = @{ }
    Check 'unit: audit improvement passes' ((@(Compare-Audit $better $base)).Count -eq 0)
    Check 'unit: Quote-Arg handles spaces' ((Quote-Arg 'a b') -eq '"a b"')
    Check 'unit: forbidden names' ((Test-ForbiddenName '.env.local') -and (Test-ForbiddenName 'a/b/server.pem') -and (-not (Test-ForbiddenName '.env.example')) -and (-not (Test-ForbiddenName 'src/App.tsx')))

    # ---- shipped files must not trip our own scanner
    $own = @('auto-upload.ps1', 'config.json', 'tests\run-tests.ps1') | ForEach-Object { Join-Path $SrcDir $_ }
    $ownHits = @()
    foreach ($f in $own) { $ownHits += @(Find-SecretHits -Text (Get-Content -Raw $f) -Label (Split-Path -Leaf $f)) }
    Check 'shipped automation files pass the secret scan' ($ownHits.Count -eq 0) ($ownHits -join '; ')

    # ---- 1 no changes
    $fx = New-Fixture 't01'
    $h0 = Head $fx; $r0 = RemoteSha $fx
    $r = Invoke-AU $fx @('run')
    Check 'no changes: skipped, exit 0' ($r.Exit -eq 0 -and $r.Out -match 'no-changes') $r.Out
    Check 'no changes: no commit, remote unchanged' ((Head $fx) -eq $h0 -and (RemoteSha $fx) -eq $r0)

    # ---- 2 success: modify + add (space/Korean name) + delete, one commit per file
    $fx = New-Fixture 't02'
    $c0 = Count $fx
    $kor = ([string][char]0xD55C) + ([string][char]0xAE00)
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "hello world`n"
    WriteFile (Join-Path $fx.Auto ('docs\my note ' + $kor + '.md')) "note`n"
    Remove-Item (Join-Path $fx.Auto 'src\old.txt')
    $r = Invoke-AU $fx @('run')
    Check 'success: run reports pushed' ($r.Exit -eq 0 -and $r.Out -match 'pushed') $r.Out
    Check 'success: three per-file commits' (((Count $fx) - $c0) -eq 3) ("delta=" + ((Count $fx) - $c0))
    Check 'success: remote SHA equals local SHA' ((RemoteSha $fx) -eq (Head $fx))
    $subjects = (G $fx.Auto @('log', '-3', '--format=%s'))
    Check 'success: conventional commit subjects' (($subjects -split "`n" | Where-Object { $_ -match '^(chore|docs): (add|update|remove) .+ \(auto-upload\)$' }).Count -eq 3) $subjects
    $multi = 0; foreach ($sha in ((G $fx.Auto @('log', '-3', '--format=%H')) -split "`n")) { if (((G $fx.Auto @('show', '--name-only', '--format=', $sha)) -split "`n" | Where-Object { $_ }).Count -ne 1) { $multi++ } }
    Check 'success: each commit touches exactly one file' ($multi -eq 0)
    Check 'success: worktree clean afterwards' ((G $fx.Auto @('status', '--porcelain')).Trim() -eq '')
    Check 'success: korean file name committed intact' ((G $fx.Auto @('ls-files')) -match ('docs/my note ' + $kor + '\.md'))

    # ---- 3/4 lint / build failure
    $fx = New-Fixture 't03'
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "changed`n"
    $h0 = Head $fx; $r0 = RemoteSha $fx
    $env:AU_FAIL_LINT = '1'; $r = Invoke-AU $fx @('run'); ClearEnv
    Check 'lint failure blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'lint-failed') $r.Out
    Check 'lint failure: no commit, no push, change kept' ((Head $fx) -eq $h0 -and (RemoteSha $fx) -eq $r0 -and (G $fx.Auto @('status', '--porcelain')) -match 'src/app.txt')
    $env:AU_FAIL_BUILD = '1'; $r = Invoke-AU $fx @('run'); ClearEnv
    Check 'build failure blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'build-failed') $r.Out
    Check 'build failure: nothing pushed' ((RemoteSha $fx) -eq $r0)

    # ---- 5 secret pattern
    $fx = New-Fixture 't05'
    WriteFile (Join-Path $fx.Auto 'src\leak.txt') ("key = " + $fake + "`n")
    $r = Invoke-AU $fx @('run')
    Check 'secret pattern blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'secret-found') $r.Out
    Check 'secret value not printed or logged' (($r.Out -notmatch 'IOSFODNN') -and ((Get-Content -Raw (StateFile $fx 'auto-upload.log')) -notmatch 'IOSFODNN'))
    Check 'secret: nothing committed or staged' ((G $fx.Auto @('diff', '--cached', '--name-only')).Trim() -eq '' -and (RemoteSha $fx) -eq (Head $fx))

    # ---- 6 forbidden file name
    $fx = New-Fixture 't06'
    WriteFile (Join-Path $fx.Auto 'credentials.json') "{}`n"
    $r = Invoke-AU $fx @('run')
    Check 'forbidden file name blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'forbidden-file') $r.Out

    # ---- 7 wrong branch / origin / path
    $fx = New-Fixture 't07'
    G $fx.Auto @('switch', '-q', '-c', 'other') | Out-Null
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "x`n"
    $r = Invoke-AU $fx @('run')
    Check 'wrong branch blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'location-mismatch') $r.Out
    G $fx.Auto @('switch', '-q', 'auto/claude') | Out-Null
    G $fx.Auto @('remote', 'set-url', 'origin', (Join-Path $fx.Base 'elsewhere.git'))
    $r = Invoke-AU $fx @('run')
    Check 'wrong origin blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'location-mismatch') $r.Out
    G $fx.Auto @('remote', 'set-url', 'origin', $fx.Origin)
    $wrong = Join-Path $fx.Base 'wrong-folder'
    G $fx.Base @('clone', '-q', $fx.Origin, $wrong) | Out-Null
    G $wrong @('switch', '-q', 'auto/claude')
    $r = Invoke-AU $fx @('run') $null (Join-Path $wrong 'scripts\auto-upload\auto-upload.ps1')
    Check 'wrong folder blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'location-mismatch') $r.Out
    $hk = Hook $fx (Join-Path $fx.Base 'somewhere-else')
    Check 'hook outside dedicated folder is rejected, exit 0' ($hk.Exit -eq 0 -and $hk.Out -match 'location-mismatch') $hk.Out

    # ---- 8 pre-existing staged change
    $fx = New-Fixture 't08'
    WriteFile (Join-Path $fx.Auto 'src\old.txt') "user staged`n"
    G $fx.Auto @('add', '--', 'src/old.txt')
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "auto change`n"
    $r0 = RemoteSha $fx
    $r = Invoke-AU $fx @('run')
    Check 'pre-existing staged change aborts' ($r.Exit -eq 1 -and $r.Out -match 'staged-changes') $r.Out
    Check 'user staged file stays staged, nothing pushed' ((G $fx.Auto @('diff', '--cached', '--name-only')) -match 'src/old.txt' -and (RemoteSha $fx) -eq $r0)

    # ---- 9 concurrent runs
    $fx = New-Fixture 't09'
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "concurrent`n"
    $c0 = Count $fx
    $env:AU_SLEEP_BUILD = '5000'
    $pa = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-File', ('"' + $fx.Script + '"'), 'run') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $fx.Base 'a.out')
    Start-Sleep -Seconds 3
    $rb = Invoke-AU $fx @('run')
    $pa.WaitForExit(); ClearEnv
    Check 'concurrent: second run skipped as locked' ($rb.Out -match 'locked') $rb.Out
    Check 'concurrent: exactly one commit and remote in sync' (((Count $fx) - $c0) -eq 1 -and (RemoteSha $fx) -eq (Head $fx)) ("delta=" + ((Count $fx) - $c0))
    Check 'concurrent: lock released' (-not (Test-Path (StateFile $fx 'run.lock')))

    # ---- stale lock is recovered
    $fx = New-Fixture 't09b'
    WriteFile (StateFile $fx 'run.lock') ("999999 " + (Get-Date).ToUniversalTime().AddHours(-3).ToString('o'))
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "after stale lock`n"
    $r = Invoke-AU $fx @('run')
    Check 'stale lock from dead process is replaced' ($r.Exit -eq 0 -and $r.Out -match 'pushed') $r.Out

    # ---- 10 disabled
    $fx = New-Fixture 't10'
    Invoke-AU $fx @('disable') | Out-Null
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "while disabled`n"
    $h0 = Head $fx; $r0 = RemoteSha $fx
    $hk = Hook $fx
    Check 'disabled: hook exits 0 silently' ($hk.Exit -eq 0 -and $hk.Out.Trim() -eq '') $hk.Out
    Check 'disabled: nothing committed or pushed' ((Head $fx) -eq $h0 -and (RemoteSha $fx) -eq $r0)

    # ---- 11 push failure, then recovery on the next run
    $fx = New-Fixture 't11'
    $hookFile = Join-Path $fx.Origin 'hooks\pre-receive'
    WriteFile $hookFile "#!/bin/sh`necho 'blocked by test' >&2`nexit 1`n"
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "push will fail`n"
    $r0 = RemoteSha $fx; $c0 = Count $fx
    $r = Invoke-AU $fx @('run')
    Check 'push failure is reported' ($r.Exit -eq 1 -and $r.Out -match 'push') $r.Out
    Check 'push failure: commit kept locally, remote unchanged' (((Count $fx) - $c0) -eq 1 -and (RemoteSha $fx) -eq $r0)
    Remove-Item $hookFile -Force
    $r = Invoke-AU $fx @('run')
    Check 'next run notices unpushed commit and uploads it' ($r.Exit -eq 0 -and $r.Out -match 'pushed') $r.Out
    Check 'recovery: remote equals local, no extra commit' ((RemoteSha $fx) -eq (Head $fx) -and ((Count $fx) - $c0) -eq 1)

    # ---- 12 remote conflict: no merge, no force
    $fx = New-Fixture 't12'
    $other = Join-Path $fx.Base 'other'
    G $fx.Base @('clone', '-q', '-b', 'auto/claude', $fx.Origin, $other) | Out-Null
    G $other @('config', 'user.name', 'other'); G $other @('config', 'user.email', 'o@example.invalid')
    WriteFile (Join-Path $other 'remote-only.txt') "remote`n"
    G $other @('add', '--', 'remote-only.txt'); G $other @('commit', '-q', '-m', 'chore: remote change'); G $other @('push', '-q', 'origin', 'auto/claude')
    $theirs = RemoteSha $fx
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "local change`n"
    $h0 = Head $fx
    $r = Invoke-AU $fx @('run')
    Check 'remote ahead: aborts without merge or force' ($r.Exit -eq 1 -and $r.Out -match 'remote-ahead|diverged') $r.Out
    Check 'remote ahead: remote untouched, no local commit' ((RemoteSha $fx) -eq $theirs -and (Head $fx) -eq $h0)
    # diverged: make a local commit, then rerun
    G $fx.Auto @('add', '--', 'src/app.txt'); G $fx.Auto @('commit', '-q', '-m', 'chore: local commit')
    $r = Invoke-AU $fx @('run')
    Check 'diverged history aborts without rebase' ($r.Exit -eq 1 -and $r.Out -match 'diverged') $r.Out
    Check 'diverged: remote still the other side' ((RemoteSha $fx) -eq $theirs)

    # ---- 13 source changes during checks
    $fx = New-Fixture 't13'
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "before build`n"
    $r0 = RemoteSha $fx; $c0 = Count $fx
    $env:AU_MUTATE = '1'; $r = Invoke-AU $fx @('run'); ClearEnv
    Check 'change during checks blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'source-changed-during-checks') $r.Out
    Check 'change during checks: no commit, no push' ((Count $fx) -eq $c0 -and (RemoteSha $fx) -eq $r0)

    # ---- 14 protected file tamper
    $fx = New-Fixture 't14'
    [IO.File]::AppendAllText((Join-Path $fx.Auto 'scripts\auto-upload\config.json'), "`n")
    $r0 = RemoteSha $fx
    $r = Invoke-AU $fx @('run')
    Check 'protected automation file change blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'protected-changed') $r.Out
    Check 'protected change: nothing pushed' ((RemoteSha $fx) -eq $r0)
    $st = Invoke-AU $fx @('status')
    Check 'status shows protected change' ($st.Out -match 'CHANGED')

    # ---- 15 first run with existing changes
    $fx = New-Fixture 't15' -NoInit
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "existing user change`n"
    $r = Invoke-AU $fx @('run')
    Check 'first run with existing changes aborts' ($r.Exit -eq 1 -and $r.Out -match 'first-run-dirty') $r.Out

    # ---- 16 hook mode behavior
    $fx = New-Fixture 't16'
    $hk = Hook $fx
    Check 'hook, no changes: silent exit 0' ($hk.Exit -eq 0 -and $hk.Out.Trim() -eq '') $hk.Out
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "hook change`n"
    $hk = Hook $fx $null $true
    Check 'hook with stop_hook_active=true does nothing' ($hk.Exit -eq 0 -and $hk.Out.Trim() -eq '' -and (RemoteSha $fx) -ne '' -and (G $fx.Auto @('status', '--porcelain')) -match 'src/app.txt')
    $env:AU_FAIL_LINT = '1'; $hk = Hook $fx; ClearEnv
    $okjson = $false; try { $j = $hk.Out | ConvertFrom-Json; $okjson = ($j.systemMessage -match 'lint-failed') } catch { }
    Check 'hook failure: exit 0 with systemMessage JSON, never blocks' ($hk.Exit -eq 0 -and $okjson) $hk.Out
    $hk = Hook $fx
    $okjson = $false; try { $j = $hk.Out | ConvertFrom-Json; $okjson = ($j.systemMessage -match 'pushed') } catch { }
    Check 'hook success: uploads and reports' ($hk.Exit -eq 0 -and $okjson -and (RemoteSha $fx) -eq (Head $fx)) $hk.Out
    Check 'hook trigger recorded in log' ((Get-Content -Raw (StateFile $fx 'auto-upload.log')) -match '\[hook\]')
    Check 'no decision/block output ever emitted' ($hk.Out -notmatch '"decision"')

    # ---- 17 git operation in progress
    $fx = New-Fixture 't17'
    WriteFile (Join-Path $fx.Auto 'src\app.txt') "during merge`n"
    $gd = (G $fx.Auto @('rev-parse', '--absolute-git-dir')).Trim()
    WriteFile (Join-Path $gd 'MERGE_HEAD') ((Head $fx) + "`n")
    $r = Invoke-AU $fx @('run')
    Remove-Item (Join-Path $gd 'MERGE_HEAD') -Force
    Check 'merge in progress blocks upload' ($r.Exit -eq 1 -and $r.Out -match 'operation-in-progress') $r.Out
}
finally {
    ClearEnv
    Set-Location $env:TEMP
    try { Remove-Item -Recurse -Force $Tmp -ErrorAction Stop } catch { Write-Output ("note: could not remove temp dir " + $Tmp) }
}
Write-Output ''
Write-Output ("RESULT: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { $script:Failures | ForEach-Object { Write-Output ("  failed: " + $_) }; exit 1 }
exit 0
