param(
    [string]$SftpHost            = "az16sftp01.blob.core.windows.net",
    [int]   $SftpPort            = 22,

    # Zugangsdaten
    [string]$SftpUser            = "az16sftp01.wagner.wagner",
    [string]$SftpPassword        = "",  # optional: direkt per Parameter übergeben

    # Optional: SecureString-Password-Datei (wird verwendet, wenn $SftpPassword leer ist)
    [string]$SftpPasswordFile    = "D:\Ordering\secure\m.sec",

    # Optional: wenn du mit Key arbeiten willst:
    [string]$SshPrivateKeyPath   = "",  # z.B. "C:\Keys\azure_sftp.ppk"

    # Remote-Verzeichnis auf dem SFTP
    [string]$RemoteDirectory     = "/",

    # Lokales Zielverzeichnis
    [string]$LocalDirectory      = "D:\Ordering\incomming",

    # Logfile
    [string]$LogPath             = "D:\Ordering\sftp_download.log",

    # Pfad zur WinSCP .NET-Assembly
    [string]$WinScpNetDllPath    = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
)

# ==========================================================
# Einfache Logging-Funktion
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

# ==========================================================
# Log initialisieren
# ==========================================================
try {
    "========== SFTP DOWNLOAD RUN START: $(Get-Date) ==========" |
        Out-File -FilePath $LogPath -Encoding utf8 -Force
}
catch {
    Write-Error "Konnte Logdatei nicht initialisieren: $LogPath - $_"
}

Write-Log "Starte SFTP-Download von {$SftpHost}:$SftpPort ($RemoteDirectory -> $LocalDirectory)" "INFO"

# ==========================================================
# Lokales Zielverzeichnis sicherstellen
# ==========================================================
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
# SFTP-Passwort laden (aus Datei, falls nicht per Parameter übergeben)
# ==========================================================
if ([string]::IsNullOrWhiteSpace($SftpPassword)) {

    if ([string]::IsNullOrWhiteSpace($SftpPasswordFile)) {
        Write-Log "Weder SftpPassword noch SftpPasswordFile gesetzt." "ERROR"
        exit 1
    }

    if (-not (Test-Path $SftpPasswordFile)) {
        Write-Log "Secure Password File nicht gefunden: $SftpPasswordFile" "ERROR"
        exit 1
    }

    try {
        # Datei enthält den per ConvertFrom-SecureString gespeicherten SecureString
        $securePassword = Get-Content $SftpPasswordFile | ConvertTo-SecureString
        $bstr           = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $SftpPassword   = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        Write-Log "SFTP-Passwort erfolgreich aus Secure-Datei geladen." "DEBUG"
    }
    catch {
        Write-Log "Fehler beim Lesen des SFTP-Passworts aus {$SftpPasswordFile}: $_" "ERROR"
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
$sessionOptions.Protocol   = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName   = $SftpHost
$sessionOptions.PortNumber = $SftpPort
$sessionOptions.UserName   = $SftpUser

if ([string]::IsNullOrWhiteSpace($SshPrivateKeyPath)) {
    # Passwort-Login
    $sessionOptions.Password = $SftpPassword
}
else {
    # Key-Login
    $sessionOptions.SshPrivateKeyPath = $SshPrivateKeyPath

    if (-not [string]::IsNullOrWhiteSpace($SftpPassword)) {
        # Optional: Key-Passphrase oder zusätzliches Passwort
        $sessionOptions.Password = $SftpPassword
    }
}

# Hinweis: Für Produktion solltest du hier den SSH-Fingerprint validieren
# Für schnellen Start:
$sessionOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true

$session = New-Object WinSCP.Session

try {
    Write-Log "Öffne SFTP-Session..." "INFO"
    $session.Open($sessionOptions)
    Write-Log "SFTP-Session geöffnet." "INFO"

    # ======================================================
    # Dateien herunterladen und nach Erfolg löschen
    # ======================================================
    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    $remoteMask = "$RemoteDirectory/*"

    Write-Log "Starte Download: $remoteMask -> $LocalDirectory (mit anschließendem Löschen auf SFTP bei Erfolg)" "INFO"

    # remove = $true  -> löscht Dateien nach erfolgreichem Download vom SFTP
    $transferResult = $session.GetFiles($remoteMask, "$LocalDirectory\", $true, $transferOptions)

    # Wirft Exception, wenn mindestens ein Transfer fehlgeschlagen ist
    $transferResult.Check()

    foreach ($transfer in $transferResult.Transfers) {
        Write-Log "Erfolgreich geladen und auf SFTP gelöscht: $($transfer.FileName) -> $($transfer.Destination)" "INFO"
    }

    Write-Log "Alle Dateien erfolgreich heruntergeladen und auf SFTP gelöscht." "INFO"
}
catch {
    Write-Log "Fehler bei SFTP-Download: $_" "ERROR"
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
