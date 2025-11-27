<#
.SYNOPSIS
    Liest Bestelldaten aus einer CSV-Datei und sendet sie als
    HEADER- und LINE-Records per API an IBM i.
    Vorher wird geprüft, ob die Bestellung bereits im ORDERH existiert.
    Wenn ja: nur protokollieren, nichts schreiben.
    Nach erfolgreichem Schreiben werden Status-Felder per UPDATE (PATCH) gesetzt.
    Alle Verarbeitungsschritte werden in eine Logdatei geschrieben.
    Optional Dry-Run (nur Logs & JSON-Dateien, keine API-Calls).
#>

param(
    [string]$CsvPath              = "C:\temp\order.csv",
    [string]$ApiBaseUrl           = "http://localhost:8085/api/ibmi/s105dd7a",
    [string]$BearerToken          = "",
    [string]$UserInterface        = "B2BB2C",            # ersetzt H330 + L160
    [string]$ChannelId            = "00055",             # ersetzt H030 + L250
    [string]$LogPath              = "C:\temp\order_import.log",
    [string]$RequestDumpDirectory = "C:\temp\order_requests",
    [switch]$TestMode,
    [switch]$DryRun
)

# =====================================================================
# LOGGING
# =====================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
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

# Logdatei initialisieren (überschreiben)
try {
    "========== RUN START: $(Get-Date) ==========" | Out-File -FilePath $LogPath -Encoding utf8 -Force
}
catch {
    Write-Error "Konnte Logdatei nicht initialisieren: $LogPath - $_"
}

# Dump-Verzeichnis vorbereiten (falls gesetzt)
if (-not [string]::IsNullOrWhiteSpace($RequestDumpDirectory)) {
    try {
        if (-not (Test-Path $RequestDumpDirectory)) {
            New-Item -Path $RequestDumpDirectory -ItemType Directory -Force | Out-Null
        }
        Write-Log "RequestDumpDirectory: $RequestDumpDirectory" "INFO"
    }
    catch {
        Write-Log "Konnte RequestDumpDirectory nicht anlegen: $RequestDumpDirectory - $_" "ERROR"
    }
}

if ($DryRun) {
    Write-Log "DRY-RUN ist AKTIV – es werden KEINE HTTP-Requests gesendet." "WARN"
}

# =====================================================================
# HILFSFUNKTIONEN
# =====================================================================

function Convert-DateDEToIso {
    param([string]$DateString)
    if ([string]::IsNullOrWhiteSpace($DateString)) {
        return ""
    }
    $dt = [datetime]::ParseExact($DateString, "dd.MM.yyyy", $null)
    return $dt.ToString("yyyy-MM-dd")
}

function Invoke-ApiJson {
    param(
        [string]$Url,
        [Parameter(Mandatory=$true)]
        $Body,                                # kann String ODER Hashtable sein
        [hashtable]$Headers,
        [string]$Context      = "",
        [string]$DumpFileName = "",
        [string]$Method       = "POST"
    )

    if ($Body -is [string]) {
        # JSON ist schon fertig
        $json = $Body
    }
    else {
        # Hashtable/Objekt -> JSON serialisieren
        $json = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    Write-Log "[$Method] $Url Kontext=[$Context]" "DEBUG"
    $preview = if ($json.Length -gt 400) { $json.Substring(0,400) + "..." } else { $json }
    Write-Log "Request-Body (gekürzt): $preview" "DEBUG"

    if (-not [string]::IsNullOrWhiteSpace($RequestDumpDirectory) -and
        -not [string]::IsNullOrWhiteSpace($DumpFileName)) {

        try {
            $safeName = ($DumpFileName -replace '[^a-zA-Z0-9_\.-]', '_')
            $dumpPath = Join-Path $RequestDumpDirectory $safeName
            $json | Out-File -FilePath $dumpPath -Encoding utf8 -Force
            Write-Log "Request-JSON in Datei geschrieben: $dumpPath (Kontext=[$Context])" "DEBUG"
        }
        catch {
            Write-Log "Konnte Request-JSON nicht schreiben: $DumpFileName - $_" "ERROR"
        }
    }

    if ($DryRun) {
        Write-Log "DRY-RUN: Request NICHT gesendet (Kontext=[$Context], Method=$Method)." "INFO"
        return $null
    }

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -Body $json
        Write-Log "Request erfolgreich. Kontext=[$Context], Method=$Method" "INFO"
        return $response
    }
    catch {
        Write-Log "Fehler beim Request. Kontext=[$Context], Method=$Method - $_" "ERROR"
        return $null
    }
}


