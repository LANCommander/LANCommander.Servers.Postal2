#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Postal 2: Share the Pain is retail software with no public download. Use an existing install in
# /config/Server, or set P2_ARCHIVE_URL to a zip of the Share the Pain folder, e.g. a LANCommander
# archive. The folder holding System/Postal2MP.exe is used, so a full Postal 2 zip (with
# ShareThePain/ inside) works too.

Invoke-Hook "PreInstallPostal2"

$ucc = Join-Path $Env:SERVER_DIR 'System/UCC.exe'

if (Test-Path -Path $ucc) {
    Write-Log "Postal 2 found in $Env:SERVER_DIR"
} elseif ($Env:P2_ARCHIVE_URL) {
    Write-Log "Downloading Postal 2 from $Env:P2_ARCHIVE_URL"

    $zip     = '/tmp/postal2.zip'
    $extract = '/tmp/postal2'

    curl -fL --retry 3 --output $zip "$Env:P2_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:P2_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    # Accept Share the Pain at the zip root or in a subfolder (ShareThePain/ in a Postal 2 zip)
    $root = Get-ChildItem -Path $extract -Filter 'Postal2MP.exe' -Recurse -File -Depth 3 |
        Where-Object { $_.Directory.Name -eq 'System' } |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "System/Postal2MP.exe not found in $Env:P2_ARCHIVE_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root.Parent.FullName '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Postal 2 installed"
} else {
    Write-Log -Level Error "System/UCC.exe not found in $Env:SERVER_DIR. Copy a Postal 2 install there or set P2_ARCHIVE_URL."
}

Invoke-Hook "PostInstallPostal2"

Set-Location $Env:SERVER_ROOT
