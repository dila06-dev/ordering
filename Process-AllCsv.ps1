<#
    =====================================================================================
      PROCESS-ALLCSV.PS1
      -----------------------------------------------------------------------------
      Haupt-Steuer-Script für den vollständigen Order-Import-Prozess:

      1. Download aller CSV-Dateien vom SFTP-Server
      2. Verarbeitung jeder CSV-Datei durch Send-OrderCsv (Modul OrderImport.Common.psm1)
      3. Umbenennung der erfolgreich verarbeiteten Dateien (#filename.csv)
      4. Logging in zentrale System-Logdatei

      Struktur des OrderImport-Projekts:
        D:\Ordering\OrderImport\
            |-- OrderImport.Common.psm1     → Modul: Logging, Helpers, API-Funktionen
            |-- Process-AllCsv.ps1          → Dieses Script (Main Runner)
            |-- Send-OrderCsv.ps1           → Optionaler Wrapper für Einzeldatei
            |-- Download-FromSftpAndCleanup.ps1 → SFTP Download + Cleanup

      Autor:    Dimitri Langlitz
      Version:  1.0
      Datum:    11.20.2025
    =====================================================================================
#>


param(
    # Ordner mit eingehenden CSV-Dateien
    [string]$CsvDirectory        = "D:\Ordering\incomming",

    # API-Endpunkt-Basis für IBM i
    [string]$ApiBaseUrl          = "http://localhost:8085/api/ibmi/s105dd7a",

    # Bearer Token zur Authentifizierung
    [string]$BearerToken         = "IOwIAdKxAuBvlqzOgR9rr9wCmtX7SRaaxnfDjeVSd46c7b41",

    # Kennung für ORDERH/ORDERL (Interface-Name)
    [string]$UserInterface       = "EASYIMPORT",

    # Kanal-ID (L250/H030)
    [string]$ChannelId           = "00025",

    # Globale Logdatei für den gesamten Importprozess
    [string]$LogPath             = "D:\Ordering\order_import.log",

    # Speicherort für JSON-Dumps aller Requests
    [string]$RequestDumpDirectory= "D:\Ordering\order_requests",

    # TestMode: Insert/Update nur simulieren
    [switch]$TestMode,

    # DryRun: API-Requests werden nicht abgesendet, aber als JSON gespeichert
    [switch]$DryRun
)

#return

# =====================================================================================
# 1) Import des PowerShell-Moduls (Logging, API-Calls, SEND-LOGIK)
# =====================================================================================

Import-Module 'D:\Ordering\OrderImport.Common.psm1' -Force


# =====================================================================================
# 2) Download neuer Dateien vom SFTP-Server
#    (Dieses Script holt alle Dateien und löscht sie nach Erfolg vom SFTP.)
# =====================================================================================

.\Download-FromSftpAndCleanup.ps1


# =====================================================================================
# 3) Logdatei initialisieren
# =====================================================================================

Initialize-OrderImportLog -LogPath $LogPath
Write-Log "START: PROCESS_ALL_CSV.ps1" "INFO" $LogPath
Write-Log "CSV-Verzeichnis: $CsvDirectory" "INFO" $LogPath


# =====================================================================================
# 4) Prüfen, ob das eingestellte CSV-Verzeichnis existiert
# =====================================================================================

if (-not (Test-Path $CsvDirectory)) {
    Write-Log "Verzeichnis existiert nicht: $CsvDirectory" "ERROR" $LogPath
    exit 1
}


# =====================================================================================
# 5) Alle CSV-Dateien sammeln (ohne die bereits verarbeiteten #filename.csv)
# =====================================================================================

$csvFiles = Get-ChildItem -Path $CsvDirectory -Filter "*.csv" |
            Where-Object { $_.Name -notlike "#*" }

if ($csvFiles.Count -eq 0) {
    Write-Log "Keine zu verarbeitenden CSV-Dateien gefunden." "WARN" $LogPath
    exit 0
}

Write-Log "Gefundene CSV-Dateien: $($csvFiles.Count)" "INFO" $LogPath


# =====================================================================================
# 6) Jede CSV-Datei einzeln verarbeiten
# =====================================================================================

foreach ($csv in $csvFiles) {

    Write-Log "----------------------------------------------" "INFO" $LogPath
    Write-Log "Verarbeite Datei: $($csv.Name)" "INFO" $LogPath
    Write-Log "----------------------------------------------" "INFO" $LogPath

    $fullPath = $csv.FullName

    try {
        # -----------------------------------------------------------------------------
        # Übergabe aller relevanten Parameter an die zentrale Verarbeitungsfunktion
        # -----------------------------------------------------------------------------
        Send-OrderCsv `
            -CsvPath $fullPath `
            -ApiBaseUrl $ApiBaseUrl `
            -BearerToken $BearerToken `
            -UserInterface $UserInterface `
            -ChannelId $ChannelId `
            -LogPath $LogPath `
            -RequestDumpDirectory $RequestDumpDirectory `
            -TestMode:$TestMode `
            -DryRun:$DryRun `
            -HeaderTable "TVRELWAECO.ORDERH" `
            -LineTable   "TVRELWAECO.ORDERL" `
            -OrderIdPrefix "WAG-"


        Write-Log "SUCCESS: Datei erfolgreich verarbeitet." "INFO" $LogPath

        # -----------------------------------------------------------------------------
        # 6a) Nach erfolgreicher Verarbeitung: Datei mit Prefix '#' markieren
        #     Dies verhindert erneute Verarbeitung beim nächsten Lauf.
        # -----------------------------------------------------------------------------
        try {
            $newName = "#" + $csv.Name
            Rename-Item -Path $csv.FullName -NewName $newName -Force
            Write-Log "Datei umbenannt zu: $newName" "INFO" $LogPath
        }
        catch {
            Write-Log "FEHLER beim Umbenennen: $_" "ERROR" $LogPath
        }
    }
    catch {
        # -----------------------------------------------------------------------------
        # Fehler in der Verarbeitung der CSV-Datei → Loggen
        # -----------------------------------------------------------------------------
        Write-Log "FEHLER bei Verarbeitung von $($csv.Name): $_" "ERROR" $LogPath
    }
}

# =====================================================================================
# 7) Abschlussmeldung
# =====================================================================================

Write-Log "ALLE DATEIEN VERARBEITET." "INFO" $LogPath