# =====================================================================
# GRUNDSETUP: CSV, HEADERS, URLs
# =====================================================================

if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV-Datei nicht gefunden: $CsvPath" "ERROR"
    exit 1
}

$rows = Import-Csv -Path $CsvPath -Delimiter ';'

if (-not $rows) {
    Write-Log "Keine Daten in CSV gefunden." "ERROR"
    exit 1
}

$AddUrl    = "$ApiBaseUrl/add"      # Insert
$UpdateUrl = "$ApiBaseUrl/update"   # Status-Update
$QueryUrl  = "$ApiBaseUrl/select"    # SELECT-Endpoint (bei Bedarf anpassen!)

$commonHeaders = @{
    "Content-Type" = "application/json"
}

if (-not [string]::IsNullOrWhiteSpace($BearerToken)) {
    $commonHeaders["Authorization"] = "Bearer $BearerToken"
}

$testModeValue = [bool]$TestMode

Write-Log "Starte Verarbeitung. CSV=$CsvPath, ApiBaseUrl=$ApiBaseUrl, TestMode=$testModeValue, DryRun=$DryRun" "INFO"

# =====================================================================
# VERARBEITUNG: Gruppieren nach order_unique_id (pro Bestellung)
# =====================================================================

$groups = $rows | Group-Object order_unique_id
Write-Log "Anzahl unterschiedlicher Orders (order_unique_id): $($groups.Count)" "INFO"

