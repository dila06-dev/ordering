# Ordering – Automated Order Import Pipeline for IBM i

![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue)
![Build Status](https://img.shields.io/badge/Build-GitHub_Actions-green)
![Documentation](https://img.shields.io/badge/Docs-Available-brightgreen)

A fully automated, production-ready Order Import System designed to process CSV files, download them from SFTP, transform them, and import structured orders into IBM i (AS/400) systems using REST APIs.

This project contains a complete PowerShell processing pipeline, API integration layer, logging system, SFTP automation, and documentation including diagrams.

---

# Project Structure

```
ordering/
│
├── Process-AllCsv.ps1
├── Download-FromSftpAndCleanup.ps1
├── OrderImport.Common.psm1
├── Send-OrderCsv.ps1
│
├── diagrams/
│   └── order_import_flow.svg
│
└── docs/
    └── Process_Description.docx
```

---

# Architecture Diagram (SVG)

```
![Order Import Workflow](diagrams/order_import_flow.svg)
```

---

# 1. Main Process – Process-AllCsv.ps1

## 1.1 Startup & Initialization

Start PROCESS-ALLCSV.ps1

Load Parameters:
- CsvDirectory
- ApiBaseUrl
- BearerToken
- UserInterface
- ChannelId
- LogPath
- RequestDumpDirectory
- TestMode, DryRun

Import module:
```
Import-Module "OrderImport.Common.psm1" -Force
```

---

## 1.2 SFTP Download & Logging

Execute SFTP download:
```
.\Download-FromSftpAndCleanup.ps1
```

Initialize log:
```
Initialize-OrderImportLog -LogPath $LogPath
Write-Log "START: PROCESS_ALLCSV"
```

---

## 1.3 Directory & File Check

Check whether directory exists.  
If missing → log error → exit.

Collect CSV files and ignore those starting with '#'.

If no files → log warning → exit.

---

## 1.4 Processing Loop

For each CSV file:
- Log header
- Determine full path
- Call Send-OrderCsv
- If successful → rename to "#filename.csv"
- On failure → log error, keep original file

End:
```
Write-Log "ALL FILES PROCESSED."
```

---

# 2. Order Processing – Send-OrderCsv

## 2.1 Initialization

Check CSV exists.  
Import rows.  
If empty → throw.  

Prepare API URLs.  
Group rows by order_unique_id.

---

## 2.2 Per-Order Processing

For each order group:

Compute prefixed ID  
Generate timestamps  
Log context  

---

# 3. Existence Check

Build SQL:
```
SELECT * FROM ORDERH WHERE H050='<orderId>'
```

API request:
```
Invoke-ApiJson -Url $QueryUrl -Body @{ query = $query }
```

If exists → skip.

---

# 4. Inserts

## 4.1 Header Insert
Build JSON header, POST → /add.

## 4.2 Line Inserts
Loop through rows, POST → /add.

If any line fails → mark processing as failed.

---

# 5. Status Updates (PATCH)

Only if header and all lines were inserted successfully.

Header PATCH:
```
Invoke-ApiJson -Method PATCH -Body @{ H350=" " }
```

Line PATCH:
```
Invoke-ApiJson -Method PATCH -Body @{ L240=" " }
```

---

# 6. Completion

Log final status.  
Throw if any order failed.

---

# Developer Quickstart

Clone repository:
```
git clone https://github.com/<user>/ordering.git
```

Run pipeline:
```
.\Process-AllCsv.ps1 -CsvDirectory "D:\Wagner\incoming"
```

---

# Contributing

See CONTRIBUTING.md.

---

# Documentation

Details available in:
```
docs/Process_Description.docx
```

---

# Support

If this project helps you, please consider starring the repository.
