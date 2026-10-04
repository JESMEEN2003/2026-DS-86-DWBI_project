# Northwind DW/BI — Complete ETL Process & Pipeline Documentation
## IT3101: Data Warehousing & Business Intelligence | Project ID: 2026-DS-86

This document provides a comprehensive technical walkthrough of the **Extract, Transform, and Load (ETL)** pipeline developed for the Northwind Enterprise Data Warehouse (`Northwind_DW`). It details the source extraction methods, data staging architecture, transformation and derivation algorithms, loading sequence, and validation audit queries implemented in **Microsoft SQL Server (SSMS)**.

---

## 1. Architectural Overview

The analytical data platform employs an enterprise **ELT (Extract-Load-Transform)** architecture to integrate disparate operational systems into a high-performance Kimball Star Schema:

```
[Operational Sources]
  ├── Relational DB (SQLite): orders, order_details
  ├── Delimited Flat Files (CSV): products, categories, suppliers
  └── Hierarchical Documents (JSON): customers, employees, shippers
          │
          ▼ (Extract & Ingestion)
[Staging Area: Northwind_Staging]
  ├── stg_orders (830 rows)
  ├── stg_order_details (2,155 rows)
  ├── stg_products (77 rows)
  ├── stg_categories (8 rows)
  ├── stg_suppliers (29 rows)
  ├── stg_customers (91 rows)
  ├── stg_employees (9 rows)
  └── stg_shippers (6 rows)
          │
          ▼ (SQL Server Transformation Pipeline: Script 03)
[Enterprise Data Warehouse: Northwind_DW]
  ├── Dim_Date (1,462 rows — continuous calendar 1996-1999 + sentinel)
  ├── Dim_Customer (91 rows — cleansed & imputed)
  ├── Dim_Product (77 rows — category denormalized)
  ├── Dim_Employee (9 rows — unified naming & role)
  ├── Dim_Shipper (6 rows — 3PL carriers)
  └── Fact_Orders (2,155 rows — atomic line-item grain)
          │
          ▼ (Departmental Views: Script 05)
[Departmental Data Marts]
  ├── vw_Logistics_SLA_Performance (Carrier transit, SLA breach tracking)
  └── vw_Sales_Margin_Leakage (Discretionary discounting & salesperson margins)
          │
          ▼
[Presentation Layer: Microsoft Power BI]
  └── Interactive OLAP Dashboards, Slicers, DAX KPI Cards
```

---

## 2. Extract Phase: Multi-Source Ingestion

To reflect realistic enterprise data heterogeneity, data was extracted from three distinct physical source types into the staging database `Northwind_Staging`:

### 2.1 Extraction Inventory & Mapping Table
*(Referenced in Report: Page 6, Table 3.1 & Page 13, Table 5.1)*

| Operational Entity | Source Format | Source Storage Path | Connector / Protocol | Target Staging Table | Rows Extracted | Key Extraction Attributes |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **orders** | Relational DB | `northwind_sources/northwind_oltp.db` | Python `sqlite3` + `SQLAlchemy` | `stg_orders` | **830** | `order_id`, `customer_id`, `employee_id`, `order_date`, `required_date`, `shipped_date`, `ship_via`, `freight`, `ship_name`, `ship_city`, `ship_country` |
| **order_details** | Relational DB | `northwind_sources/northwind_oltp.db` | Python `sqlite3` + `SQLAlchemy` | `stg_order_details` | **2,155** | `order_id`, `product_id`, `unit_price`, `quantity`, `discount` |
| **products** | Delimited CSV | `northwind_sources/products.csv` | Python `pandas.read_csv()` | `stg_products` | **77** | `product_id`, `product_name`, `supplier_id`, `category_id`, `quantity_per_unit`, `unit_price`, `units_in_stock`, `units_on_order`, `reorder_level`, `discontinued` |
| **categories** | Delimited CSV | `northwind_sources/categories.csv` | Python `pandas.read_csv()` | `stg_categories` | **8** | `category_id`, `category_name`, `description` |
| **suppliers** | Delimited CSV | `northwind_sources/suppliers.csv` | Python `pandas.read_csv()` | `stg_suppliers` | **29** | `supplier_id`, `company_name`, `contact_name`, `contact_title`, `city`, `country`, `phone` |
| **customers** | Hierarchical JSON | `northwind_sources/customers.json` | Python `json.load()` + DataFrame | `stg_customers` | **91** | `customer_id`, `company_name`, `contact_name`, `contact_title`, `address`, `city`, `region`, `postal_code`, `country`, `phone` |
| **employees** | Hierarchical JSON | `northwind_sources/employees.json` | Python `json.load()` + Filter | `stg_employees` | **9** | `employee_id`, `first_name`, `last_name`, `title`, `birth_date`, `hire_date`, `city`, `country`, `reports_to` |
| **shippers** | Hierarchical JSON | `northwind_sources/shippers.json` | Python `json.load()` + DataFrame | `stg_shippers` | **6** | `shipper_id`, `company_name`, `phone` |

