#Requires -Modules Logging

# Create the server ini (P2_INI, default System/Server.ini) from the game's Default.ini on first
# start, then write the P2_* settings into it. It's created through the merged view, so it lands in
# Overlay/ and can be edited there; keys without a P2_* setting are never touched.

$system   = Join-Path $Env:SERVER_ROOT 'System'
$template = Join-Path $system 'Default.ini'
$ini      = Join-Path $system $Env:P2_INI

if (-not (Test-Path -Path $ini)) {
    if (-not (Test-Path -Path $template)) {
        Write-Log -Level Error "$template not found; skipping server configuration"
        return
    }

    Copy-Item -Path $template -Destination $ini
    Write-Log "Created $ini from Default.ini"
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

function Get-SectionRange([string] $Section) {
    $start = $lines.IndexOf("[$Section]")
    if ($start -lt 0) { return $null }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    return @($start, $end)
}

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $range = Get-SectionRange $Section
    if (-not $range) {
        if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
        return
    }

    $start, $end = $range
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lines[$i] = "$Key=$Value"
            return
        }
    }

    # Insert after the section's last non-blank line
    $at = $end
    while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    $lines.Insert($at, "$Key=$Value")
}

function Get-IniValue([string] $Section, [string] $Key) {
    $range = Get-SectionRange $Section
    if (-not $range) { return $null }

    for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) { return $lines[$i].Substring($Key.Length + 1) }
    }
    return $null
}

# Per-mode rules (GoalScore, TimeLimit) live in the game class's own section
$gameSection = if ($Env:P2_GAME_TYPE) { $Env:P2_GAME_TYPE } else { 'MultiGame.xDeathMatch' }

$settings = @(
    @('URL',                         'Port',          $Env:P2_PORT),
    @('Engine.GameReplicationInfo',  'ServerName',    $Env:P2_SERVER_NAME),
    @('Engine.GameReplicationInfo',  'ShortName',     $Env:P2_SHORT_NAME),
    @('Engine.GameReplicationInfo',  'AdminName',     $Env:P2_ADMIN_NAME),
    @('Engine.GameReplicationInfo',  'AdminEmail',    $Env:P2_ADMIN_EMAIL),
    @('Engine.GameReplicationInfo',  'MOTDLine1',     $Env:P2_MOTD),
    @('Engine.GameInfo',             'MaxPlayers',    $Env:P2_MAX_PLAYERS),
    @('Engine.AccessControl',        'GamePassword',  $Env:P2_GAME_PASSWORD),
    @('MultiBase.MPGameInfo',        'MinPlayers',    $Env:P2_MIN_PLAYERS),
    @('MultiBase.MPGameInfo',        'BotDifficulty', $Env:P2_BOT_DIFFICULTY),
    @($gameSection,                  'GoalScore',     $Env:P2_GOAL_SCORE),
    @($gameSection,                  'TimeLimit',     $Env:P2_TIME_LIMIT)
)

foreach ($s in $settings) {
    if ($s[2]) { Set-IniValue $s[0] $s[1] $s[2] }
}

# Map rotation. Each game class has its own map list section.
$mapLists = @{
    'MultiGame.xDeathMatch' = 'MultiGame.DMMapList'
    'MultiGame.xTeamGame'   = 'MultiGame.TDMMapList'
    'MultiGame.xCTFGame'    = 'MultiGame.CTFMapList'
    'MultiGame.xGrabBag'    = 'MultiGame.GBMapList'
}
$mapsDir = Join-Path $Env:SERVER_ROOT 'Maps'
$available = @{}
Get-ChildItem -Path $mapsDir -Filter '*.fuk' -File -ErrorAction SilentlyContinue |
    ForEach-Object { $available[$_.Name.ToLowerInvariant()] = $true }

function Get-MapFile([string] $Map) {
    if ($Map -notmatch '\.fuk$') { $Map = "$Map.fuk" }
    return $Map
}

foreach ($listSection in $mapLists.Values) {
    if (-not (Get-SectionRange $listSection)) { continue }

    $maps = @()
    for ($i = 0; $i -lt 32; $i++) {
        $m = Get-IniValue $listSection "Maps[$i]"
        if ($m) { $maps += $m }
    }

    if ($listSection -eq $mapLists[$gameSection] -and $Env:P2_MAPS) {
        $maps = @($Env:P2_MAPS -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { Get-MapFile $_ })
    }

    # The stock lists name maps that aren't in every release (e.g. mpDGT-SportingWood); a missing
    # map in the rotation stops the server at the end of a round
    if ($available.Count) {
        $missing = @($maps | Where-Object { -not $available.ContainsKey($_.ToLowerInvariant()) })
        if ($missing) {
            Write-Log "Removed missing map(s) from [$listSection]: $($missing -join ', ')"
            $maps = @($maps | Where-Object { $available.ContainsKey($_.ToLowerInvariant()) })
        }
    }

    for ($i = 0; $i -lt 32; $i++) {
        Set-IniValue $listSection "Maps[$i]" $(if ($i -lt $maps.Count) { $maps[$i] } else { '' })
    }
}

# GameSpy is gone. The stock uplink points at 333networks, a replacement master server; it's
# dropped by default for LAN servers.
if ($Env:P2_MASTER_SERVER_UPLINK -notin @('true', '1', 'yes')) {
    $removed = $lines.RemoveAll({ param($l) $l -like 'ServerActors=IpDrv.UdpServerUplink*' })
    if ($removed) { Write-Log "Removed $removed master server uplink(s) from $Env:P2_INI" }
    Set-IniValue 'IpDrv.UdpServerUplink' 'DoUplink' 'False'
}

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied P2_* settings to $ini"
