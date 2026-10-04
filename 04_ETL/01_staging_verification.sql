-- ============================================================================
-- SCRIPT 01: Staging Tables Row Count Verification
-- Database: Northwind_Staging
-- Report Section: Task 3 (Page 6) / Task 5.1 (Page 13)
-- Description: Verifies that data from operational SQLite, CSVs, and JSON files 
--              were ingested 100% into staging tables without record loss.
-- ============================================================================

USE Northwind_Staging;
GO

SELECT 'stg_orders' AS TableName, COUNT(*) AS TotalRows, 830 AS ExpectedRows FROM stg_orders
UNION ALL
SELECT 'stg_order_details', COUNT(*), 2155 FROM stg_order_details
UNION ALL
SELECT 'stg_products', COUNT(*), 77 FROM stg_products
UNION ALL
SELECT 'stg_categories', COUNT(*), 8 FROM stg_categories
UNION ALL
SELECT 'stg_suppliers', COUNT(*), 29 FROM stg_suppliers
UNION ALL
SELECT 'stg_customers', COUNT(*), 91 FROM stg_customers
UNION ALL
SELECT 'stg_employees', COUNT(*), 9 FROM stg_employees
UNION ALL
SELECT 'stg_shippers', COUNT(*), 6 FROM stg_shippers;
GO
