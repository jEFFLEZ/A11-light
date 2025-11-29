function Get-A11LockStatus {
    param()
    $repoRoot = (Resolve-Path -Path $PSScriptRoot).Path
    $localSentinel = Join-Path $repoRoot '..\.no-autostart'
    $systemLock = 'C:\ProgramData\A11\autostart.lock'
    return [pscustomobject]@{
        LocalSentinel = Test-Path $localSentinel
        LocalSentinelPath = $localSentinel
        SystemLock = Test-Path $systemLock
        SystemLockPath = $systemLock
    }
}

function Disable-A11 {
    param(
        [switch]$CreateSystemLock
    )
    $repoRoot = (Resolve-Path -Path $PSScriptRoot).Path
    $localSentinel = Join-Path $repoRoot '..\.no-autostart'

    # Create local sentinel
    try {
        Set-Content -Path $localSentinel -Value 'true' -Encoding UTF8 -Force
    } catch {
        throw "Failed to create local sentinel: $($_.Exception.Message)"
    }

    if ($CreateSystemLock) {
        try {
            $dir = Split-Path -Path 'C:\ProgramData\A11\autostart.lock'
            if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            Set-Content -Path 'C:\ProgramData\A11\autostart.lock' -Value 'true' -Encoding UTF8 -Force
            $user = "$env:USERDOMAIN\$env:USERNAME"
            icacls 'C:\ProgramData\A11\autostart.lock' /inheritance:r | Out-Null
            icacls 'C:\ProgramData\A11\autostart.lock' /grant:r "$user:(R)" | Out-Null
            icacls 'C:\ProgramData\A11\autostart.lock' /remove "Everyone" | Out-Null
        } catch {
            throw "Failed to create system lock: $($_.Exception.Message)"
        }
    }

    return Get-A11LockStatus
}

function Enable-A11 {
    param(
        [switch]$RemoveSystemLock
    )
    $repoRoot = (Resolve-Path -Path $PSScriptRoot).Path
    $localSentinel = Join-Path $repoRoot '..\.no-autostart'

    # Remove local sentinel
    try { Remove-Item -Path $localSentinel -Force -ErrorAction SilentlyContinue } catch { }

    if ($RemoveSystemLock) {
        try { Remove-Item -Path 'C:\ProgramData\A11\autostart.lock' -Force -ErrorAction SilentlyContinue } catch { }
    }

    return Get-A11LockStatus
}

Export-ModuleMember -Function Get-A11LockStatus,Disable-A11,Enable-A11