### 2.2 Staging Verification Query
Run **`01_staging_verification.sql`** in SSMS to verify the raw extraction count:
```sql
USE Northwind_Staging;
GO

SELECT 'stg_orders' AS TableName, COUNT(*) AS TotalRows, 830 AS ExpectedRows FROM stg_orders
UNION ALL SELECT 'stg_order_details', COUNT(*), 2155 FROM stg_order_details
UNION ALL SELECT 'stg_products', COUNT(*), 77 FROM stg_products
UNION ALL SELECT 'stg_categories', COUNT(*), 8 FROM stg_categories
UNION ALL SELECT 'stg_suppliers', COUNT(*), 29 FROM stg_suppliers
UNION ALL SELECT 'stg_customers', COUNT(*), 91 FROM stg_customers
UNION ALL SELECT 'stg_employees', COUNT(*), 9 FROM stg_employees
UNION ALL SELECT 'stg_shippers', COUNT(*), 6 FROM stg_shippers;
```
**Outcome:** All 8 staging tables report identical actual and expected row counts with 0 record loss.

---

## 3. Transform Phase: Cleansing, Imputation & Derivations

The transformation phase cleanses raw operational anomalies, resolves surrogate keys, and derives high-value analytical measures directly in SQL Server.

### 3.1 Missing Value Imputation
*(Referenced in Report: Page 14, Test 1)*

1. **Unshipped Warehouse Orders (Sentinel Date Key):**
   - **Problem:** 21 parent orders (representing **73 individual atomic line items** in `order_details`) have `shipped_date IS NULL` because they are pending warehouse dispatch.
   - **Solution:** Rather than dropping these rows (which would lose revenue) or violating foreign key integrity with a NULL foreign key, unshipped orders are assigned a sentinel key:
     ```sql
     CASE 
         WHEN o.shipped_date IS NULL OR TRIM(o.shipped_date) = '' OR TRIM(o.shipped_date) = 'None' 
         THEN -1
         ELSE CAST(CONVERT(VARCHAR(8), CAST(o.shipped_date AS DATE), 112) AS INT)
     END AS shipped_date_key
     ```
   - In `Dim_Date`, record `-1` maps to `'1900-01-01'` with description `'Unknown / Unshipped'`.
   - The operational compliance flag is set to `is_shipped = 0`, and duration `shipping_lead_time_days = NULL`.

2. **Customer Geographic Regions (Hierarchy Continuity):**
   - **Problem:** 60 of the 91 corporate client profiles in `customers.json` have NULL or empty `region` strings. In OLAP cubes and Power BI hierarchies (`Country -> Region -> City`), NULL values produce unclickable broken nodes.
   - **Solution:** Imputed with the standard string `'Not Specified'`:
     ```sql
     CASE 
         WHEN region IS NULL OR TRIM(region) = '' OR TRIM(region) = 'None' 
         THEN 'Not Specified' 
         ELSE TRIM(region) 
     END AS region
     ```

### 3.2 Data Cleansing & Text Standardization
*(Referenced in Report: Page 14, Test 2)*

- **Trimming:** All string columns across customers, employees, products, and shippers pass through `TRIM()` to remove erroneous leading/trailing spaces.
- **Natural Key Uppercasing:** Alphanumeric customer codes are forced to uppercase using `UPPER(TRIM(customer_id))` to avoid duplicate surrogate keys due to case differences (e.g., `'alfki'` vs `'ALFKI'`).

### 3.3 Data Type Conversions
*(Referenced in Report: Page 15, Test 3)*

- **Temporal Keys:** Dates stored as operational text strings (`'YYYY-MM-DD'`) are converted into smart integer keys in `YYYYMMDD` format via:
  ```sql
  CAST(CONVERT(VARCHAR(8), CAST(o.order_date AS DATE), 112) AS INT)
  ```
- **Monetary Precision:** SQLite floating-point types (`REAL`) are cast into fixed-precision decimals (`DECIMAL(10,2)` and `DECIMAL(12,2)`) to eliminate floating-point rounding discrepancies.

### 3.4 Mathematical Derivations of Analytical Measures
*(Referenced in Report: Pages 15–16, Test 4)*

All additive business measures and transit duration metrics are pre-calculated at the atomic line-item grain in `Fact_Orders`:

