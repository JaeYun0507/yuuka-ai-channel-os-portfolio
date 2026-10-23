# auto-upload.ps1 - Stop-hook uploader for the dedicated auto/claude worktree.
# Windows PowerShell 5.1 compatible. Keep this file ASCII-only.
#
# Commands: hook | run | check | status | enable | disable | approve | baseline | help
# See docs/auto-upload.md. This script never merges, rebases, force-pushes or
# touches main. A failed step aborts the run; it never retries by itself.
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [switch]$Yes,
    [int]$Tail = 15
)

$ErrorActionPreference = 'Stop'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Root = (Resolve-Path (Join-Path $script:ScriptDir '..\..')).ProviderPath
$script:Cfg = Get-Content -Raw -Path (Join-Path $script:ScriptDir 'config.json') | ConvertFrom-Json
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:State = $null
$script:Trigger = 'manual'
$script:Deadline = (Get-Date).AddSeconds(600)
$script:StagedByUs = @()

# ---------------------------------------------------------------- run control
function Stop-Run {
    param([string]$Kind, [string]$Code, [string]$Msg)
    $e = New-Object System.Exception("${Code}: $Msg")
    $e.Data['kind'] = $Kind
    $e.Data['code'] = $Code
    $e.Data['msg'] = $Msg
    throw $e
}

function Get-Remaining {
    $s = [int][Math]::Floor(($script:Deadline - (Get-Date)).TotalSeconds)
    if ($s -le 5) { Stop-Run 'failed' 'timeout' 'total run time limit reached' }
    return $s
}

function Limit-Sec([int]$Step) {
    $r = Get-Remaining
    if ($Step -lt $r) { return $Step }
    return $r
}

function Write-Log {
    param([string]$Level, [string]$Msg)
    if (-not $script:State) { return }
    try {
        $log = Join-Path $script:State 'auto-upload.log'
        if ((Test-Path $log) -and ((Get-Item $log).Length -gt 524288)) {
            $keep = Get-Content -Path $log -Tail 200
            [IO.File]::WriteAllLines($log, [string[]]$keep, $script:Utf8)
        }
        $clean = ($Msg -replace '[\r\n]+', ' ')
        if ($clean.Length -gt 400) { $clean = $clean.Substring(0, 400) }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $Level, $script:Trigger, $clean
        [IO.File]::AppendAllText($log, $line + "`r`n", $script:Utf8)
    } catch { }
}

function Set-LastStatus {
    param([string]$Result, [string]$Code, [string]$Msg, [string]$Local, [string]$Remote)
    if (-not $script:State) { return }
    try {
        $o = [ordered]@{
            time = (Get-Date).ToUniversalTime().ToString('o'); trigger = $script:Trigger
            result = $Result; code = $Code; message = $Msg; localSha = $Local; remoteSha = $Remote
        }
        [IO.File]::WriteAllText((Join-Path $script:State 'last-status.json'), ($o | ConvertTo-Json), $script:Utf8)
    } catch { }
}

