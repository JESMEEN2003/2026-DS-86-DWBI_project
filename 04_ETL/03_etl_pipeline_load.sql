-- ============================================================================
-- SCRIPT 03: Complete ETL Pipeline Load Script
-- Database: Northwind_DW (Populating from Northwind_Staging)
-- Report Section: Task 5 (Pages 13-17)
-- Description: Executes the sequential load:
--              1. Dim_Date (1461 continuous calendar days + 1 Unknown sentinel)
--              2. Dim_Customer (string trim, upper keys, imputation of 'Not Specified')
--              3. Dim_Product (category denormalization & type casting)
--              4. Dim_Employee & Dim_Shipper
--              5. Fact_Orders (surrogate key lookup joins, derived financial/duration measures)
-- ============================================================================

USE Northwind_DW;
GO

SET NOCOUNT ON;

-- Clean existing data for clean execution
DELETE FROM Fact_Orders;
DELETE FROM Dim_Customer;
DELETE FROM Dim_Product;
DELETE FROM Dim_Employee;
DELETE FROM Dim_Shipper;
DELETE FROM Dim_Date;

DBCC CHECKIDENT ('Dim_Customer', RESEED, 0);
DBCC CHECKIDENT ('Dim_Product', RESEED, 0);
DBCC CHECKIDENT ('Dim_Employee', RESEED, 0);
DBCC CHECKIDENT ('Dim_Shipper', RESEED, 0);
DBCC CHECKIDENT ('Fact_Orders', RESEED, 0);

-- STEP 1: Populate Dim_Date
INSERT INTO Dim_Date (
    date_key, full_date, calendar_year, calendar_quarter, 
    calendar_month, month_name, day_of_month, day_of_week_name, 
    week_of_year, is_weekend
)
VALUES (-1, '1900-01-01', 1900, 1, 1, 'Unknown', 1, 'Unknown', 1, 0);

DECLARE @CurDate DATE = '1996-01-01';
DECLARE @StopDate DATE = '1999-12-31';

WHILE @CurDate <= @StopDate
BEGIN
    DECLARE @dKey INT = CAST(CONVERT(VARCHAR(8), @CurDate, 112) AS INT);
    
    INSERT INTO Dim_Date (
        date_key, full_date, calendar_year, calendar_quarter, 
        calendar_month, month_name, day_of_month, day_of_week_name, 
        week_of_year, is_weekend
    )
    VALUES (
        @dKey,
        @CurDate,
        YEAR(@CurDate),
        DATEPART(QUARTER, @CurDate),
        MONTH(@CurDate),
        DATENAME(MONTH, @CurDate),
        DAY(@CurDate),
        DATENAME(WEEKDAY, @CurDate),
        DATEPART(ISO_WEEK, @CurDate),
        CASE WHEN DATEPART(WEEKDAY, @CurDate) IN (1, 7) THEN 1 ELSE 0 END
    );
    
    SET @CurDate = DATEADD(DAY, 1, @CurDate);
END;

-- STEP 2: Load Dim_Customer
INSERT INTO Dim_Customer (
    customer_id_nk, company_name, contact_name, contact_title, 
    address, city, region, postal_code, country, phone
)
SELECT 
    UPPER(TRIM(customer_id)),
    TRIM(company_name),
    NULLIF(TRIM(contact_name), ''),
    NULLIF(TRIM(contact_title), ''),
    NULLIF(TRIM(address), ''),
    TRIM(city),
    CASE 
        WHEN region IS NULL OR TRIM(region) = '' OR TRIM(region) = 'None' 
        THEN 'Not Specified' 
        ELSE TRIM(region) 
    END,
    NULLIF(TRIM(postal_code), ''),
    TRIM(country),
    NULLIF(TRIM(phone), '')
FROM Northwind_Staging.dbo.stg_customers;

-- STEP 3: Load Dim_Product
INSERT INTO Dim_Product (
    product_id_nk, product_name, category_name, category_description, 
    quantity_per_unit, catalog_unit_price, units_in_stock, units_on_order, 
    reorder_level, is_discontinued
)
SELECT 
    p.product_id,
    TRIM(p.product_name),
    COALESCE(TRIM(c.category_name), 'Uncategorized'),
    c.description,
    p.quantity_per_unit,
    CAST(p.unit_price AS DECIMAL(10,2)),
    COALESCE(p.units_in_stock, 0),
    COALESCE(p.units_on_order, 0),
    COALESCE(p.reorder_level, 0),
    CASE WHEN p.discontinued = 1 THEN 1 ELSE 0 END
FROM Northwind_Staging.dbo.stg_products p
LEFT JOIN Northwind_Staging.dbo.stg_categories c ON p.category_id = c.category_id;

-- STEP 4: Load Dim_Employee
INSERT INTO Dim_Employee (
    employee_id_nk, full_name, job_title, hire_date, city, country
)
SELECT 
    employee_id,
    TRIM(first_name) + ' ' + TRIM(last_name),
    TRIM(title),
    TRY_CAST(hire_date AS DATE),
    TRIM(city),
    TRIM(country)
