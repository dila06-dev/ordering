# Ordering – Automated Order Import Pipeline for IBM i

![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue)
![Build Status](https://img.shields.io/badge/Build-GitHub_Actions-green)
![Documentation](https://img.shields.io/badge/Docs-Available-brightgreen)

A fully automated, production-ready **Order Import Pipeline** designed for IBM i (AS/400) environments.  
It downloads CSV files from SFTP, processes and validates them, transforms them into structured orders, and imports them using REST APIs.

This repository contains:

- PowerShell automation pipeline  
- IBM i REST API integration  
- Logging & error handling  
- SFTP management  
- Documentation & diagrams  

---

# 📊 Full Order Import Pipeline – High-Level Flow

```mermaid
flowchart LR

    SFTP[SFTP Server]
    IN[CSV Input Folder]
    MAIN[Process-AllCsv.ps1<br>Orchestration]
    CORE[Send-OrderCsv<br>Order Processing]
    API[IBM i REST API Gateway]
    DB[IBM i Order Tables]
    LOG[Logging System]

    SFTP --> IN --> MAIN --> CORE --> API --> DB
    MAIN --> LOG
    CORE --> LOG
```


# 📊 Top-Level-Logik
```mermaid
flowchart TD

    START([Start Process-AllCsv]) --> DIR{CSV Directory Exists?}
    DIR -- NO --> DIR_ERR[Log Error and Exit]
    DIR -- YES --> SCAN[Scan for CSV Files]

    SCAN --> ANY{Any CSV Files?}
    ANY -- NO --> EXIT_NOFILES[Log 'No Files' and Exit]
    ANY -- YES --> LOOP[[Loop: For Each CSV]]

    LOOP --> PROC[Process CSV via Send-OrderCsv]
    PROC --> RESULT{Success?}
    RESULT -- YES --> RENAME[Rename to #filename.csv]
    RESULT -- NO --> LOGERR[Log Error]

    RENAME --> NEXT((Next File))
    LOGERR --> NEXT
    NEXT --> LOOP

    LOOP --> END([End Process-AllCsv])

```

---

# 📁 Project Structure

```
ordering/
├── Process-AllCsv.ps1
├── Download-FromSftpAndCleanup.ps1
├── OrderImport.Common.psm1
├── Send-OrderCsv.ps1
├── diagrams/
│   └── order_import_flow.svg
└── docs/
    └── Process_Description.docx
```

---

# 🧱 Architecture Overview

## Main Script – Process-AllCsv.ps1

Handles parameter loading, SFTP download, logging, file discovery, and calling **Send-OrderCsv**.

## Core Processor – Send-OrderCsv

Validates CSV, groups by order, checks IBM i existence, inserts header + line items, updates statuses.

---

# 🚀 Developer Quickstart

```sh
git clone https://github.com/<user>/ordering.git
```

```powershell
.\Process-AllCsv.ps1 -CsvDirectory "D:\Wagner\incoming"
```

---

# 📘 Documentation

Located in:

```
docs/Process_Description.docx
```

---

# 🤝 Contributing

See `CONTRIBUTING.md`.

---

# ⭐ Support

Star the repository if this project helps you!
