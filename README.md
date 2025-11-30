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
flowchart TD

    %% MAIN ORCHESTRATION
    A([START main process]) --> B[Read script parameters]
    B --> C[Import common module]
    C --> D[Download files from SFTP]
    D --> E[Initialize log]

    E --> F{CSV directory exists?}
    F -- NO --> F_ERR[[Error: directory missing, exit]]
    F -- YES --> G[Collect CSV files]

    G --> H{Any CSV files?}
    H -- NO --> H_LOG[[No files found, exit]]
    H -- YES --> I[[Loop: for each CSV file]]

    I --> J[Log current file]
    J --> K[Call Send-OrderCsv]
    K --> L{Success?}
    L -- YES --> M[Rename to #filename.csv]
    L -- NO --> N[[Log error for file]]

    M --> O((Next file))
    N --> O
    O --> I

    I --> P[Log all files processed]
    P --> Q([END main process])


    %% CORE ORDER PROCESSING
    subgraph CORE["Send-OrderCsv core processing"]
        S1([START Send-OrderCsv]) --> S2[Log order context]

        S2 --> S3{CSV file exists?}
        S3 -- NO --> S3_ERR[[Throw: missing file]]
        S3 -- YES --> S4[Import CSV rows]

        S4 --> S5{CSV has data?}
        S5 -- NO --> S5_ERR[[Throw: CSV empty]]
        S5 -- YES --> S6[Prepare API urls and headers]

        S6 --> S7[Group rows by order id]
        S7 --> S8[[Loop: each order]]

        S8 --> S9[Compute order id and timestamps]
        S9 --> S10[Run select query]

        S10 --> S11{Order exists?}
        S11 -- YES --> S11_SKIP[[Skip order]] --> S8
        S11 -- NO --> S12[Insert header]

        S12 --> S13[[Loop: insert lines]]
        S13 --> S14[Insert line]
        S14 --> S13

        S13 --> S15{Header ok and lines ok?}
        S15 -- NO --> S16[[Mark error and skip status update]] --> S8
        S15 -- YES --> S17[Patch header status]
        S17 --> S18[Patch line status] --> S8

        S8 --> S19[Log completion for all orders]
        S19 --> S20{Any errors?}
        S20 -- YES --> S21[[Throw processing error]]
        S20 -- NO --> S22([SUCCESS])
    end
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
