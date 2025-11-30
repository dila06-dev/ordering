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
    A([START Process-AllCsv.ps1]) --> B[Read Script Parameters]
    B --> C[Import OrderImport.Common.psm1]
    C --> D[Run Download-FromSftpAndCleanup.ps1 (SFTP to Local)]
    D --> E[Initialize Log]

    E --> F{CSV Directory Exists?}
    F -- NO --> F_ERR[[ERROR: Directory Missing - EXIT]]
    F -- YES --> G[Collect CSV Files]

    G --> H{Any CSV Files?}
    H -- NO --> H_LOG[[No Files Found - EXIT]]
    H -- YES --> I[[Loop: For Each CSV]]

    I --> J[Log Processing Filename]
    J --> K[Call Send-OrderCsv]
    K --> L{Success?}
    L -- YES --> M[Rename to #filename.csv]
    L -- NO --> N[[Error Logged]]

    M --> O((Next File))
    N --> O
    O --> I

    I --> P[Log All Files Processed]
    P --> Q([END Process-AllCsv.ps1])


    %% CORE ORDER PROCESSING
    subgraph CORE["Send-OrderCsv Core Processing"]
        S1([START Send-OrderCsv]) --> S2[Log Order Context]

        S2 --> S3{CSV Exists?}
        S3 -- NO --> S3_ERR[[Throw: Missing File]]
        S3 -- YES --> S4[Import CSV Rows]

        S4 --> S5{CSV Has Data?}
        S5 -- NO --> S5_ERR[[Throw: CSV Empty]]
        S5 -- YES --> S6[Prepare API URLs and Headers]

        S6 --> S7[Group Rows by Order ID]
        S7 --> S8[[Loop: Each Order]]

        S8 --> S9[Compute OrderId and Timestamps]
        S9 --> S10[Run SELECT Query]

        S10 --> S11{Order Exists?}
        S11 -- YES --> S11_SKIP[[Skip Order]] --> S8
        S11 -- NO --> S12[Insert Header]

        S12 --> S13[[Loop: Insert Lines]]
        S13 --> S14[Insert Line]
        S14 --> S13

        S13 --> S15{Header OK AND Lines OK?}
        S15 -- NO --> S16[[Mark Error - Skip Status]] --> S8
        S15 -- YES --> S17[PATCH Header Status]
        S17 --> S18[PATCH Line Status] --> S8

        S8 --> S19[Log Completion]
        S19 --> S20{Any Errors?}
        S20 -- YES --> S21[[Throw Error]]
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
