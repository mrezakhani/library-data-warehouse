# Library Data Warehouse

A complete Data Warehouse solution for library management systems, featuring ETL pipeline development, dimensional modeling, and comprehensive database design documentation.

## Overview

This project demonstrates the full lifecycle of building a Data Warehouse from an OLTP (Online Transaction Processing) system to an OLAP (Online Analytical Processing) solution, including:

- Conceptual and logical database design
- Dimensional modeling with star schema
- ETL (Extract, Transform, Load) pipeline implementation
- Slowly Changing Dimensions (SCD) strategies

## Features

- **Database Design**: Chen ER diagrams, relational models, and normalization analysis
- **Data Warehouse Schema**: Star schema with fact and dimension tables
- **ETL Pipeline**: Python-based extraction, transformation, and loading
- **SCD Implementation**: Handling historical data changes
- **Storage Calculation**: Capacity planning and optimization

## Project Structure

```
├── Database Design
│   ├── 1.2.1 Chen_ER_Diagramm_DE.drawio    # Chen ER diagram
│   ├── 1.2.2 ER_Diagramm_DE.drawio         # Standard ER diagram
│   ├── 1.2.3 Objektbeschreibung_DE.*       # Entity descriptions
│   ├── 1.2.4 Relationenmodell_DE.*         # Relational model
│   ├── 1.2.5 Normalisierungsanalyse.*      # Normalization analysis
│   └── 1.2.6 Speicherberechnungstabelle.*  # Storage calculations
│
├── Data Warehouse Design
│   ├── 1.3 DWH Fragen.*                    # DWH requirements
│   ├── 2.1.1 MER Diagram.drawio            # Multidimensional ER
│   ├── 2.1.2 logisches Schema.drawio       # Logical schema
│   ├── 3.1 Mapping Tabelle.xlsx            # Source-to-target mapping
│   └── 3.2 SCD.*                           # SCD documentation
│
├── Implementation
│   ├── 4.1.1 Business DB---bibliothek_schema_und_daten.sql  # OLTP schema & data
│   ├── 4.1.2 DWH---DWH_Schema.sql          # DWH schema
│   ├── 4.1.3 ETL.py                        # ETL pipeline
│   ├── ETL_Complete.py                     # Complete ETL script
│   └── Quick_Analysis.py                   # Data analysis queries
│
├── Databases
│   ├── bibliothek_oltp.db                  # Source OLTP database
│   └── bibliothek_dwh.db                   # Target DWH database
│
└── Presentation
    └── Bibliothek_DWH_Praesentation.pptx   # Project presentation
```

## Technologies

- **Database**: SQLite
- **ETL**: Python
- **Modeling**: draw.io
- **Documentation**: Microsoft Office (Word, Excel, PowerPoint)

## Getting Started

### Prerequisites

- Python 3.x
- SQLite

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/library-data-warehouse.git
   cd library-data-warehouse
   ```

2. Run the startup script:
   ```bash
   START_PROJEKT.bat
   ```

   Or manually execute the ETL pipeline:
   ```bash
   python ETL_Complete.py
   ```

### Database Setup

To recreate the databases from scratch:

1. Create OLTP database:
   ```bash
   sqlite3 bibliothek_oltp.db < bibliothek_schema_de.sql
   sqlite3 bibliothek_oltp.db < bibliothek_daten_de.sql
   ```

2. Create DWH database:
   ```bash
   sqlite3 bibliothek_dwh.db < DWH_Schema.sql
   ```

3. Run ETL:
   ```bash
   python ETL_Complete.py
   ```

## Data Warehouse Architecture

### Source System (OLTP)
- Library management database with normalized tables
- Handles daily operations: loans, returns, member management

### Target System (OLAP)
- Star schema optimized for analytical queries
- Fact tables for loan transactions
- Dimension tables: Time, Book, Member, Branch

### ETL Process
1. **Extract**: Read data from OLTP source
2. **Transform**: Apply business rules, handle SCD
3. **Load**: Insert into DWH dimensional model

## Documentation

All documentation is provided in German (DE):
- Entity-Relationship diagrams
- Normalization to 3NF
- Storage capacity calculations
- SCD type selection rationale

## License

This project is for educational purposes.

## Author
Mojgan Rezakhani (rezakhani.mojgan@gmail.com)