# ---------------------------------------------------------------- processes
function Quote-Arg([string]$a) {
    if ($a -eq '') { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

function Invoke-Proc {
    param([string]$File, [string[]]$ProcArgs, [int]$TimeoutSec = 60, [string]$Cwd = $script:Root)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (@($ProcArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $psi.WorkingDirectory = $Cwd
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = $script:Utf8
    $psi.StandardErrorEncoding = $script:Utf8
    $psi.EnvironmentVariables['GIT_LITERAL_PATHSPECS'] = '1'
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $p.StandardInput.Close()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
        [void]$p.WaitForExit(5000)
        return [pscustomobject]@{ ExitCode = -1; Out = ''; Err = 'timed out'; TimedOut = $true }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $o.Result; Err = $e.Result; TimedOut = $false }
}

$script:GitExe = (Get-Command git.exe -ErrorAction Stop).Source

function First-Line([string]$t) {
    $l = ($t -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $l) { return '' }
    $l = $l.Trim()
    if ($l.Length -gt 200) { $l = $l.Substring(0, 200) }
    return $l
}

function Get-GitErrorCode([string]$err, [string]$default) {
    if ($err -match 'Authentication failed|could not read Username|Permission denied|returned error: 40[13]|Invalid username') { return 'auth-failed' }
    if ($err -match 'Could not resolve host|Failed to connect|Connection (timed out|refused)|unable to access') { return 'network-error' }
    if ($err -match 'rejected|non-fast-forward|fetch first|failed to push') { return 'push-rejected' }
    return $default
}

function Git {
    param([string[]]$GitArgs, [int]$TimeoutSec = 0, [switch]$AllowFail)
    if ($TimeoutSec -le 0) { $TimeoutSec = [int]$script:Cfg.limits.gitSec }
    $r = Invoke-Proc -File $script:GitExe -ProcArgs (@('-c', 'core.quotepath=false') + $GitArgs) -TimeoutSec (Limit-Sec $TimeoutSec)
    if ($r.TimedOut) { Stop-Run 'failed' 'git-timeout' ("git " + $GitArgs[0] + " timed out") }
    if ($r.ExitCode -ne 0 -and -not $AllowFail) {
        Stop-Run 'failed' (Get-GitErrorCode $r.Err 'git-failed') ("git " + $GitArgs[0] + " failed (exit " + $r.ExitCode + "): " + (First-Line $r.Err))
    }
    return $r
}

function Resolve-Npm {
    $c = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $c) { Stop-Run 'failed' 'npm-missing' 'npm.cmd not found on PATH' }
    return $c.Source
}

# ---------------------------------------------------------------- helpers
function Normalize-Path([string]$p) {
    return ([IO.Path]::GetFullPath($p).TrimEnd('\', '/') -replace '/', '\').ToLowerInvariant()
}

function Normalize-Url([string]$u) {
    return (($u.Trim().ToLowerInvariant() -replace '\\', '/') -replace '/+$', '' -replace '\.git$', '')
}

function Get-FileHashHex([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-StringHashHex([string]$s) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:Utf8.GetBytes($s))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return (Get-Content -Raw -Path $path | ConvertFrom-Json)
}

function Write-JsonFile([string]$path, $obj) {
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 8), $script:Utf8)
}

# ---------------------------------------------------------------- location guard
function Assert-Location {
    param([string]$HookCwd)
    $c = $script:Cfg
    $probe = Invoke-Proc -File $script:GitExe -ProcArgs @('rev-parse', '--path-format=absolute', '--show-toplevel', '--absolute-git-dir', '--git-common-dir') -TimeoutSec 30
    if ($probe.ExitCode -ne 0) { Stop-Run 'failed' 'location-mismatch' 'not inside a git repository' }
    $lines = @($probe.Out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -lt 3) { Stop-Run 'failed' 'location-mismatch' 'unexpected git rev-parse output' }
    $top = Normalize-Path $lines[0]
    $gitDir = $lines[1]
    $common = $lines[2]
    $script:State = Join-Path $gitDir 'auto-upload'
    if (-not (Test-Path $script:State)) { [void](New-Item -ItemType Directory -Path $script:State -Force) }

    if ($top -ne (Normalize-Path $script:Root)) { Stop-Run 'failed' 'location-mismatch' 'script is not at the repository root' }
    if ((Split-Path -Leaf $script:Root) -ne $c.dedicatedFolderName) { Stop-Run 'failed' 'location-mismatch' 'folder name is not the dedicated worktree folder' }
    $mainRoot = Split-Path -Parent $common
    if ((Split-Path -Leaf $mainRoot) -ne $c.mainFolderName) { Stop-Run 'failed' 'location-mismatch' 'main worktree folder name does not match' }
    if ((Normalize-Path (Split-Path -Parent $script:Root)) -ne (Normalize-Path (Split-Path -Parent $mainRoot))) { Stop-Run 'failed' 'location-mismatch' 'worktree is not a sibling of the main worktree' }
    if ((Normalize-Path $gitDir) -eq (Normalize-Path $common)) { Stop-Run 'failed' 'location-mismatch' 'not a linked worktree' }

    $br = Invoke-Proc -File $script:GitExe -ProcArgs @('symbolic-ref', '--short', '-q', 'HEAD') -TimeoutSec 30
    if ($br.Out.Trim() -ne $c.branch) { Stop-Run 'failed' 'location-mismatch' ("branch is not " + $c.branch) }
    $or = Invoke-Proc -File $script:GitExe -ProcArgs @('remote', 'get-url', $c.remote) -TimeoutSec 30
    if ($or.ExitCode -ne 0 -or (Normalize-Url $or.Out) -ne (Normalize-Url $c.expectedOrigin)) { Stop-Run 'failed' 'location-mismatch' 'origin URL does not match the expected repository' }

    if ($HookCwd) {
        $cw = Normalize-Path $HookCwd
        $rt = Normalize-Path $script:Root
        if ($cw -ne $rt -and -not $cw.StartsWith($rt + '\')) { Stop-Run 'failed' 'location-mismatch' 'Claude session cwd is outside the dedicated worktree' }
    }
    return $gitDir
}

function Assert-NoGitOperation([string]$gitDir) {
    foreach ($n in 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'REBASE_HEAD', 'BISECT_LOG', 'rebase-merge', 'rebase-apply', 'sequencer') {
        if (Test-Path (Join-Path $gitDir $n)) { Stop-Run 'failed' 'operation-in-progress' "git operation in progress ($n)" }
    }
}

# ---------------------------------------------------------------- lock
function Enter-Lock {
    $path = Join-Path $script:State 'run.lock'
    for ($i = 0; $i -lt 2; $i++) {
        try {
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $b = [Text.Encoding]::ASCII.GetBytes("$PID " + (Get-Date).ToUniversalTime().ToString('o'))
            $fs.Write($b, 0, $b.Length)
            $fs.Flush()
            return $fs
        } catch [IO.IOException] {
            $stale = $false
            try {
                $txt = (Get-Content -Raw -Path $path -ErrorAction Stop).Trim() -split '\s+'
                $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($txt[1]).ToUniversalTime()).TotalSeconds
                $alive = Get-Process -Id ([int]$txt[0]) -ErrorAction SilentlyContinue
                if (-not $alive -or $age -gt [int]$script:Cfg.limits.lockStaleSec) { $stale = $true }
            } catch { }
            if ($stale) {
                try { Remove-Item -Force -Path $path -ErrorAction Stop; Write-Log 'WARN' 'removed stale lock' } catch { Stop-Run 'skipped' 'locked' 'another run holds the lock' }
                continue
            }
            Stop-Run 'skipped' 'locked' 'another run holds the lock'
        }
    }
    Stop-Run 'skipped' 'locked' 'could not acquire the lock'
}

function Exit-Lock($fs) {
    if ($fs) { try { $fs.Close(); $fs.Dispose() } catch { } }
    try { Remove-Item -Force -Path (Join-Path $script:State 'run.lock') -ErrorAction SilentlyContinue } catch { }
}

# ---------------------------------------------------------------- git state
function Get-StatusItems {
    $r = Git @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--no-renames')
    $items = @()
    foreach ($rec in ($r.Out -split "`0")) {
        if ($rec.Length -lt 4) { continue }
        $items += [pscustomobject]@{ X = [string]$rec[0]; Y = [string]$rec[1]; Path = $rec.Substring(3) }
    }
    return $items
}

function Test-Unmerged($it) {
    return ($it.X -eq 'U' -or $it.Y -eq 'U' -or ($it.X -eq 'A' -and $it.Y -eq 'A') -or ($it.X -eq 'D' -and $it.Y -eq 'D'))
}

function Get-Head { return (Git @('rev-parse', 'HEAD')).Out.Trim() }

function Get-TrackingSha {
    $r = Git @('rev-parse', '--verify', '-q', ("refs/remotes/" + $script:Cfg.remote + "/" + $script:Cfg.branch)) -AllowFail
    if ($r.ExitCode -eq 0) { return $r.Out.Trim() }
    return ''
}

function Get-BaseSha([string]$remoteSha) {
    if ($remoteSha) { return $remoteSha }
    $r = Git @('merge-base', 'HEAD', ("refs/remotes/" + $script:Cfg.remote + "/" + $script:Cfg.baseBranch)) -AllowFail
    if ($r.ExitCode -ne 0) { Stop-Run 'failed' 'no-base' 'cannot determine the base commit (fetch origin/main first)' }
    return $r.Out.Trim()
}

function Get-RemoteSha {
    $r = Git @('ls-remote', '--heads', $script:Cfg.remote, ("refs/heads/" + $script:Cfg.branch))
    $l = $r.Out.Trim()
    if (-not $l) { return '' }
    return ($l -split "\s+")[0]
}

# ---------------------------------------------------------------- file policy
function Get-RepoPathList {
    $r = Git @('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    return @($r.Out -split "`0" | Where-Object { $_ })
}

function Test-ForbiddenName([string]$path) {
    $p = $path -replace '\\', '/'
    foreach ($a in $script:Cfg.allowedNamePatterns) { if ($p -match $a) { return $false } }
    foreach ($f in $script:Cfg.forbiddenNamePatterns) { if ($p -match $f) { return $true } }
    return $false
}

function Get-ProtectedHashes([string[]]$paths) {
    $h = @{}
    foreach ($p in $paths) {
        $hit = $false
        foreach ($pat in $script:Cfg.protectedPatterns) { if ($p -match $pat) { $hit = $true; break } }
        if (-not $hit) { continue }
        $full = Join-Path $script:Root $p
        if (Test-Path -LiteralPath $full) { $h[$p] = Get-FileHashHex $full } else { $h[$p] = 'MISSING' }
    }
    return $h
}

function Get-ApprovedHashes {
    $o = Read-JsonFile (Join-Path $script:State 'approved-hashes.json')
    if (-not $o) { return $null }
    $h = @{}
    foreach ($p in $o.files.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    return $h
}

function Compare-Protected([string[]]$paths) {
    $appr = Get-ApprovedHashes
    if (-not $appr) { Stop-Run 'failed' 'protected-not-approved' 'protected files have not been approved yet (run: approve -Yes after review)' }
    $cur = Get-ProtectedHashes $paths
    $diff = @()
    foreach ($k in (@($cur.Keys) + @($appr.Keys) | Sort-Object -Unique)) {
        $a = ''; $b = ''
        if ($cur.ContainsKey($k)) { $a = $cur[$k] }
        if ($appr.ContainsKey($k)) { $b = $appr[$k] }
        if ($a -ne $b) { $diff += $k }
    }
    return $diff
}

# ---------------------------------------------------------------- secret scan (pattern based)
$script:SecretRules = @(
    @{ N = 'aws-access-key'; R = '\b(AKIA|ASIA)[0-9A-Z]{16}\b' },
    @{ N = 'github-token'; R = '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b' },
    @{ N = 'github-pat'; R = '\bgithub_pat_[A-Za-z0-9_]{40,}' },
    @{ N = 'anthropic-key'; R = '\bsk-ant-[A-Za-z0-9_\-]{20,}' },
    @{ N = 'openai-style-key'; R = '\bsk-(proj-)?[A-Za-z0-9_\-]{32,}' },
    @{ N = 'google-api-key'; R = '\bAIza[0-9A-Za-z_\-]{35}' },
    @{ N = 'slack-token'; R = '\bxox[abprs]-[0-9A-Za-z\-]{10,}' },
    @{ N = 'stripe-live-key'; R = '\b[sr]k_live_[0-9A-Za-z]{16,}' },
    @{ N = 'private-key-block'; R = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' },
    @{ N = 'jwt'; R = '\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}' },
    @{ N = 'url-credentials'; R = '\bhttps?://[^/\s:@]+:[^/\s@]+@' },
    @{ N = 'credential-assignment'; R = '(?i)(api[_-]?key|secret|token|passw(or)?d|client[_-]?secret|private[_-]?key|auth[_-]?key)["'']?\s*[:=]\s*["''][^"''\s]{8,}["'']' }
)

# Returns hit descriptions ("rule @ label:line"); never the matched value.
function Find-SecretHits {
    param([string]$Text, [string]$Label, [bool]$IsLockFile = $false)
    $hits = @()
    $n = 0
    foreach ($line in ($Text -split "`n")) {
        $n++
        if ($IsLockFile -and $line -match '"(integrity|resolved)"\s*:') { continue }
        foreach ($rule in $script:SecretRules) {
            if ([regex]::IsMatch($line, $rule.R)) { $hits += ("{0} @ {1}:{2}" -f $rule.N, $Label, $n) }
        }
        if ($hits.Count -ge 50) { break }
    }
    return $hits
}

function Get-AddedLinesByFile([string]$diffText) {
    $map = @{}
    $cur = $null
    foreach ($line in ($diffText -split "`n")) {
        if ($line -match '^\+\+\+ b/(.+)$') { $cur = $Matches[1]; if (-not $map.ContainsKey($cur)) { $map[$cur] = New-Object System.Text.StringBuilder }; continue }
        if ($line -match '^\+\+\+ /dev/null') { $cur = $null; continue }
        if ($cur -and $line.StartsWith('+') -and -not $line.StartsWith('+++')) { [void]$map[$cur].AppendLine($line.Substring(1)) }
    }
    return $map
}

function Test-DiffForSecrets([string]$diffText) {
    $hits = @()
    $map = Get-AddedLinesByFile $diffText
    foreach ($k in $map.Keys) {
        $hits += Find-SecretHits -Text $map[$k].ToString() -Label $k -IsLockFile ($k -match '(^|/)package-lock\.json$')
    }
    return $hits
}

function Assert-TargetContent([string[]]$paths) {
    $hits = @()
    $allowBin = @($script:Cfg.allowedBinaryExtensions)
    foreach ($p in $paths) {
        $full = Join-Path $script:Root $p
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $len = (Get-Item -LiteralPath $full).Length
        if ($len -gt [int]$script:Cfg.limits.maxScanBytes) { Stop-Run 'failed' 'file-too-large' "file too large to scan: $p" }
        $bytes = [IO.File]::ReadAllBytes($full)
        if ($bytes -contains 0) {
            $ext = [IO.Path]::GetExtension($p).TrimStart('.').ToLowerInvariant()
            if ($allowBin -notcontains $ext) { Stop-Run 'failed' 'binary-not-allowed' "binary file needs manual review: $p" }
            continue
        }
        $hits += Find-SecretHits -Text ($script:Utf8.GetString($bytes)) -Label $p -IsLockFile ($p -match '(^|/)package-lock\.json$')
    }
    return $hits
}

function Assert-NoSecretHits($hits) {
    $hits = @($hits | Where-Object { $_ })
    if ($hits.Count -gt 0) {
        Write-Log 'ERROR' ("secret patterns found: " + ($hits -join '; '))
        Stop-Run 'failed' 'secret-found' ("secret-like content blocked (" + $hits.Count + " hit(s)); first: " + $hits[0])
    }
}

# ---------------------------------------------------------------- npm audit baseline
$script:SevRank = @{ info = 0; low = 1; moderate = 2; high = 3; critical = 4 }

function Get-AuditSummary($obj) {
    $h = @{}
    if (-not $obj.vulnerabilities) { return $h }
    foreach ($p in $obj.vulnerabilities.PSObject.Properties) {
        $v = $p.Value
        $adv = @(); $via = @()
        foreach ($x in @($v.via)) {
            if ($x -is [string]) { $via += $x } else { $adv += [string]$x.source }
        }
        $h[$p.Name] = [ordered]@{
            severity = [string]$v.severity; isDirect = [bool]$v.isDirect
            advisories = @($adv | Sort-Object -Unique); viaPackages = @($via | Sort-Object -Unique)
            effects = @(@($v.effects) | Sort-Object -Unique); nodes = @(@($v.nodes) | Sort-Object -Unique)
        }
    }
    return $h
}

function ConvertTo-AuditMap($pso) {
    $h = @{}
    if (-not $pso) { return $h }
    foreach ($p in $pso.PSObject.Properties) {
        $v = $p.Value
        $h[$p.Name] = @{
            severity = [string]$v.severity; advisories = @($v.advisories); viaPackages = @($v.viaPackages)
            nodes = @($v.nodes)
        }
    }
    return $h
}

function Compare-Audit($current, $baseline) {
    $viol = @()
    foreach ($name in $current.Keys) {
        $c = $current[$name]
        if (-not $baseline.ContainsKey($name)) { $viol += "new vulnerable package: $name ($($c.severity))"; continue }
        $b = $baseline[$name]
        if ($script:SevRank[[string]$c.severity] -gt $script:SevRank[[string]$b.severity]) { $viol += "severity worsened: $name $($b.severity) -> $($c.severity)" }
        foreach ($a in @($c.advisories)) { if (@($b.advisories) -notcontains $a) { $viol += "new advisory on ${name}: $a" } }
        foreach ($a in @($c.viaPackages)) { if (@($b.viaPackages) -notcontains $a) { $viol += "new dependency path on ${name}: via $a" } }
        foreach ($a in @($c.nodes)) { if (@($b.nodes) -notcontains $a) { $viol += "new install path on ${name}: $a" } }
    }
    return $viol
}

function Invoke-NpmAudit {
    $r = Invoke-Proc -File (Resolve-Npm) -ProcArgs @('audit', '--json') -TimeoutSec (Limit-Sec ([int]$script:Cfg.limits.auditSec))
    if ($r.TimedOut) { Stop-Run 'failed' 'audit-failed' 'npm audit timed out' }
    $obj = $null
    try { $obj = $r.Out | ConvertFrom-Json } catch { }
    if (-not $obj) { Stop-Run 'failed' 'audit-failed' ('npm audit returned no parseable JSON (exit ' + $r.ExitCode + ')') }
    if ($obj.error) { Stop-Run 'failed' 'audit-failed' ('npm audit reported an error: ' + [string]$obj.error.code) }
    if (-not $obj.metadata) { Stop-Run 'failed' 'audit-failed' 'npm audit output has no metadata' }
    return $obj
}

function Test-AuditGate {
    param([bool]$Needed)
    if ($script:Cfg.audit.mode -eq 'disabled') { Write-Log 'WARN' 'audit gate disabled by config'; return }
    $lock = Join-Path $script:Root 'package-lock.json'
    $pkg = Join-Path $script:Root 'package.json'
    $key = ''
    if (Test-Path $pkg) { $key += Get-FileHashHex $pkg }
    if (Test-Path $lock) { $key += Get-FileHashHex $lock }
    $cachePath = Join-Path $script:State 'audit-cache.json'
    $cache = Read-JsonFile $cachePath
    if (-not $Needed -and $cache -and $cache.key -eq $key) { Write-Log 'INFO' 'audit: dependency files unchanged since last verified run'; return }
    $baseObj = Read-JsonFile (Join-Path $script:ScriptDir 'security-baseline.json')
    if (-not $baseObj) { Stop-Run 'failed' 'audit-baseline-missing' 'security-baseline.json is missing (run: baseline -Yes)' }
    $cur = Get-AuditSummary (Invoke-NpmAudit)
    $viol = @(Compare-Audit $cur (ConvertTo-AuditMap $baseObj.vulnerabilities))
    if ($viol.Count -gt 0) {
        Write-Log 'ERROR' ('audit worse than baseline: ' + ($viol -join '; '))
        Stop-Run 'failed' 'audit-worse' ('npm audit is worse than the recorded baseline: ' + $viol[0])
    }
    Write-JsonFile $cachePath ([ordered]@{ key = $key; verifiedAt = (Get-Date).ToUniversalTime().ToString('o') })
    Write-Log 'INFO' ('audit: no new or worse findings vs baseline (' + $cur.Count + ' known packages)')
}

# ---------------------------------------------------------------- snapshot
function Get-Snapshot([string[]]$paths) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Get-Head))
    [void]$sb.AppendLine((Git @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--no-renames')).Out)
    foreach ($p in ($paths | Sort-Object)) {
        $full = Join-Path $script:Root $p
        if (Test-Path -LiteralPath $full -PathType Leaf) { [void]$sb.AppendLine($p + ' ' + (Get-FileHashHex $full)) } else { [void]$sb.AppendLine($p + ' MISSING') }
    }
    return Get-StringHashHex $sb.ToString()
}

# ---------------------------------------------------------------- commit helpers
function Get-CommitMessage([string]$kind, [string]$path) {
    $type = 'chore'
    if ($path -match '\.(md|txt)$') { $type = 'docs' }
    $verb = @{ add = 'add'; modify = 'update'; delete = 'remove' }[$kind]
    return "${type}: $verb $path (auto-upload)"
}

# ---------------------------------------------------------------- main pipeline
function Invoke-Upload {
    param([string]$Trigger, [bool]$DryRun = $false, [string]$HookCwd = '')
    $script:Trigger = $Trigger
    $script:Deadline = (Get-Date).AddSeconds([int]$script:Cfg.limits.totalSec)
    $script:StagedByUs = @()
    $lock = $null
    $result = [ordered]@{ result = 'skipped'; code = 'no-changes'; msg = ''; local = ''; remote = ''; quiet = $false }
    try {
        $gitDir = Assert-Location -HookCwd $HookCwd
        $c = $script:Cfg
        if (-not $DryRun -and -not (Test-Path (Join-Path $script:State 'enabled'))) { Stop-Run 'skipped' 'disabled' 'automation is switched off' }

        $items = @(Get-StatusItems)
        $head = Get-Head
        $tracking = Get-TrackingSha
        $baseRef = $tracking
        if (-not $baseRef) { $baseRef = (Git @('rev-parse', '--verify', '-q', ("refs/remotes/" + $c.remote + "/" + $c.baseBranch)) -AllowFail).Out.Trim() }

        $initFlag = Join-Path $script:State 'initialized'
        if (-not (Test-Path $initFlag)) {
            if ($items.Count -gt 0) { Stop-Run 'failed' 'first-run-dirty' 'worktree already has changes on first run; treated as user changes (commit or stash them, then rerun)' }
            if (-not $DryRun) { [IO.File]::WriteAllText($initFlag, (Get-Date).ToUniversalTime().ToString('o'), $script:Utf8) }
        }

        if ($items.Count -eq 0 -and $baseRef -and $head -eq $baseRef) { Stop-Run 'skipped' 'no-changes' 'nothing to upload' }

        $lock = Enter-Lock
        Write-Log 'INFO' ('start (dryRun=' + $DryRun + ')')
        Assert-NoGitOperation $gitDir

        # re-read under lock
        $items = @(Get-StatusItems)
        if (@($items | Where-Object { Test-Unmerged $_ }).Count -gt 0) { Stop-Run 'failed' 'conflict' 'unmerged paths present' }
        $staged = @($items | Where-Object { $_.X -ne ' ' -and $_.X -ne '?' -and $_.X -ne '!' })
        if ($staged.Count -gt 0) { Stop-Run 'failed' 'staged-changes' ('index already has staged changes (' + $staged.Count + '); not mixing with automation') }
        foreach ($it in $items) { if ($it.Y -eq 'T') { Stop-Run 'failed' 'typechange' ('file type change needs manual review: ' + $it.Path) } }

        $allPaths = Get-RepoPathList
        $pdiff = @(Compare-Protected $allPaths)
        if ($pdiff.Count -gt 0) { Stop-Run 'failed' 'protected-changed' ('automation/security files differ from the approved state: ' + ($pdiff -join ', ') + ' (review, then run: approve -Yes)') }

        # remote relationship
        $head = Get-Head
        $remoteSha = Get-RemoteSha
        if ($remoteSha) {
            if ($remoteSha -ne $tracking) { [void](Git @('fetch', $c.remote, $c.branch) -TimeoutSec ([int]$c.limits.pushSec)) }
            $has = Git @('cat-file', '-e', ($remoteSha + '^{commit}')) -AllowFail
            if ($has.ExitCode -ne 0) { Stop-Run 'failed' 'remote-unknown' 'remote branch commit is not available locally' }
            if ($remoteSha -ne $head) {
                $fw = Git @('merge-base', '--is-ancestor', $remoteSha, $head) -AllowFail
                if ($fw.ExitCode -ne 0) {
                    $bw = Git @('merge-base', '--is-ancestor', $head, $remoteSha) -AllowFail
                    if ($bw.ExitCode -eq 0) { Stop-Run 'failed' 'remote-ahead' 'remote auto/claude is ahead of local; no automatic merge or rebase' }
                    Stop-Run 'failed' 'diverged' 'local and remote auto/claude have diverged; no automatic merge or rebase'
                }
            }
        }
        $result.remote = $remoteSha
        $base = Get-BaseSha $remoteSha
        $unpushed = [int](Git @('rev-list', '--count', ($base + '..HEAD'))).Out.Trim()

        # targets
        $targets = @()
        foreach ($it in $items) {
            $kind = 'modify'
            if ($it.X -eq '?' ) { $kind = 'add' } elseif ($it.Y -eq 'D') { $kind = 'delete' } elseif ($it.Y -eq 'A') { $kind = 'add' }
            $targets += [pscustomobject]@{ Path = $it.Path; Kind = $kind }
        }
        $tPaths = @($targets | ForEach-Object { $_.Path })
        if ($targets.Count -eq 0 -and $unpushed -eq 0) { Stop-Run 'skipped' 'no-changes' 'nothing to upload' }
        Write-Log 'INFO' ("targets=" + $targets.Count + " unpushed=" + $unpushed)

        # forbidden files: tracked, changed, and files in the unpushed range
        $names = @($allPaths) + $tPaths
        $rangeDiff = ''
        if ($unpushed -gt 0) {
            $names += @((Git @('diff', '--name-only', '-z', $base, 'HEAD')).Out -split "`0" | Where-Object { $_ })
            $rangeDiff = (Git @('diff', '--unified=0', '--no-color', $base, 'HEAD')).Out
        }
        $bad = @($names | Sort-Object -Unique | Where-Object { Test-ForbiddenName $_ })
        if ($bad.Count -gt 0) { Stop-Run 'failed' 'forbidden-file' ('forbidden file name present: ' + ($bad -join ', ')) }

        # secrets: all changed content + all unpushed commits
        $hits = @()
        $hits += @(Assert-TargetContent $tPaths)
        if ($rangeDiff) { $hits += @(Test-DiffForSecrets $rangeDiff) }
        Assert-NoSecretHits $hits

        # checks
        $snap1 = Get-Snapshot $tPaths
        $npm = Resolve-Npm
        $lint = Invoke-Proc -File $npm -ProcArgs $c.lintCommand -TimeoutSec (Limit-Sec ([int]$c.limits.lintSec))
        if ($lint.TimedOut -or $lint.ExitCode -ne 0) { Stop-Run 'failed' 'lint-failed' ('npm run lint failed (exit ' + $lint.ExitCode + ')') }
        $build = Invoke-Proc -File $npm -ProcArgs $c.buildCommand -TimeoutSec (Limit-Sec ([int]$c.limits.buildSec))
        if ($build.TimedOut -or $build.ExitCode -ne 0) { Stop-Run 'failed' 'build-failed' ('npm run build failed (exit ' + $build.ExitCode + ')') }

        $depTouched = ($tPaths | Where-Object { $_ -match '^package(-lock)?\.json$' }).Count -gt 0
        if (-not $depTouched -and $unpushed -gt 0) {
            $depTouched = (@((Git @('diff', '--name-only', '-z', $base, 'HEAD')).Out -split "`0" | Where-Object { $_ -match '^package(-lock)?\.json$' })).Count -gt 0
        }
        Test-AuditGate -Needed $depTouched

        $snap2 = Get-Snapshot $tPaths
        if ($snap1 -ne $snap2) { Stop-Run 'failed' 'source-changed-during-checks' 'files changed while lint/build ran; nothing was uploaded' }

        if ($DryRun) {
            $result.result = 'success'; $result.code = 'dry-run-ok'
            $result.msg = ('checks passed: ' + $targets.Count + ' changed file(s), ' + $unpushed + ' unpushed commit(s); nothing staged or pushed')
            return [pscustomobject]$result
        }

        # stage and commit file by file (one commit per file)
        $made = 0
        foreach ($t in $targets) {
            $p = $t.Path
            [void](Git @('add', '-A', '--', $p))
            $script:StagedByUs = @($p)
            $cached = @((Git @('diff', '--cached', '--name-only', '-z')).Out -split "`0" | Where-Object { $_ })
            if ($cached.Count -eq 0) { $script:StagedByUs = @(); Write-Log 'INFO' "no staged diff for $p (skipped)"; continue }
            if ($cached.Count -ne 1 -or $cached[0] -ne $p) { Stop-Run 'failed' 'unexpected-staging' ('staged set differs from target: ' + ($cached -join ', ')) }
            Assert-NoSecretHits (Test-DiffForSecrets (Git @('diff', '--cached', '--unified=0', '--no-color')).Out)
            if (Test-ForbiddenName $p) { Stop-Run 'failed' 'forbidden-file' "forbidden file name: $p" }
            [void](Git @('commit', '-q', '-m', (Get-CommitMessage $t.Kind $p)))
            $script:StagedByUs = @()
            $made++
            Write-Log 'INFO' ("committed " + $t.Kind + " " + $p)
        }

        $head = Get-Head
        $unpushed = [int](Git @('rev-list', '--count', ($base + '..HEAD'))).Out.Trim()
        if ($unpushed -eq 0) { Stop-Run 'skipped' 'no-changes' 'nothing to push after staging' }

        $push = Git @('push', $c.remote, ('HEAD:refs/heads/' + $c.branch)) -TimeoutSec ([int]$c.limits.pushSec) -AllowFail
        if ($push.TimedOut -or $push.ExitCode -ne 0) {
            $code = Get-GitErrorCode $push.Err 'push-failed'
            if ($code -eq 'git-failed') { $code = 'push-failed' }
            Stop-Run 'failed' $code ('push failed; commit(s) kept locally and retried on the next run: ' + (First-Line $push.Err))
        }
        $after = Get-RemoteSha
        $result.local = $head; $result.remote = $after
        if ($after -ne $head) { Stop-Run 'failed' 'remote-mismatch' 'remote SHA does not match local SHA after push' }
        $result.result = 'success'; $result.code = 'pushed'
        $result.msg = ('pushed ' + $unpushed + ' commit(s) to ' + $c.branch + ' at ' + $head.Substring(0, 7))
        return [pscustomobject]$result
    } catch {
        $ex = $_.Exception
        if ($ex.Data.Contains('kind')) {
            $result.result = [string]$ex.Data['kind']; $result.code = [string]$ex.Data['code']; $result.msg = [string]$ex.Data['msg']
        } else {
            $result.result = 'failed'; $result.code = 'internal-error'; $result.msg = ([string]$ex.Message)
            if ($result.msg.Length -gt 300) { $result.msg = $result.msg.Substring(0, 300) }
        }
        return [pscustomobject]$result
    } finally {
        if ($script:StagedByUs.Count -gt 0) {
            foreach ($p in $script:StagedByUs) { try { [void](Git @('restore', '--staged', '--', $p) -AllowFail) } catch { } }
            $script:StagedByUs = @()
        }
        Exit-Lock $lock
    }
}

function Complete-Result($r, [bool]$quiet) {
    $script:LastResult = $r
    $level = 'INFO'
    if ($r.result -eq 'failed') { $level = 'ERROR' }
    Write-Log $level ("{0}: {1} - {2}" -f $r.result, $r.code, $r.msg)
    $silent = @('no-changes', 'disabled')
    if ($silent -notcontains $r.code -and $script:State) { Set-LastStatus $r.result $r.code $r.msg $r.local $r.remote }
}

# ---------------------------------------------------------------- commands
function Invoke-Hook {
    $inp = $null
    try {
        if ([Console]::IsInputRedirected) {
            $rd = New-Object IO.StreamReader([Console]::OpenStandardInput(), $script:Utf8)
            $raw = $rd.ReadToEnd()
            if ($raw.Trim()) { $inp = $raw | ConvertFrom-Json }
        }
    } catch { }
    $script:Trigger = 'hook'
    if ($inp -and $inp.stop_hook_active -eq $true) { return }
    $cwd = ''
    if ($inp -and $inp.cwd) { $cwd = [string]$inp.cwd }
    $r = Invoke-Upload -Trigger 'hook' -HookCwd $cwd
    Complete-Result $r $true
    $silent = @('no-changes', 'disabled')
    if ($silent -contains $r.code) { return }
    $msg = "auto-upload: $($r.result) - $($r.code): $($r.msg)"
    Write-Output ((@{ systemMessage = $msg }) | ConvertTo-Json -Compress)
}

function Invoke-RunCommand([bool]$dry) {
    $r = Invoke-Upload -Trigger 'manual' -DryRun $dry
    Complete-Result $r $false
    Write-Output ("[{0}] {1}: {2}" -f $r.result, $r.code, $r.msg)
    if ($r.result -eq 'failed') { exit 1 }
}

function Show-Status {
    $c = $script:Cfg
    Write-Output 'auto-upload status'
    try { [void](Assert-Location); $loc = 'ok' } catch { $loc = 'MISMATCH - ' + $_.Exception.Data['msg'] }
    Write-Output ("  root:        " + $script:Root)
    Write-Output ("  location:    " + $loc)
    if (-not $script:State) { return }
    $en = 'OFF'; if (Test-Path (Join-Path $script:State 'enabled')) { $en = 'ON' }
    Write-Output ("  enabled:     " + $en)
    Write-Output ("  initialized: " + (Test-Path (Join-Path $script:State 'initialized')))
    $appr = Get-ApprovedHashes
    if ($appr) { Write-Output ("  approved:    " + $appr.Count + " protected file(s)") } else { Write-Output '  approved:    NO (run: approve -Yes after review)' }
    try {
        if ($appr) {
            $pd = @(Compare-Protected (Get-RepoPathList))
            if ($pd.Count -gt 0) { Write-Output ("  protected:   CHANGED -> " + ($pd -join ', ')) } else { Write-Output '  protected:   unchanged' }
        }
        $head = Get-Head; $tr = Get-TrackingSha
        Write-Output ("  local HEAD:  " + $head.Substring(0, 7))
        if ($tr) { Write-Output ("  origin ref:  " + $tr.Substring(0, 7) + " (last known)") } else { Write-Output '  origin ref:  none (branch not pushed yet)' }
        $base = Get-BaseSha $tr
        Write-Output ("  unpushed:    " + (Git @('rev-list', '--count', ($base + '..HEAD'))).Out.Trim() + " commit(s)")
        Write-Output ("  worktree:    " + @(Get-StatusItems).Count + " changed path(s)")
    } catch { Write-Output ("  (git state unavailable: " + $_.Exception.Message + ")") }
    $ls = Read-JsonFile (Join-Path $script:State 'last-status.json')
    if ($ls) { Write-Output ("  last result: {0} / {1} @ {2} ({3})" -f $ls.result, $ls.code, $ls.time, $ls.trigger); Write-Output ("               " + $ls.message) } else { Write-Output '  last result: none yet' }
    $log = Join-Path $script:State 'auto-upload.log'
    if (Test-Path $log) { Write-Output ("  log (last $Tail lines): " + $log); Get-Content -Path $log -Tail $Tail | ForEach-Object { Write-Output ("    " + $_) } }
}

function Invoke-Approve {
    [void](Assert-Location)
    $cur = Get-ProtectedHashes (Get-RepoPathList)
    $old = Get-ApprovedHashes
    Write-Output 'Protected files (automation, hook settings, security rules):'
    foreach ($k in ($cur.Keys | Sort-Object)) {
        $mark = 'unchanged'
        if (-not $old -or -not $old.ContainsKey($k)) { $mark = 'NEW' } elseif ($old[$k] -ne $cur[$k]) { $mark = 'CHANGED' }
        Write-Output ("  {0,-10} {1}" -f $mark, $k)
    }
    if ($old) { foreach ($k in $old.Keys) { if (-not $cur.ContainsKey($k)) { Write-Output ("  REMOVED    " + $k) } } }
    if (-not $Yes) { Write-Output 'Review the files above (git diff), then rerun with -Yes to record them as approved.'; return }
    $files = [ordered]@{}
    foreach ($k in ($cur.Keys | Sort-Object)) { $files[$k] = $cur[$k] }
    Write-JsonFile (Join-Path $script:State 'approved-hashes.json') ([ordered]@{ approvedAt = (Get-Date).ToUniversalTime().ToString('o'); files = $files })
    Write-Output ("Approved " + $cur.Count + " protected file(s).")
}

function Invoke-Baseline {
    [void](Assert-Location)
    $sum = Get-AuditSummary (Invoke-NpmAudit)
    $obj = [ordered]@{
        recordedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        note = 'Known, UNRESOLVED npm audit findings. Uploads are blocked on new packages, new advisories, new paths or higher severity. Not a statement that these are harmless.'
        vulnerabilities = [ordered]@{}
    }
    foreach ($k in ($sum.Keys | Sort-Object)) { $obj.vulnerabilities[$k] = $sum[$k] }
    Write-Output ("Audit findings: " + $sum.Count + " package(s)")
    foreach ($k in ($sum.Keys | Sort-Object)) { Write-Output ("  {0} [{1}] advisories={2} via={3}" -f $k, $sum[$k].severity, (@($sum[$k].advisories) -join ','), (@($sum[$k].viaPackages) -join ',')) }
    if (-not $Yes) { Write-Output 'Rerun with -Yes to write security-baseline.json.'; return }
    Write-JsonFile (Join-Path $script:ScriptDir 'security-baseline.json') $obj
    Write-Output 'security-baseline.json written. Review it, then run: approve -Yes'
}

function Invoke-Switch([bool]$on) {
    [void](Assert-Location)
    $f = Join-Path $script:State 'enabled'
    if ($on) {
        [IO.File]::WriteAllText($f, (Get-Date).ToUniversalTime().ToString('o'), $script:Utf8)
        Write-Output 'auto-upload: ON (applies to Claude Code sessions started in this worktree)'
    } else {
        if (Test-Path $f) { Remove-Item -Force $f }
        Write-Output 'auto-upload: OFF'
    }
    Write-Log 'INFO' ('switch ' + $(if ($on) { 'on' } else { 'off' }))
}

function Show-Help {
    Write-Output @'
auto-upload.ps1 <command>
  status     show switch, location checks, last result, unpushed commits, log tail
  enable     turn automation on (state kept outside Git)
  disable    turn automation off
  run        run the full pipeline once now (commit + push to auto/claude)
  check      dry run: all checks, no staging/commit/push
  approve    list protected files; with -Yes record them as reviewed
  baseline   print npm audit findings; with -Yes write security-baseline.json
  hook       Stop-hook entry (reads JSON on stdin; always exits 0)
'@
}

function Invoke-Main {
    try {
        switch ($Command.ToLowerInvariant()) {
            'hook' { try { Invoke-Hook } catch { }; exit 0 }
            'run' { Invoke-RunCommand $false }
            'check' { Invoke-RunCommand $true }
            'status' { Show-Status }
            'enable' { Invoke-Switch $true }
            'disable' { Invoke-Switch $false }
            'approve' { Invoke-Approve }
            'baseline' { Invoke-Baseline }
            default { Show-Help }
        }
    } catch {
        $d = $_.Exception.Data
        if ($d -and $d.Contains('msg')) { Write-Output ("[failed] " + $d['code'] + ": " + $d['msg']) } else { Write-Output ("[failed] " + $_.Exception.Message) }
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
