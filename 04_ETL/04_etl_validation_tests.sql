-- ============================================================================
-- SCRIPT 04: ETL Transformation and Integrity Validation Tests
-- Database: Northwind_DW
-- Report Section: Task 5.2 & Task 5.3 (Pages 14-17)
-- Description: Executes the exact queries whose screenshot outputs are shown
--              in the final submission report.
-- ============================================================================

USE Northwind_DW;
GO

-- ----------------------------------------------------------------------------
-- TEST 1: Missing Value Imputation Evidence
-- Matches Screenshot: Report Page 14 (Top Grid)
-- ----------------------------------------------------------------------------
SELECT 
    'Unshipped Orders' AS MetricTested,
    COUNT(*) AS TotalAffectedRows,
    MIN(shipped_date_key) AS SentinelDateKeyAssigned,
    MIN(CAST(is_shipped AS INT)) AS IsShippedFlagAssigned,
    COUNT(shipping_lead_time_days) AS NonNullLeadTimes
FROM Fact_Orders
WHERE is_shipped = 0;

SELECT 
    'Imputed Regions' AS MetricTested,
    COUNT(*) AS ImputedCustomerCount,
    MIN(region) AS ImputedValueAssigned
FROM Dim_Customer
WHERE region = 'Not Specified';
GO

-- ----------------------------------------------------------------------------
-- TEST 2: String Sanitization and Key Whitespace Audit
-- Matches Screenshot: Report Page 14 (Bottom Grid)
-- ----------------------------------------------------------------------------
SELECT 
    'Dim_Customer Whitespace Audit' AS CheckType,
    SUM(CASE WHEN customer_id_nk LIKE ' %' OR customer_id_nk LIKE '% ' THEN 1 ELSE 0 END) AS Untrimmed_CustomerIDs,
    SUM(CASE WHEN company_name LIKE ' %' OR company_name LIKE '% ' THEN 1 ELSE 0 END) AS Untrimmed_CompanyNames,
    SUM(CASE WHEN customer_id_nk COLLATE Latin1_General_BIN <> UPPER(customer_id_nk) THEN 1 ELSE 0 END) AS NonUppercase_CustomerIDs
FROM Dim_Customer;
GO

-- ----------------------------------------------------------------------------
-- TEST 3: Column Data Type Conversions Audit (Metadata Inspection)
-- Matches Screenshot: Report Page 15 (Top Grid)
-- ----------------------------------------------------------------------------
SELECT 
    c.name AS ColumnName,
    t.name AS TransformedDataType,
    c.precision AS NumericPrecision,
    c.scale AS DecimalScale
FROM sys.columns c
INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('Fact_Orders')
  AND c.name IN ('order_date_key', 'shipped_date_key', 'gross_sales_amount', 'discount_amount', 'net_sales_amount', 'freight_allocated')
ORDER BY c.column_id;
GO

-- ----------------------------------------------------------------------------
-- TEST 4: Derived Attribute Mathematical Trace
-- Matches Screenshot: Report Page 15 (Bottom Grid)
-- ----------------------------------------------------------------------------
SELECT TOP 5
    order_id_nk,
    unit_price,
    quantity,
    discount_rate,
    gross_sales_amount,
    discount_amount,
    net_sales_amount,
    freight_allocated,
    shipping_lead_time_days,
    delivery_delay_days,
    is_sla_breached
FROM Fact_Orders
WHERE discount_rate > 0 AND delivery_delay_days > 0
ORDER BY order_id_nk;
GO

-- ----------------------------------------------------------------------------
-- TEST 5: Target Star Schema Row Count Preservation Check
-- Matches Screenshot: Report Page 16 (Top Grid)
-- ----------------------------------------------------------------------------
SELECT 'Dim_Date' AS TableName, COUNT(*) AS TotalRows, '1,462 (1461 Days + 1 Sentinel)' AS ExpectedRows FROM Dim_Date
UNION ALL
SELECT 'Dim_Customer', COUNT(*), '91' FROM Dim_Customer
UNION ALL
SELECT 'Dim_Product', COUNT(*), '77' FROM Dim_Product
UNION ALL
SELECT 'Dim_Employee', COUNT(*), '9' FROM Dim_Employee
UNION ALL
SELECT 'Dim_Shipper', COUNT(*), '6' FROM Dim_Shipper
UNION ALL
SELECT 'Fact_Orders', COUNT(*), '2,155 (Exact match with stg_order_details)' FROM Fact_Orders;
GO

-- ----------------------------------------------------------------------------
-- TEST 6: Referential Integrity (Zero Orphan Key Test)
-- Matches Screenshot: Report Page 17 (Top Grid)
-- ----------------------------------------------------------------------------
SELECT 
    SUM(CASE WHEN c.customer_key IS NULL THEN 1 ELSE 0 END) AS Orphan_Customers,
    SUM(CASE WHEN p.product_key IS NULL THEN 1 ELSE 0 END) AS Orphan_Products,
    SUM(CASE WHEN e.employee_key IS NULL THEN 1 ELSE 0 END) AS Orphan_Employees,
    SUM(CASE WHEN s.shipper_key IS NULL THEN 1 ELSE 0 END) AS Orphan_Shippers,
    SUM(CASE WHEN d.date_key IS NULL THEN 1 ELSE 0 END) AS Orphan_OrderDates
FROM Fact_Orders f
LEFT JOIN Dim_Customer c ON f.customer_key = c.customer_key
LEFT JOIN Dim_Product p ON f.product_key = p.product_key
LEFT JOIN Dim_Employee e ON f.employee_key = e.employee_key
LEFT JOIN Dim_Shipper s ON f.shipper_key = s.shipper_key
LEFT JOIN Dim_Date d ON f.order_date_key = d.date_key;
GO