| Analytical Measure | SQL Calculation Formula | Business Rationale & Meaning |
| :--- | :--- | :--- |
| **Gross Sales Amount** | `CAST((od.quantity * od.unit_price) AS DECIMAL(12,2))` | Top-line nominal invoice revenue before discount deductions. |
| **Discount Amount** | `CAST((od.quantity * od.unit_price * od.discount) AS DECIMAL(12,2))` | Cash value surrendered via sales discount negotiations. |
| **Net Sales Amount** | `CAST(((od.quantity * od.unit_price) - (od.quantity * od.unit_price * od.discount)) AS DECIMAL(12,2))` | Actual realized commercial cash flow received. |
| **Allocated Freight** | `CAST((o.freight / NULLIF(olt.line_item_count, 0)) AS DECIMAL(10,2))` | Header-level freight charge proportionally divided across line items. |
| **Shipping Lead Time (Days)** | `DATEDIFF(DAY, CAST(o.order_date AS DATE), CAST(o.shipped_date AS DATE))` | Total transit days elapsed from order placement to dispatch. |
| **Delivery Delay (Days)** | `CASE WHEN CAST(o.shipped_date AS DATE) > CAST(o.required_date AS DATE) THEN DATEDIFF(DAY, CAST(o.required_date AS DATE), CAST(o.shipped_date AS DATE)) ELSE 0 END` | Number of days delivery exceeded the contractual deadline. |
| **SLA Breached Flag** | `CASE WHEN CAST(o.shipped_date AS DATE) > CAST(o.required_date AS DATE) THEN 1 ELSE 0 END` | Binary indicator (1 = Contract Breached, 0 = On-Time). |

#### Mathematical Trace Example (Order 10264):
- **Quantity:** $25$ SKUs | **Unit Price:** $\$7.70$ | **Discount Rate:** $15\%$ ($0.15$) | **Allocated Freight:** $\$1.84$
- **Gross Sales:** $25 \times 7.70 = \mathbf{\$192.50}$
- **Discount Amount:** $192.50 \times 0.15 = \mathbf{\$28.88}$
- **Net Sales:** $192.50 - 28.88 = \mathbf{\$163.63}$
- **Lead Time:** Order Date `1996-07-24` &rarr; Shipped Date `1996-08-23` = **30 days**
- **Delivery Delay:** Required Date `1996-08-21` &rarr; Shipped Date `1996-08-23` = **2 days late**
- **SLA Breach Flag:** `1` (Breached)

---

## 4. Load Phase: Sequence & Referential Integrity

To maintain foreign key constraints and avoid orphan records, the data loading follows a strict sequential dependency order in **`03_etl_pipeline_load.sql`**:

```
Step 1: Dim_Date (Generate continuous calendar 1996–1999 + Unknown sentinel)
Step 2: Dim_Customer (Load from stg_customers with TRIM & Imputation)
Step 3: Dim_Product (Denormalize stg_products with stg_categories)
Step 4: Dim_Employee (Load from stg_employees with full name concatenation)
Step 5: Dim_Shipper (Load from stg_shippers)
Step 6: Fact_Orders (Lookup surrogate keys from dimensions & compute measures)
```

### Surrogate Key Resolution Logic:
```sql
FROM Northwind_Staging.dbo.stg_order_details od
INNER JOIN Northwind_Staging.dbo.stg_orders o ON od.order_id = o.order_id
INNER JOIN OrderLineTotals olt ON o.order_id = olt.order_id
INNER JOIN Dim_Customer dc ON UPPER(TRIM(o.customer_id)) = dc.customer_id_nk
INNER JOIN Dim_Product dp ON od.product_id = dp.product_id_nk
INNER JOIN Dim_Employee de ON o.employee_id = de.employee_id_nk
INNER JOIN Dim_Shipper ds ON o.ship_via = ds.shipper_id_nk;
```

---

## 5. ETL Validation & Integrity Audit Results

All 6 validation test queries in **`04_etl_validation_tests.sql`** have been executed on Microsoft SQL Server 2022. The empirical results match the final report screenshots:

### Audit Results Summary Table