FROM Northwind_Staging.dbo.stg_employees;

-- STEP 5: Load Dim_Shipper
INSERT INTO Dim_Shipper (
    shipper_id_nk, company_name, phone
)
SELECT 
    shipper_id,
    TRIM(company_name),
    NULLIF(TRIM(phone), '')
FROM Northwind_Staging.dbo.stg_shippers;

-- STEP 6: Load Fact_Orders
WITH OrderLineTotals AS (
    SELECT order_id, COUNT(*) AS line_item_count
    FROM Northwind_Staging.dbo.stg_order_details
    GROUP BY order_id
)
INSERT INTO Fact_Orders (
    order_id_nk,
    ship_name,
    ship_city,
    ship_region,
    ship_country,
    order_date_key,
    required_date_key,
    shipped_date_key,
    customer_key,
    product_key,
    employee_key,
    shipper_key,
    is_shipped,
    is_sla_breached,
    unit_price,
    quantity,
    discount_rate,
    gross_sales_amount,
    discount_amount,
    net_sales_amount,
    freight_allocated,
    shipping_lead_time_days,
    delivery_delay_days
)
SELECT 
    o.order_id,
    TRIM(o.ship_name),
    TRIM(o.ship_city),
    CASE 
        WHEN o.ship_region IS NULL OR TRIM(o.ship_region) = '' OR TRIM(o.ship_region) = 'None' 
        THEN 'Not Specified' 
        ELSE TRIM(o.ship_region) 
    END,
    TRIM(o.ship_country),
    
    -- Date Keys
    CAST(CONVERT(VARCHAR(8), CAST(o.order_date AS DATE), 112) AS INT),
    CAST(CONVERT(VARCHAR(8), CAST(o.required_date AS DATE), 112) AS INT),
    CASE 
        WHEN o.shipped_date IS NULL OR TRIM(o.shipped_date) = '' OR TRIM(o.shipped_date) = 'None' THEN -1
        ELSE CAST(CONVERT(VARCHAR(8), CAST(o.shipped_date AS DATE), 112) AS INT)
    END,
    
    -- Surrogate Keys via Dimension Joins
    dc.customer_key,
    dp.product_key,
    de.employee_key,
    ds.shipper_key,
    
    -- Status Indicators
    CASE 
        WHEN o.shipped_date IS NOT NULL AND TRIM(o.shipped_date) <> '' AND TRIM(o.shipped_date) <> 'None' 
        THEN 1 ELSE 0 
    END,
    CASE 
        WHEN o.shipped_date IS NOT NULL 
             AND TRIM(o.shipped_date) <> '' 
             AND TRIM(o.shipped_date) <> 'None'
             AND CAST(o.shipped_date AS DATE) > CAST(o.required_date AS DATE) 
        THEN 1 ELSE 0 
    END,
    
    -- Additive Measures
    CAST(od.unit_price AS DECIMAL(10,2)),
    od.quantity,
    od.discount,
    CAST((od.quantity * od.unit_price) AS DECIMAL(12,2)),
    CAST((od.quantity * od.unit_price * od.discount) AS DECIMAL(12,2)),
    CAST(((od.quantity * od.unit_price) - (od.quantity * od.unit_price * od.discount)) AS DECIMAL(12,2)),
    
    -- Freight Split
    CAST((o.freight / NULLIF(olt.line_item_count, 0)) AS DECIMAL(10,2)),
    
    -- Duration Metrics (Days)
    CASE 
        WHEN o.shipped_date IS NULL OR TRIM(o.shipped_date) = '' OR TRIM(o.shipped_date) = 'None' THEN NULL
        ELSE DATEDIFF(DAY, CAST(o.order_date AS DATE), CAST(o.shipped_date AS DATE))
    END,
    
    CASE 
        WHEN o.shipped_date IS NULL OR TRIM(o.shipped_date) = '' OR TRIM(o.shipped_date) = 'None' THEN 0
        WHEN CAST(o.shipped_date AS DATE) > CAST(o.required_date AS DATE) 
             THEN DATEDIFF(DAY, CAST(o.required_date AS DATE), CAST(o.shipped_date AS DATE))
        ELSE 0
    END

FROM Northwind_Staging.dbo.stg_order_details od
INNER JOIN Northwind_Staging.dbo.stg_orders o ON od.order_id = o.order_id
INNER JOIN OrderLineTotals olt ON o.order_id = olt.order_id
INNER JOIN Dim_Customer dc ON UPPER(TRIM(o.customer_id)) = dc.customer_id_nk
INNER JOIN Dim_Product dp ON od.product_id = dp.product_id_nk
INNER JOIN Dim_Employee de ON o.employee_id = de.employee_id_nk
INNER JOIN Dim_Shipper ds ON o.ship_via = ds.shipper_id_nk;
GO
