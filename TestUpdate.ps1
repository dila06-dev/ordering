# ================================================================
# 1. Testfunktion: Invoke-ApiJson (isoliert)
# ================================================================
function Invoke-ApiJson {
    param(
        [string]$Url,
        [hashtable]$Body,
        [hashtable]$Headers,
        [string]$DumpFileName = "",
        [string]$Method       = "POST"
    )

    $json = $Body | ConvertTo-Json -Depth 10 -Compress

    Write-Host "[DEBUG] Methode: $Method" -ForegroundColor Yellow
    Write-Host "[DEBUG] URL: $Url" -ForegroundColor Yellow
    Write-Host "[DEBUG] JSON (gekürzt): $($json.Substring(0, [Math]::Min(400, $json.Length)))" -ForegroundColor Gray

    if ($DumpFileName) {
        $json | Out-File -FilePath $DumpFileName -Encoding utf8 -Force
        Write-Host "[DEBUG] JSON wurde gespeichert in: $DumpFileName" -ForegroundColor DarkGray
    }

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -Body $json
        Write-Host "[INFO] Request erfolgreich." -ForegroundColor Green
        return $response
    }
    catch {
        Write-Host "[ERROR] Fehler beim Request: $_" -ForegroundColor Red
        return $null
    }
}

# ================================================================
# 2. Header-UPDATE-Body (funktioniert laut deinem Test)
# ================================================================
$headerStatusBody = @{
    table = "DOMGENT.ORDERH"
    data  = @{
        "H350" = " "
    }
    keys  = @{
        "H370" = @{
            value    = "2025-11-19-16.10.50.283868"
            operator = "="
        }
    }
}

# ================================================================
# 3. Auth-Header
# ================================================================
$commonHeaders = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer IOwIAdKxAuBvlqzOgR9rr9wCmtX7SRaaxnfDjeVSd46c7b41"
}

# ================================================================
# 4. Test-Call senden (PATCH)
# ================================================================
Invoke-ApiJson `
    -Url "http://localhost:8085/api/ibmi/s105dd7a/update" `
    -Body $headerStatusBody `
    -Headers $commonHeaders `
    -DumpFileName ".\STATUS_HEADER_TEST.json" `
    -Method "PATCH"
