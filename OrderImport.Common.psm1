# D:\Ordering\OrderImport\OrderImport.Common.psm1
<#
    =====================================================================================
      ORDERIMPORT.COMMON.PS1M
      -----------------------------------------------------------------------------
      Gemeinsames PowerShell-Modul für den Order-Import:

        - Logging (Write-Log, Initialize-OrderImportLog)
        - Hilfsfunktionen (Datums-Konvertierung, API-Wrapper)
        - Hauptfunktion Send-OrderCsv:
          * Liest Orders aus CSV
          * Prüft Existenz in ORDERH
          * Schreibt HEADER (ORDERH) + LINES (ORDERL)
          * Führt Status-Update per PATCH aus

      Parametrisierbare Tabellen:
        - HeaderTable (Standard: TVRELWAECO.ORDERH)
        - LineTable   (Standard: TVRELWAECO.ORDERL)

        - HeaderTable (Test:     DOMGENT.ORDERH)
        - LineTable   (Test:     DOMGENT.ORDERL)

      Autor:    Dimitri Langlitz
      Version:  1.1
      Datum:    11.20.2025
    =====================================================================================
#>

param(
    # Standard-Logpfad, falls Funktionen keinen expliziten Pfad bekommen
    [string]$DefaultLogPath = "D:\Ordering\order_import.log",

    # Standard-Verzeichnis für JSON-Dumps von Requests
    [string]$DefaultRequestDumpDirectory = "D:\Ordering\order_requests"
)

# ==============================================================================
# LOGGING
# ==============================================================================

function Write-Log {
    <#
        .SYNOPSIS
            Schreibt eine Logzeile auf Konsole und in eine Logdatei.

        .PARAMETER Message
            Die Lognachricht.

        .PARAMETER Level
            Log-Level (INFO/WARN/ERROR/DEBUG)

        .PARAMETER LogPath
            Pfad zur Logdatei.
    #>
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO",
        [string]$LogPath = $DefaultLogPath
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"  { Write-Host    $line }
        "WARN"  { Write-Warning $line }
        "ERROR" { Write-Error   $line }
        "DEBUG" { Write-Host    $line }
    }

    try {
        Add-Content -Path $LogPath -Value $line
    }
    catch {
        Write-Error "Konnte nicht in Logdatei schreiben: $LogPath - $_"
    }
}

function Initialize-OrderImportLog {
    <#
        .SYNOPSIS
            Initialisiert die Logdatei für einen neuen Run
            (überschreibt existierende Datei).
    #>
    param(
        [string]$LogPath = $DefaultLogPath
    )

    try {
        "========== RUN START: $(Get-Date) ==========" |
            Out-File -FilePath $LogPath -Encoding utf8 -Force
    }
    catch {
        Write-Error "Konnte Logdatei nicht initialisieren: $LogPath - $_"
    }
}

# ==============================================================================
# HILFSFUNKTIONEN
# ==============================================================================

function Convert-DateDEToIso {
    <#
        .SYNOPSIS
            Wandelt ein Datum im Format dd.MM.yyyy in yyyy-MM-dd um.
    #>
    param(
        [string]$DateString
    )

    if ([string]::IsNullOrWhiteSpace($DateString)) {
        return ""
    }

    $dt = [datetime]::ParseExact($DateString, "dd.MM.yyyy", $null)
    return $dt.ToString("yyyy-MM-dd")
}

