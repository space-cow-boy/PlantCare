$ErrorActionPreference = 'Stop'

$secureKey = Read-Host 'Enter your Kindwise Plant.id API key' -AsSecureString
$keyPointer = [IntPtr]::Zero

try {
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'The API key cannot be empty.'
    }
    if ($apiKey -match '[\r\n]') {
        throw 'The API key must be on one line.'
    }

    $envPath = Join-Path $PSScriptRoot '.env'
    $remainingLines = @()
    if (Test-Path -LiteralPath $envPath) {
        $remainingLines = @(Get-Content -LiteralPath $envPath | Where-Object { $_ -notmatch '^\s*PLANT_ID_API_KEY\s*=' })
    }
    $lines = @($remainingLines) + "PLANT_ID_API_KEY=$apiKey"
    [System.IO.File]::WriteAllLines($envPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host 'Saved the key in server/.env. Keep that file private; it is ignored by Git.'
}
finally {
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
    if ($null -ne $apiKey) {
        $apiKey = $null
    }
}
