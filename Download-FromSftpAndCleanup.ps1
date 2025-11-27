param(
    [string]$SftpHost            = "az16sftp01.blob.core.windows.net",
    [int]   $SftpPort            = 22,

    # Anpassen:
    [string]$SftpUser            = "az16sftp01.wagner.wagner",
    [string]$SftpPassword        = "b/yYZ8BhZjUcbVwv8/QdS6pjGJgc139q",

    # Optional: wenn du mit Key arbeiten willst:
    [string]$SshPrivateKeyPath   = "",  # z.B. "C:\Keys\azure_sftp.ppk"

    # Remote-Verzeichnis auf dem SFTP
    [string]$RemoteDirectory     = "/",

    # Lokales Zielverzeichnis
    [string]$LocalDirectory      = "D:\Wagner\incomming",

    # Logfile
    [string]$LogPath             = "D:\Wagner\sftp_download.log",

    # Pfad zur WinSCP .NET-Assembly
    [string]$WinScpNetDllPath    = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
)

# ==========================================================
# Einfache Logging-Funktion (unabhängig von deinem Modul)
# ==========================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$Level] $Message"

    if ($Level -eq "ERROR") {
        Write-Error $line
    }
    elseif ($Level -eq "WARN") {
        Write-Warning $line
    }
    else {
        Write-Host $line
    }

    try {
        Add-Content -Path $LogPath -Value $line
    }
    catch {
        Write-Warning "Konnte nicht in Logdatei schreiben: $LogPath - $_"
    }
}

# Log initialisieren
try {
    "========== SFTP DOWNLOAD RUN START: $(Get-Date) ==========" |
        Out-File -FilePath $LogPath -Encoding utf8 -Force
}
catch {
    Write-Error "Konnte Logdatei nicht initialisieren: $LogPath - $_"
}

Write-Log "Starte SFTP-Download von {$SftpHost}:$SftpPort ($RemoteDirectory -> $LocalDirectory)" "INFO"

# Lokales Verzeichnis sicherstellen
if (-not (Test-Path $LocalDirectory)) {
    try {
        New-Item -Path $LocalDirectory -ItemType Directory -Force | Out-Null
        Write-Log "Lokales Verzeichnis angelegt: $LocalDirectory" "INFO"
    }
    catch {
        Write-Log "Konnte lokales Verzeichnis nicht anlegen: $LocalDirectory - $_" "ERROR"
        exit 1
    }
}

# ==========================================================
# WinSCP .NET-Assembly laden
# ==========================================================
if (-not (Test-Path $WinScpNetDllPath)) {
    Write-Log "WinSCP .NET Assembly nicht gefunden: $WinScpNetDllPath" "ERROR"
    exit 1
}

try {
    Add-Type -Path $WinScpNetDllPath
}
catch {
    Write-Log "Fehler beim Laden von WinSCP .NET Assembly: $_" "ERROR"
    exit 1
}

# ==========================================================
# SFTP-Session aufbauen
# ==========================================================
$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = $SftpHost
$sessionOptions.PortNumber = $SftpPort
$sessionOptions.UserName = $SftpUser

if ([string]::IsNullOrWhiteSpace($SshPrivateKeyPath)) {
    # Passwort-Login
    $sessionOptions.Password = $SftpPassword
}
else {
    # Key-Login
    $sessionOptions.SshPrivateKeyPath = $SshPrivateKeyPath
    if (-not [string]::IsNullOrWhiteSpace($SftpPassword)) {
        # Falls Key-passphrase oder Passwort zusätzlich
        $sessionOptions.Password = $SftpPassword
    }
}

# Achtung: Für produktiv solltest du hier Fingerprint validieren!
# Für schnellen Start:
$sessionOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true

$session = New-Object WinSCP.Session

try {
    Write-Log "Öffne SFTP-Session..." "INFO"
    $session.Open($sessionOptions)
    Write-Log "SFTP-Session geöffnet." "INFO"

    # ======================================================
    # Dateien herunterladen und nach Erfolg löschen
    # GetFiles(remoteMask, localPath, remove, transferOptions)
    # remove=$true bedeutet: nach erfolgreichem Download vom Server löschen
    # ======================================================
    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    $remoteMask = "$RemoteDirectory/*"

    Write-Log "Starte Download: $remoteMask -> $LocalDirectory (mit anschließendem Löschen auf SFTP bei Erfolg)" "INFO"

    $transferResult = $session.GetFiles($remoteMask, "$LocalDirectory\", $true, $transferOptions)

    # Prüft alle Transfers, wirft Exception, wenn etwas fehlgeschlagen ist
    $transferResult.Check()

    foreach ($transfer in $transferResult.Transfers) {
        Write-Log "Erfolgreich geladen & auf SFTP gelöscht: $($transfer.FileName) -> $($transfer.Destination)" "INFO"
    }

    Write-Log "Alle Dateien erfolgreich heruntergeladen und auf SFTP gelöscht." "INFO"
}
catch {
    Write-Log "Fehler bei SFTP-Download: $_" "ERROR"
    # Session wird unten im finally geschlossen
    exit 1
}
finally {
    if ($session -ne $null) {
        Write-Log "Schließe SFTP-Session..." "DEBUG"
        $session.Dispose()
    }
}

Write-Log "SFTP-Download-Script erfolgreich beendet." "INFO"

exit 0