function Invoke-ApiJson {
    <#
        .SYNOPSIS
            Sendet einen JSON-Request an eine API (POST/PATCH/etc.).

        .DESCRIPTION
            - Kann Hashtable oder bereits fertigen JSON-String verarbeiten
            - Schreibt optional den JSON-Request ins Dateisystem
            - Unterstützt Dry-Run (kein HTTP-Request, nur Logging/Dump)

        .PARAMETER Url
            Ziel-URL des Requests.

        .PARAMETER Body
            Request-Body (Hashtable/PSObject oder JSON-String).

        .PARAMETER Headers
            HTTP-Header als Hashtable.

        .PARAMETER Context
            Log-Kontext (z. B. "HEADER Order=...").

        .PARAMETER DumpFileName
            Name für JSON-Dump-Datei (optional).

        .PARAMETER Method
            HTTP-Methode (z. B. POST, PATCH).

        .PARAMETER RequestDumpDirectory
            Verzeichnis für JSON-Dumps.

        .PARAMETER DryRun
            Wenn gesetzt, wird kein HTTP-Request gesendet.

        .PARAMETER LogPath
            Pfad zur Logdatei.
    #>
    param(
        [string]$Url,
        [Parameter(Mandatory = $true)]
        $Body,
        [hashtable]$Headers,
        [string]$Context      = "",
        [string]$DumpFileName = "",
        [string]$Method       = "POST",
        [string]$RequestDumpDirectory = $DefaultRequestDumpDirectory,
        [switch]$DryRun,
        [string]$LogPath = $DefaultLogPath
    )

    # Body ggf. in JSON konvertieren
    if ($Body -is [string]) {
        $json = $Body
    }
    else {
        $json = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    Write-Log "[$Method] $Url Kontext=[$Context]" "DEBUG" $LogPath
    $preview = if ($json.Length -gt 400) { $json.Substring(0,400) + "..." } else { $json }
    Write-Log "Request-Body (gekürzt): $preview" "DEBUG" $LogPath

    # JSON-Dump schreiben (falls gewünscht)
    if (-not [string]::IsNullOrWhiteSpace($RequestDumpDirectory) -and
        -not [string]::IsNullOrWhiteSpace($DumpFileName)) {

        try {
            if (-not (Test-Path $RequestDumpDirectory)) {
                New-Item -Path $RequestDumpDirectory -ItemType Directory -Force | Out-Null
            }

            $safeName = ($DumpFileName -replace '[^a-zA-Z0-9_\.-]', '_')
            $dumpPath = Join-Path $RequestDumpDirectory $safeName
            $json | Out-File -FilePath $dumpPath -Encoding utf8 -Force
            Write-Log "Request-JSON in Datei geschrieben: $dumpPath (Kontext=[$Context])" "DEBUG" $LogPath
        }
        catch {
            Write-Log "Konnte Request-JSON nicht schreiben: $DumpFileName - $_" "ERROR" $LogPath
        }
    }

    # Dry-Run → kein HTTP-Request
    if ($DryRun) {
        Write-Log "DRY-RUN: Request NICHT gesendet (Kontext=[$Context], Method=$Method)." "INFO" $LogPath
        return $null
    }

    # Tatsächlicher HTTP-Request
    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -Body $json
        Write-Log "Request erfolgreich. Kontext=[$Context], Method=$Method" "INFO" $LogPath
        return $response
    }
    catch {
        Write-Log "Fehler beim Request. Kontext=[$Context], Method=$Method - $_" "ERROR" $LogPath
        return $null
    }
}

# ==============================================================================
# HAUPTFUNKTION: ENTSPRICH SEND-SCRIPT (PARAMETRISIERTE TABELLEN)
# ==============================================================================

