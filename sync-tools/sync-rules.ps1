<#
.SYNOPSIS
    Flux-Panel Forward Rule Sync Script (Windows PowerShell)
.DESCRIPTION
    Sync all forwarding rules to gost nodes via panel API.
    Use when switching servers or after node reconnection.
.PARAMETER Url
    Panel URL (e.g. https://panel.example.com)
.PARAMETER Token
    API Token from browser LocalStorage
.PARAMETER Username
    Admin username
.PARAMETER Password
    Admin password
.PARAMETER Config
    Config file path
.PARAMETER Timeout
    HTTP timeout in seconds, default 30
.PARAMETER DryRun
    Dry run mode, check only without syncing
.PARAMETER Verbose
    Verbose output
.EXAMPLE
    .\sync-rules.ps1 -Url https://panel.example.com -Token "xxx"
.EXAMPLE
    .\sync-rules.ps1 -Url https://panel.example.com -Username admin -Password pass
.EXAMPLE
    .\sync-rules.ps1 -Config config.ps1
#>

param(
    [string]$Url,
    [string]$Token,
    [string]$Username,
    [string]$Password,
    [string]$Config,
    [int]$Timeout = 30,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$NewConfig
)

$ApiPrefix = "/api/v1"

function Write-Info  { Write-Host "[INFO]  $($args[0])" -ForegroundColor Cyan }
function Write-Ok    { Write-Host "[OK]    $($args[0])" -ForegroundColor Green }
function Write-Warn  { Write-Host "[WARN]  $($args[0])" -ForegroundColor Yellow }
function Write-Err   { Write-Host "[ERROR] $($args[0])" -ForegroundColor Red }
function Write-Dbg   { if ($Verbose) { Write-Host "  [DEBUG] $($args[0])" -ForegroundColor DarkGray } }

function Show-Banner {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   Flux-Panel Forward Rule Sync" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Usage {
    Write-Host "Usage: $($MyInvocation.MyCommand.Path) [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Url [URL]            Panel URL (e.g. https://panel.example.com)"
    Write-Host "  -Token [token]        API Token (mutually exclusive with Username)"
    Write-Host "  -Username [username]  Admin username (mutually exclusive with Token)"
    Write-Host "  -Password [password]  Admin password"
    Write-Host "  -Config [file]        Config file path"
    Write-Host "  -Timeout [seconds]    HTTP timeout (default: 30)"
    Write-Host "  -DryRun               Dry run mode, check only"
    Write-Host "  -Verbose              Verbose output"
    Write-Host ""
    Write-Host "Auth methods (choose one):"
    Write-Host "  1. Token:       -Url URL -Token TOKEN"
    Write-Host "  2. Credential:  -Url URL -Username user -Password pass"
    Write-Host ""
    Write-Host "Config file format (.json):"
    Write-Host '  {'
    Write-Host '    "url": "https://panel.example.com",'
    Write-Host '    "token": "your_token_here"'
    Write-Host '  }'
    Write-Host ""
    Write-Host "Examples:"
    Write-Host '  .\sync-rules.ps1 -Url https://192.168.1.100 -Token eyJxxx...'
    Write-Host '  .\sync-rules.ps1 -Url https://panel.example.com -Username admin -Password pass123'
    Write-Host '  .\sync-rules.ps1 -Config sync-config.json'
    exit 0
}

function Load-ConfigFile {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { Write-Err "Config file not found: $ConfigPath"; exit 1 }
    Write-Info "Loading config: $ConfigPath"
    try {
        $cfg = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        Write-Err "Invalid JSON config: $_"; exit 1
    }
    if ($cfg.url -and -not $Url)      { $script:Url      = $cfg.url }
    if ($cfg.token -and -not $Token)  { $script:Token    = $cfg.token }
    if ($cfg.username -and -not $Username) { $script:Username = $cfg.username }
    if ($cfg.password -and -not $Password) { $script:Password = $cfg.password }
    Write-Info "Config loaded"
}

# 兼容旧版 .ps1 格式配置文件
function Load-OldConfigFile {
    param([string]$ConfigPath)
    Write-Info "Loading legacy config: $ConfigPath"
    $content = Get-Content $ConfigPath -Raw -ErrorAction Stop
    $pattern = '\$(\w+)\s*=\s*"([^"]*)"'
    $matches = [regex]::Matches($content, $pattern)
    foreach ($m in $matches) {
        $n = $m.Groups[1].Value; $v = $m.Groups[2].Value
        switch ($n) {
            'PanelUrl'      { if (-not $Url)      { $script:Url      = $v } }
            'PanelToken'    { if (-not $Token)    { $script:Token    = $v } }
            'PanelUsername' { if (-not $Username) { $script:Username = $v } }
            'PanelPassword' { if (-not $Password) { $script:Password = $v } }
        }
    }
    Write-Info "Legacy config loaded"
}

function Interactive-Input {
    if (-not $Url) { $script:Url = Read-Host "Enter panel URL (e.g. https://panel.example.com)" }
    $script:Url = $script:Url.TrimEnd('/')
}

function Invoke-ApiRequest {
    param([string]$Path, [object]$Body, [switch]$NoAuth)
    $url = "${Url}${ApiPrefix}${Path}"
    $headers = @{ "Content-Type" = "application/json" }
    if (-not $NoAuth -and $script:ApiToken) { $headers["Authorization"] = $script:ApiToken }
    $params = @{ Uri = $url; Method = "POST"; Headers = $headers; ContentType = "application/json"; TimeoutSec = $script:TimeoutSeconds }
    if ($Body) { $params["Body"] = ($Body | ConvertTo-Json -Compress); Write-Dbg "POST $url"; Write-Dbg "Data: $($params["Body"])" }
    else { Write-Dbg "POST $url" }
    try { return Invoke-RestMethod @params -UseBasicParsing }
    catch {
        try { $r = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $b = $r.ReadToEnd(); $r.Close(); return ($b | ConvertFrom-Json) }
        catch { return @{ code = -1; msg = "Request failed: $($_.Exception.Message)" } }
    }
}

function Login {
    if ($script:ApiToken) { Write-Info "Using existing Token"; return $true }
    $body = @{ username = $Username; password = $Password }
    $resp = Invoke-ApiRequest -Path "/user/login" -Body $body -NoAuth
    if ($resp.code -ne 0) { Write-Err "Login failed: $($resp.msg)"; return $false }
    $script:ApiToken = $resp.data.token
    if (-not $script:ApiToken) { Write-Err "No token in response"; return $false }
    Write-Ok "Login OK, user: $($resp.data.name)"
    return $true
}

function Check-Nodes {
    Write-Info "Checking node status..."
    $resp = Invoke-ApiRequest -Path "/node/list"
    if ($resp.code -ne 0) { Write-Warn "Cannot get node list"; return }
    $nodes = $resp.data
    if (-not $nodes -or $nodes.Count -eq 0) { Write-Warn "No nodes configured"; return }
    $online  = @($nodes | Where-Object { $_.status -eq 1 })
    $offline = @($nodes | Where-Object { $_.status -ne 1 })
    Write-Host "  Total nodes: $($nodes.Count)"
    Write-Host "  Online: $($online.Count)" -ForegroundColor Green
    Write-Host "  Offline: $($offline.Count)" -ForegroundColor Red
    if ($online.Count -eq 0 -and $nodes.Count -gt 0) { Write-Warn "All nodes offline, sync may not work" }
}

function Get-Forwards {
    Write-Info "Fetching forward rules..."
    $resp = Invoke-ApiRequest -Path "/forward/list"
    if ($resp.code -ne 0) { Write-Err "Failed to get forwards: $($resp.msg)"; return $null }
    return $resp
}

function Sync-Forwards {
    param([object]$Response)
    $forwards = @($Response.data | Where-Object { $_.status -eq 1 })
    if ($forwards.Count -eq 0) { Write-Warn "No active forwards to sync"; return $true }
    Write-Info "Found $($forwards.Count) active forwards, starting sync..."
    $total = 0; $success = 0; $fail = 0
    foreach ($f in $forwards) {
        $total++
        Write-Info "[$total] Syncing: $($f.name) (ID: $($f.id))"
        if ($DryRun) {
            Write-Host "       tunnel=$($f.tunnelId) port=$($f.inPort) target=$($f.remoteAddr)"
            Write-Warn "       (dry run, skipped)"; continue
        }
        $body = @{ id = $f.id; userId = $f.userId; name = $f.name; tunnelId = $f.tunnelId; remoteAddr = $f.remoteAddr }
        if ($f.strategy) { $body["strategy"] = $f.strategy }
        if ($f.inPort)   { $body["inPort"]   = $f.inPort }
        if ($f.interfaceName) { $body["interfaceName"] = $f.interfaceName }
        $resp = Invoke-ApiRequest -Path "/forward/update" -Body $body
        if ($resp.code -eq 0) { Write-Ok "  OK: $($f.name)"; $success++ }
        else { Write-Err "  FAIL: $($f.name) - $($resp.msg)"; $fail++ }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Done: total=$total success=$success fail=$fail"
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    return ($fail -eq 0)
}

function New-ConfigTemplate {
    $cfg = [Ordered]@{
        url      = "https://your-panel-domain.com"
        token    = "your_token_here"
    }
    $json = $cfg | ConvertTo-Json
    $path = Join-Path $PSScriptRoot "sync-config.json"
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($path, $json, $utf8)
    Write-Ok "Config template created: $path"
}

function Main {
    if ($Config) { Load-ConfigFile -ConfigPath $Config }
    Interactive-Input
    $script:TimeoutSeconds = $Timeout
    $script:ApiToken = $Token
    Write-Info "Panel URL: $Url"
    Write-Info "Timeout: ${Timeout}s"
    if ($DryRun) { Write-Warn "Dry run mode: check only" }
    Write-Host ""
    if (-not (Login)) { exit 1 }
    Write-Host ""
    Check-Nodes
    Write-Host ""
    $fr = Get-Forwards
    if (-not $fr) { exit 1 }
    Write-Host ""
    $r = Sync-Forwards -Response $fr
    if ($r) { Write-Ok "All done!" } else { Write-Warn "Some syncs failed" }
}

# ---- 入口 ----
Show-Banner

# -NewConfig: 只生成配置模板，不执行同步
if ($NewConfig) {
    New-ConfigTemplate
    return
}

Main