| Test Suite | Metric Verified | Expected Result | Actual Result in SQL Server | Status | Report Location |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Test 1: Imputation** | Unshipped Orders Line Items | 73 lines | **73 lines** (`shipped_date_key = -1`, `is_shipped = 0`) | ✅ PASS | Page 14 (Top) |
| **Test 1: Imputation** | Customer Regions Imputed | 60 clients | **60 clients** (`region = 'Not Specified'`) | ✅ PASS | Page 14 (Top) |
| **Test 2: Sanitization** | Untrimmed Customer IDs | 0 | **0** | ✅ PASS | Page 14 (Bottom) |
| **Test 2: Sanitization** | Untrimmed Company Names | 0 | **0** | ✅ PASS | Page 14 (Bottom) |
| **Test 2: Sanitization** | Non-Uppercase Customer IDs | 0 | **0** | ✅ PASS | Page 14 (Bottom) |
| **Test 3: Data Types** | `order_date_key`, `shipped_date_key` | `int` | **`int` (Precision 10, Scale 0)** | ✅ PASS | Page 15 (Top) |
| **Test 3: Data Types** | `gross_sales_amount`, `discount_amount`, `net_sales_amount` | `decimal(12,2)` | **`decimal(12,2)`** | ✅ PASS | Page 15 (Top) |
| **Test 3: Data Types** | `freight_allocated` | `decimal(10,2)` | **`decimal(10,2)`** | ✅ PASS | Page 15 (Top) |
| **Test 4: Derivations** | Mathematical Trace (Order 10264) | Gross: $192.50, Net: $163.63 | **Gross: $192.50, Net: $163.63** | ✅ PASS | Page 15 (Bottom) & Page 16 |
| **Test 5: Row Counts** | `Dim_Date` | 1,462 | **1,462** (1,461 calendar days + 1 sentinel) | ✅ PASS | Page 16 (Top) |
| **Test 5: Row Counts** | `Dim_Customer` | 91 | **91** | ✅ PASS | Page 16 (Top) |
| **Test 5: Row Counts** | `Dim_Product` | 77 | **77** | ✅ PASS | Page 16 (Top) |
| **Test 5: Row Counts** | `Dim_Employee` | 9 | **9** | ✅ PASS | Page 16 (Top) |
| **Test 5: Row Counts** | `Dim_Shipper` | 6 | **6** | ✅ PASS | Page 16 (Top) |
| **Test 5: Row Counts** | `Fact_Orders` | 2,155 | **2,155** (Exact match with `stg_order_details`) | ✅ PASS | Page 16 (Top) |
| **Test 6: Foreign Keys** | Orphan Customers, Products, Employees, Shippers, Dates | 0 | **0 across all dimensions** | ✅ PASS | Page 17 (Top) |

---

## 6. Departmental Data Mart Views

*(Referenced in Report: Pages 17–19, Task 6)*

To provide user-tailored analytics without querying the raw fact table directly, two specialized SQL views are implemented in **`05_create_data_marts.sql`**:

### 6.1 Logistics & SLA Performance Mart (`vw_Logistics_SLA_Performance`)
- **Target Audience:** Supply Chain Directors, Logistics Dispatchers, 3PL Carrier Procurement Managers.
- **Key Attributes:** `order_id_nk`, `carrier_name`, `destination_country`, `order_date`, `required_date`, `shipped_date`, `shipping_lead_time_days`, `delivery_delay_days`, `is_sla_breached`, `freight_allocated`.
- **Verified Findings:** Successfully isolates breached shipments such as orders **10264** (Federal Shipping, 2 days late), **10271** (United Package, 1 day late), and **10280** (Speedy Express, 1 day late).

### 6.2 Sales Performance & Margin Leakage Mart (`vw_Sales_Margin_Leakage`)
- **Target Audience:** VP of Sales, Commercial Finance Analysts, Pricing Committee.
- **Key Attributes:** `order_id_nk`, `sales_representative`, `customer_name`, `product_name`, `category_name`, `quantity`, `gross_sales_amount`, `discount_amount`, `net_sales_amount`, `has_discount`.
- **Verified Findings:** Identifies major discount concessions granted by representatives **Robert King** (Order 10353: $2,108.00 discount; Order 10424: $2,065.84 discount), **Steven Buchanan** (Order 10372: $2,108.00 discount), and **Andrew Fuller** (Order 10912: $1,856.85 discount).

---

## 7. How to Reproduce & Execute

Follow these steps to execute the entire solution from scratch on any SQL Server instance:

```bash
# 1. Open SSMS or execute via sqlcmd:
sqlcmd -S . -E -i "00_create_and_load_staging.sql"
sqlcmd -S . -E -i "01_staging_verification.sql"
sqlcmd -S . -E -i "02_create_dw_schema.sql"
sqlcmd -S . -E -i "03_etl_pipeline_load.sql"
sqlcmd -S . -E -i "04_etl_validation_tests.sql"
sqlcmd -S . -E -i "05_create_data_marts.sql"
```
Every script will complete successfully, creating both `Northwind_Staging` and `Northwind_DW` with 100% data integrity and full alignment with the project report.