function Send-OrderCsv {
    <#
        .SYNOPSIS
            Verarbeitet eine CSV-Datei mit Orders und sendet HEADER/LINE-Daten an IBM i.

        .DESCRIPTION
            - Gruppiert nach order_unique_id (eine Bestellung = ein HEADER + n LINES)
            - Optionaler Prefix für order_unique_id, bevor sie in IBM i geschrieben wird
            - Prüft per SELECT, ob Order in Header-Tabelle bereits existiert
            - Führt bei Bedarf INSERT in Header- und Line-Tabelle durch
            - Setzt Status-Felder per PATCH, wenn alle Inserts erfolgreich waren

        .PARAMETER CsvPath
            Pfad zur CSV-Datei.

        .PARAMETER ApiBaseUrl
            Basis-URL der API (ohne /add, /update, /select).

        .PARAMETER BearerToken
            Bearer Token für Authorization-Header (optional).

        .PARAMETER UserInterface
            Kennung für USER-Feld (H330/L160).

        .PARAMETER ChannelId
            Channel-ID (H030/L250).

        .PARAMETER LogPath
            Logdatei-Pfad für diese Verarbeitung.

        .PARAMETER RequestDumpDirectory
            Verzeichnis für JSON-Dumps.

        .PARAMETER TestMode
            Wird an API übergeben (testMode = true/false).

        .PARAMETER DryRun
            Kein HTTP-Request, nur Logging und JSON-Dumps.

        .PARAMETER HeaderTable
            Name der Header-Tabelle (z. B. DOMGENT.ORDERH).

        .PARAMETER LineTable
            Name der Line-Tabelle (z. B. DOMGENT.ORDERL).

        .PARAMETER OrderIdPrefix
            Optionaler Prefix, der vor jede order_unique_id gesetzt wird,
            bevor sie in IBM i (H050/L040/SELECT) verwendet wird.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CsvPath,

        [string]$ApiBaseUrl           = "http://localhost:8085/api/ibmi/s105dd7a",
        [string]$BearerToken          = "",
        [string]$UserInterface        = "B2BB2C",
        [string]$ChannelId            = "00055",
        [string]$LogPath              = $DefaultLogPath,
        [string]$RequestDumpDirectory = $DefaultRequestDumpDirectory,
        [switch]$TestMode,
        [switch]$DryRun,

        [string]$HeaderTable          = "DOMGENT.ORDERH",
        [string]$LineTable            = "DOMGENT.ORDERL",

        # NEU: Prefix für Order-IDs
        [string]$OrderIdPrefix        = ""
    )

    # Standardpfade für dieses Run-Kontext setzen
    $script:DefaultLogPath = $LogPath
    $script:DefaultRequestDumpDirectory = $RequestDumpDirectory

    Write-Log "Starte Verarbeitung. CSV=$CsvPath, ApiBaseUrl=$ApiBaseUrl, HeaderTable=$HeaderTable, LineTable=$LineTable, OrderIdPrefix='$OrderIdPrefix', TestMode=$([bool]$TestMode), DryRun=$DryRun" "INFO" $LogPath

    # CSV-Prüfung
    if (-not (Test-Path $CsvPath)) {
        Write-Log "CSV-Datei nicht gefunden: $CsvPath" "ERROR" $LogPath
        throw "CSV-Datei nicht gefunden: $CsvPath"
    }

    $rows = Import-Csv -Path $CsvPath -Delimiter ';'

    if (-not $rows) {
        Write-Log "Keine Daten in CSV gefunden." "ERROR" $LogPath
        throw "Keine Daten in CSV gefunden: $CsvPath"
    }

    # API-URLs
    $AddUrl    = "$ApiBaseUrl/add"
    $UpdateUrl = "$ApiBaseUrl/update"
    $QueryUrl  = "$ApiBaseUrl/select"

    # HTTP-Header
    $commonHeaders = @{
        "Content-Type" = "application/json"
    }

    if (-not [string]::IsNullOrWhiteSpace($BearerToken)) {
        $commonHeaders["Authorization"] = "Bearer $BearerToken"
    }

    $testModeValue = [bool]$TestMode

    # Gruppieren nach Order-ID aus CSV
    $groups = $rows | Group-Object order_unique_id
    Write-Log "Anzahl unterschiedlicher Orders (order_unique_id): $($groups.Count)" "INFO" $LogPath

    $hadErrors = $false

    foreach ($group in $groups) {

        # Original-Wert aus CSV
        $csvOrderId = $group.Name

        # Prefixed-Wert für IBM i
        $orderId = "$OrderIdPrefix$csvOrderId"

        $firstRow = $group.Group[0]

        # Gemeinsame Timestamps
        $now            = Get-Date
        $orderTime      = $now.ToString("HH:mm:ss")
        $orderDateStamp = $now.ToString("yyyy-MM-dd")
        $orderFullStamp = $now.ToString("yyyy-MM-dd-HH.mm.ss.ffffff")

        Write-Host ""
        Write-Log "==================================================" "INFO" $LogPath
        Write-Log "Verarbeite Order (CSV order_unique_id): $csvOrderId" "INFO" $LogPath
        Write-Log "Verwendete Order-ID in IBM i:          $orderId" "INFO" $LogPath
        Write-Log "Anzahl Positionen in dieser Order:     $($group.Group.Count)" "INFO" $LogPath
        Write-Log "HeaderTable: $HeaderTable | LineTable: $LineTable" "DEBUG" $LogPath
        Write-Log "==================================================" "INFO" $LogPath

        # ----------------------------------------------------------------------
        # 0) EXISTENZ-PRÜFUNG in Header-Tabelle über prefixed Order-ID
        # ----------------------------------------------------------------------
        $checkQuery = "SELECT * FROM $HeaderTable WHERE H050 = '$orderId'"

        $checkBody = @{ query = $checkQuery }

        Write-Log "Prüfe, ob Order bereits existiert (Query: $checkQuery)..." "INFO" $LogPath
        $checkResult = Invoke-ApiJson `
            -Url $QueryUrl `
            -Body $checkBody `
            -Headers $commonHeaders `
            -Context "CHECK Order=$orderId" `
            -DumpFileName "CHECK_$orderId.json" `
            -Method "POST" `
            -RequestDumpDirectory $RequestDumpDirectory `
            -DryRun:$DryRun `
            -LogPath $LogPath

        $orderExists = $false
        if ($checkResult) {
            if ($checkResult.H050 -eq $orderId) {
                $orderExists = $true
            }
        }

        if ($orderExists) {
            Write-Log "Order $orderId existiert bereits in $HeaderTable – kein INSERT, nur protokolliert." "WARN" $LogPath
            continue
        }

        Write-Log "Order $orderId existiert noch nicht – fahre mit INSERT (HEADER + LINES) fort." "INFO" $LogPath

        $headerOk   = $false
        $allLinesOk = $true

        # ----------------------------------------------------------------------
        # 1) HEADER-INSERT
        # ----------------------------------------------------------------------
        $headerData = @{
            "H010: Order line type, static value" = "H"
            "H020: customer of SC"               = $firstRow.customer_number
            "H030: SC id static"                 = $ChannelId
            "H040: delivery id customer"         = $firstRow.customer_number
            "H050: SC order number"              = $orderId             # <-- Prefixed ID
            "H060: order creation /change date"  = Convert-DateDEToIso $firstRow.order_date
            "H070: order creation/change time"   = $orderTime
            "H080: SC status field (N/U/C)"      = " "
            "H090: Hold / Release"               = " "
            "H100: Delivery address Name1"       = $firstRow.delivery_company_name1
            "H110: Delivery address Name2"       = $firstRow.delivery_company_name2
            "H120: Delivery address Name3"       = $firstRow.delivery_company_name3
            "H130: Delivery address Street"      = $firstRow.delivery_address
            "H140: Delivery address Country"     = $firstRow.delivery_country
            "H150: Delivery address Zip Code"    = $firstRow.delivery_zip_code
            "H160: Delivery address City"        = $firstRow.delivery_city
            "H170: Head Text 1"                  = ""
            "H180: HEAD (H);FEED(F),LINE(L)"     = ""
            "H190: Head Text 2"                  = ""
            "H200: HEAD (H);FEED(F),LINE(L)"     = ""
            "H210: Head Text 3"                  = ""
            "H220: HEAD (H);FEED(F),LINE(L)"     = ""
            "H230: Shipping Type"                = ""
            "H240: Customer order reference"     = $firstRow.order_number
            "H250: OEM Priority"                 = "0"
            "H260: Full/partial delivery"        = ""
            "H270: SINGLE/BULK INVOICE"          = ""
            "H280: Forwarder text 1"             = ""
            "H290: Forwarder text 2"             = ""
            "H300: Name order responsible SC"    = $firstRow.delivery_email
            "H310: Message"                      = "06043 4031 - 650"
            "H320: booked"                       = ""
            "H330: user"                         = $UserInterface
            "H340: function"                     = ""
            "H350"                               = "10"
            "H360"                               = $orderDateStamp
            "H370"                               = $orderFullStamp
        }

        $headerBody = @{
            table    = $HeaderTable
            testMode = $testModeValue
            data     = @($headerData)
        }

        Write-Log "Sende HEADER (ADD) für Order $orderId in $HeaderTable..." "INFO" $LogPath
        $headerResult = Invoke-ApiJson `
            -Url $AddUrl `
            -Body $headerBody `
            -Headers $commonHeaders `
            -Context "HEADER Order=$orderId" `
            -DumpFileName "HEADER_$orderId.json" `
            -Method "POST" `
            -RequestDumpDirectory $RequestDumpDirectory `
            -DryRun:$DryRun `
            -LogPath $LogPath

        $headerOk = [bool]$headerResult

        # ----------------------------------------------------------------------
        # 2) LINE-INSERTS
        # ----------------------------------------------------------------------
        $lineNumber = 1
        foreach ($row in $group.Group) {

            $lineData = @{
                "L010: Order line type, static value" = "L"
                "L020: EDC order# part 1 (YEAR)"      = "0"
                "L030: EDC order# part 2 (#)"         = "0"
                "L040: SC order#"                     = $orderId          # <-- Prefixed ID
                "L050: Line identity on the order"    = $lineNumber
                "L060: Customer Delivery date"        = Convert-DateDEToIso $row.delivery_date
                "L070: Byte 3 Fixed delivery date"    = "0"
                "L080: SKU/article"                   = $row.article_number
                "L090: Part Description document"     = ""
                "L100: Quantity"                      = [int]$row.quantity
                "L110: Customer item reference"       = ""
                "L120: Customer item description"     = ""
                "L130: SC status field (N/U/C)"       = ""
                "L140: Hold / Release"                = ""
                "L150: Message"                       = ""
                "L160: booked"                        = $UserInterface
                "L170: function"                      = ""
                "L180"                                = $orderDateStamp
                "L190"                                = $orderFullStamp
                "L200"                                = $orderDateStamp
                "L210: amount"                        = "0"
                "L220: EDC bill# YEAR"                = "0"
                "L230: EDC bill# running#"            = "0"
                "L240"                                = "10"
                "L250: SC id static"                  = $ChannelId
                "L990: FREE SPACE"                    = ""
            }

            $lineBody = @{
                table    = $LineTable
                testMode = $testModeValue
                data     = $lineData
            }

            Write-Log "Sende LINE (ADD) $lineNumber für Order $orderId in $LineTable (Artikel=$($row.article_number), Menge=$($row.quantity))..." "INFO" $LogPath

            $lineDumpName = "LINE_${orderId}_$lineNumber.json"

            $lineResult = Invoke-ApiJson `
                -Url $AddUrl `
                -Body $lineBody `
                -Headers $commonHeaders `
                -Context "LINE Order=$orderId Line=$lineNumber" `
                -DumpFileName $lineDumpName `
                -Method "POST" `
                -RequestDumpDirectory $RequestDumpDirectory `
                -DryRun:$DryRun `
                -LogPath $LogPath

            if (-not $lineResult) {
                $allLinesOk = $false
                $hadErrors = $true
                Write-Log "LINE $lineNumber für Order $orderId in $LineTable ist fehlgeschlagen." "ERROR" $LogPath
            }

            $lineNumber++
        }

        # ----------------------------------------------------------------------
        # 3) STATUS-UPDATE (nur wenn HEADER + alle LINES ok)
        # ----------------------------------------------------------------------
        if ($headerOk -and $allLinesOk) {
            Write-Log "Alle HEADER + LINEs für Order $orderId erfolgreich. Führe Status-Updates (PATCH) aus..." "INFO" $LogPath

            # Header-Status
            $headerStatusBody = @{
                table = $HeaderTable
                data  = @{
                    "H350" = " "
                }
                keys  = @{
                    "H370" = @{
                        value    = $orderFullStamp
                        operator = "="
                    }
                }
            }

            Write-Log "Sende STATUS-UPDATE (H350) für Order $orderId in $HeaderTable (per H370=$orderFullStamp)..." "INFO" $LogPath
            [void](Invoke-ApiJson `
                -Url $UpdateUrl `
                -Body $headerStatusBody `
                -Headers $commonHeaders `
                -Context "STATUS-H350 Order=$orderId" `
                -DumpFileName "STATUS_H350_$orderId.json" `
                -Method "PATCH" `
                -RequestDumpDirectory $RequestDumpDirectory `
                -DryRun:$DryRun `
                -LogPath $LogPath)

            # Line-Status
            $lineStatusBody = @{
                table = $LineTable
                data  = @{
                    "L240" = " "
                }
                keys  = @{
                    "L190" = @{
                        value    = $orderFullStamp
                        operator = "="
                    }
                }
            }

            Write-Log "Sende STATUS-UPDATE (L240) für Order $orderId in $LineTable (per L190=$orderFullStamp)..." "INFO" $LogPath
            [void](Invoke-ApiJson `
                -Url $UpdateUrl `
                -Body $lineStatusBody `
                -Headers $commonHeaders `
                -Context "STATUS-L240 Order=$orderId" `
                -DumpFileName "STATUS_L240_$orderId.json" `
                -Method "PATCH" `
                -RequestDumpDirectory $RequestDumpDirectory `
                -DryRun:$DryRun `
                -LogPath $LogPath)
        }
        else {
            $hadErrors = $true
        }
    }

    Write-Log "Verarbeitung abgeschlossen. Siehe Logdatei: $LogPath" "INFO" $LogPath
    Write-Log "JSON-Dumps (falls aktiviert) unter: $RequestDumpDirectory" "INFO" $LogPath

    if ($hadErrors) {
        throw "Fehler bei der Verarbeitung einer oder mehrerer Orders in $CsvPath"
    }
}