foreach ($group in $groups) {
    $orderId  = $group.Name
    $firstRow = $group.Group[0]

    # Gemeinsame Timestamps pro Order
    $now            = Get-Date
    $orderTime      = $now.ToString("HH:mm:ss")
    $orderDateStamp = $now.ToString("yyyy-MM-dd")
    $orderFullStamp = $now.ToString("yyyy-MM-dd-HH.mm.ss.ffffff")

    Write-Host ""
    Write-Log "==================================================" "INFO"
    Write-Log "Verarbeite Order: $orderId" "INFO"
    Write-Log "Anzahl Positionen in dieser Order: $($group.Group.Count)" "INFO"
    Write-Log "==================================================" "INFO"

    # -------------------------------------------------
    # 0) EXISTENZ-PRÜFUNG IN ORDERH
    # -------------------------------------------------
    # Variante über Ordernummer (H050):
    $checkQuery = "SELECT * FROM DOMGENT.ORDERH WHERE H050 = '$orderId'"

    $checkBody = @{
        query = $checkQuery
    }

    Write-Log "Prüfe, ob Order bereits existiert (Query: $checkQuery)..." "INFO"
    $checkResult = Invoke-ApiJson `
        -Url $QueryUrl `
        -Body $checkBody `
        -Headers $commonHeaders `
        -Context "CHECK Order=$orderId" `
        -DumpFileName "CHECK_$orderId.json" `
        -Method "POST"

    $orderExists = $false

    if ($checkResult) {
        if ($checkResult.H050 -eq $orderId) {
            $orderExists = $true
        }
    }

    if ($orderExists) {
        Write-Log "Order $orderId existiert bereits in DOMGENT.ORDERH – kein INSERT, nur protokolliert." "WARN"
        continue  # nächste Order
    }

    Write-Log "Order $orderId existiert noch nicht – fahre mit INSERT (HEADER + LINES) fort." "INFO"

    $headerOk   = $false

    $allLinesOk = $true

    # -------------------------------------------------
    # 1) HEADER-REQUEST (ADD) für DOMGENT.ORDERH
    # -------------------------------------------------

    $headerData = @{
        "H010: Order line type, static value" = "H"
        "H020: customer of SC"               = $firstRow.customer_number
        "H030: SC id static"                 = $ChannelId
        "H040: delivery id customer"         = $firstRow.customer_number
        "H050: SC order number"              = $firstRow.order_unique_id
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
        "H310: Message"                      = "06043 4031 – 650"
        "H320: booked"                       = ""
        "H330: user"                         = $UserInterface
        "H340: function"                     = ""
        "H350"                               = "10"             # initialer Status
        "H360"                               = $orderDateStamp
        "H370"                               = $orderFullStamp  # wichtig für UPDATE-Key
    }

    $headerBody = @{
        table    = "DOMGENT.ORDERH"
        testMode = $testModeValue
        data     = @($headerData)
    }

    Write-Log "Sende HEADER (ADD) für Order $orderId..." "INFO"
    $headerResult = Invoke-ApiJson `
        -Url $AddUrl `
        -Body $headerBody `
        -Headers $commonHeaders `
        -Context "HEADER Order=$orderId" `
        -DumpFileName "HEADER_$orderId.json" `
        -Method "POST"

    $headerOk = [bool]$headerResult

    # -------------------------------------------------
    # 2) LINE-REQUESTS (ADD) für jede Zeile DOMGENT.ORDERL
    # -------------------------------------------------

    $lineNumber = 1

    foreach ($row in $group.Group) {

        $lineData = @{
            "L010: Order line type, static value" = "L"
            "L020: EDC order# part 1 (YEAR)"      = "0"
            "L030: EDC order# part 2 (#)"         = "0"
            "L040: SC order#"                     = $row.order_unique_id
            "L050: Line identity on the order"    = $lineNumber
            "L060: Customer Delivery date"        = Convert-DateDEToIso $row.delivery_date
            "L070: Byte 3 Fixed delivery date"    = "0"
            "L080: SKU/article"                   = $row.article_number
            "L090: Part Description document"     = " "
            "L100: Quantity"                      = [int]$row.quantity
            "L110: Customer item reference"       = " "
            "L120: Customer item description"     = " "
            "L130: SC status field (N/U/C)"       = " "
            "L140: Hold / Release"                = " "
            "L150: Message"                       = "For Wagner"
            "L160: booked"                        = $UserInterface
            "L170: function"                      = " "
            "L180"                                = $orderDateStamp
            "L190"                                = $orderFullStamp   # wichtig für UPDATE-Key
            "L200"                                = $orderDateStamp
            "L210: amount"                        = "0"
            "L220: EDC bill# YEAR"                = "0"
            "L230: EDC bill# running#"            = "0"
            "L240"                                = "10"              # initialer Status
            "L250: SC id static"                  = $ChannelId
            "L990: FREE SPACE"                    = " "
        }

        $lineBody = @{
            table    = "DOMGENT.ORDERL"
            testMode = $testModeValue
            data     = $lineData
        }

        Write-Log "Sende LINE (ADD) $lineNumber für Order $orderId (Artikel=$($row.article_number), Menge=$($row.quantity))..." "INFO"

        $lineDumpName = "LINE_${orderId}_$lineNumber.json"

        $lineResult = Invoke-ApiJson `
            -Url $AddUrl `
            -Body $lineBody `
            -Headers $commonHeaders `
            -Context "LINE Order=$orderId Line=$lineNumber" `
            -DumpFileName $lineDumpName `
            -Method "POST"

        if (-not $lineResult) {
            $allLinesOk = $false
            Write-Log "LINE $lineNumber für Order $orderId ist fehlgeschlagen." "ERROR"
        }

        $lineNumber++
    }

    # -------------------------------------------------
    # 3) STATUS-UPDATE nur, wenn HEADER + alle LINEs ok
    # -------------------------------------------------

    if ($headerOk -and $allLinesOk) {
        Write-Log "Alle HEADER + LINEs für Order $orderId erfolgreich. Führe Status-Updates (PATCH) aus..." "INFO"

        # HEADER-Status:
        $headerStatusBody = @{
            table = "DOMGENT.ORDERH"
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

        Write-Log "Sende STATUS-UPDATE (H350) für Order $orderId (per H370=$orderFullStamp)..." "INFO"
        [void](Invoke-ApiJson `
            -Url $UpdateUrl `
            -Body $headerStatusBody `
            -Headers $commonHeaders `
            -Context "STATUS-H350 Order=$orderId" `
            -DumpFileName "STATUS_H350_$orderId.json" `
            -Method "PATCH")

        # LINE-Status:
        $lineStatusBody = @{
            table = "DOMGENT.ORDERL"
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

        Write-Log "Sende STATUS-UPDATE (L240) für Order $orderId (per L190=$orderFullStamp)..." "INFO"
        [void](Invoke-ApiJson `
            -Url $UpdateUrl `
            -Body $lineStatusBody `
            -Headers $commonHeaders `
            -Context "STATUS-L240 Order=$orderId" `
            -DumpFileName "STATUS_L240_$orderId.json" `
            -Method "PATCH")
    }

}

Write-Log "Verarbeitung abgeschlossen. Siehe Logdatei: $LogPath" "INFO"
Write-Log "JSON-Dumps (falls aktiviert) unter: $RequestDumpDirectory" "INFO"
