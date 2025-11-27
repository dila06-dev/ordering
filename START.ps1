param(
    [string]$CsvDirectory = "D:\Wagner\incomming",
    [string]$ApiBaseUrl = "http://localhost:8085/api/ibmi/s105dd7a",
    [string]$BearerToken = "IOwIAdKxAuBvlqzOgR9rr9wCmtX7SRaaxnfDjeVSd46c7b41",
    [string]$UserInterface = "EASYIMPORT",
    [string]$ChannelId = "00025",
    [string]$LogPath = "D:\Wagner\order_import.log",
    [string]$RequestDumpDirectory = "D:\Wagner\order_requests"
)

# =====================================================================
# LOGGING
# =====================================================================

function Write-MainLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$Level] $Message"

    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

Write-MainLog "START: PROCESS_ALL_CSV.ps1" "INFO"
Write-MainLog "CSV-Verzeichnis: $CsvDirectory" "INFO"

if (-not (Test-Path $CsvDirectory)) {
    Write-MainLog "Verzeichnis existiert nicht: $CsvDirectory" "ERROR"
    exit 1
}

# =====================================================================
# CSV-Dateien sammeln (ohne prefix "#")
# =====================================================================

$csvFiles = Get-ChildItem -Path $CsvDirectory -Filter "*.csv" |
            Where-Object { $_.Name -notlike "#*" }

if ($csvFiles.Count -eq 0) {
    Write-MainLog "Keine zu verarbeitenden CSV-Dateien gefunden." "WARN"
    exit 0
}

Write-MainLog "Gefundene CSV-Dateien: $($csvFiles.Count)" "INFO"

# =====================================================================
# Jede CSV nacheinander verarbeiten
# =====================================================================

foreach ($csv in $csvFiles) {

    Write-MainLog "----------------------------------------------" "INFO"
    Write-MainLog "Verarbeite Datei: $($csv.Name)" "INFO"
    Write-MainLog "----------------------------------------------" "INFO"

    $fullPath = $csv.FullName

    # SEND_ORDER_TREND aufrufen
    $cmd = @(
        ".\SEND_ORDER_TREND.ps1",
        "-CsvPath `"$fullPath`"",
        "-ApiBaseUrl `"$ApiBaseUrl`"",
        "-BearerToken `"$BearerToken`"",
        "-UserInterface `"$UserInterface`"",
        "-ChannelId `"$ChannelId`"",
        "-LogPath `"$LogPath`"",
        "-RequestDumpDirectory `"$RequestDumpDirectory`""
    ) -join " "

    Write-MainLog "Starte: $cmd" "INFO"

    try {
        & powershell -ExecutionPolicy Bypass -NoProfile -Command $cmd
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-MainLog "SUCCESS: Datei erfolgreich verarbeitet." "INFO"

            # Datei umbenennen mit #
            try {
                $newName = "#" + $csv.Name
                Rename-Item -Path $csv.FullName -NewName $newName -Force
                Write-MainLog "Datei umbenannt zu: $newName" "INFO"
            }
            catch {
                Write-MainLog "FEHLER beim Umbenennen: $_" "ERROR"
            }
        }
        else {
            Write-MainLog "FEHLER: SEND_ORDER_TREND.ps1 gab ExitCode $exitCode zurück." "ERROR"
        }
    }
    catch {
        Write-MainLog "EXCEPTION beim Ausführen des Commands: $_" "ERROR"
    }
}

Write-MainLog "ALLE DATEIEN VERARBEITET." "INFO"
