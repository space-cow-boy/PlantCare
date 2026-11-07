$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$serverDirectory = Join-Path $projectRoot 'server'
$serverUrl = 'http://127.0.0.1:8787'
$serverProcess = $null

$lanAddress = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*' -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' } |
    Select-Object -First 1 -ExpandProperty IPAddress

if (-not $lanAddress) {
    $lanAddress = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
        ForEach-Object { $_.IPv4Address } |
        Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' } |
        Select-Object -First 1 -ExpandProperty IPAddress
}

$appEnv = Join-Path $projectRoot '.env'
$appEnvLines = @()
if (Test-Path -LiteralPath $appEnv) {
    $appEnvLines = @(Get-Content -LiteralPath $appEnv | Where-Object { $_ -notmatch '^\s*EXPO_PUBLIC_API_URL\s*=' })
}
[string]$apiUrl = ''
if ($lanAddress) { $apiUrl = "http://${lanAddress}:8787" }
$appEnvLines += "EXPO_PUBLIC_API_URL=$apiUrl"
[System.IO.File]::WriteAllLines($appEnv, [string[]]$appEnvLines, [System.Text.UTF8Encoding]::new($false))

if (-not $lanAddress) {
    Write-Warning 'No private LAN address was found. The app will run, but photo analysis needs this computer on Wi-Fi.'
} else {
    Write-Host "Phone API URL set to $apiUrl"
    $listener = Get-NetTCPConnection -State Listen -LocalPort 8787 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        $health = Invoke-RestMethod -Uri "$serverUrl/health" -TimeoutSec 3
        if (-not $health.ok) { throw 'Port 8787 is in use by a service that is not the KYARI analysis bridge.' }
    } else {
        $serverProcess = Start-Process -FilePath 'node' -ArgumentList 'index.js' -WorkingDirectory $serverDirectory -WindowStyle Hidden -PassThru
        $health = $null
        for ($attempt = 0; $attempt -lt 10 -and -not $health; $attempt++) {
            Start-Sleep -Milliseconds 500
            try { $health = Invoke-RestMethod -Uri "$serverUrl/health" -TimeoutSec 2 } catch {}
        }
        if (-not $health.ok) {
            Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
            throw 'The KYARI analysis bridge did not start. Check that Node.js is installed.'
        }
    }

    if ($health.aiConfigured) {
        Write-Host 'Plant identification and health checks are configured.'
    } else {
        Write-Warning 'The bridge is running without a Kindwise key. Add one with .\server\set-api-key.ps1; photo analysis will be enabled on the next request.'
    }
}

Write-Host 'Starting Expo Go tunnel. Scan its QR code with Expo Go; keep this window open.'
$previousAndroidHome = $env:ANDROID_HOME
$noEmulatorSdk = Join-Path $env:TEMP "kyari-no-android-sdk-$PID"
try {
    Push-Location $projectRoot
    # Expo 54 starts adb reverse whenever an Android SDK is discoverable, even for phone-only tunnels.
    # This launcher targets Expo Go over the network, so hide the SDK from this process only.
    $env:ANDROID_HOME = $noEmulatorSdk
    & npx.cmd expo start --go --tunnel --port 8082
} finally {
    Pop-Location
    if ($null -eq $previousAndroidHome) {
        Remove-Item Env:ANDROID_HOME -ErrorAction SilentlyContinue
    } else {
        $env:ANDROID_HOME = $previousAndroidHome
    }
    if ($serverProcess -and (Get-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
