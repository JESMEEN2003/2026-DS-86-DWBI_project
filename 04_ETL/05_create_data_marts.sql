-- ============================================================================
-- SCRIPT 05: Departmental Data Mart Views & Sample Audits
-- Database: Northwind_DW
-- Report Section: Task 6 (Pages 17-19)
-- Description: Creates the two dedicated data mart views:
--              1. vw_Logistics_SLA_Performance (Logistics & Supply Chain)
--              2. vw_Sales_Margin_Leakage (Sales & Revenue Governance)
--              Includes the audit queries whose screenshots are in the report.
-- ============================================================================

USE Northwind_DW;
GO

-- 1. Create Logistics & Carrier SLA Performance Mart View
IF OBJECT_ID('dbo.vw_Logistics_SLA_Performance', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Logistics_SLA_Performance;
GO

CREATE VIEW dbo.vw_Logistics_SLA_Performance AS
SELECT 
    f.order_id_nk,
    s.company_name AS carrier_name,
    f.ship_country AS destination_country,
    f.ship_city AS destination_city,
    d_ord.full_date AS order_date,
    d_req.full_date AS required_date,
    CASE WHEN f.shipped_date_key = -1 THEN NULL ELSE d_shp.full_date END AS shipped_date,
    d_ord.calendar_year AS order_year,
    d_ord.calendar_month AS order_month,
    f.is_shipped,
    f.is_sla_breached,
    f.shipping_lead_time_days,
    f.delivery_delay_days,
    f.freight_allocated
FROM dbo.Fact_Orders f
INNER JOIN dbo.Dim_Shipper s ON f.shipper_key = s.shipper_key
INNER JOIN dbo.Dim_Date d_ord ON f.order_date_key = d_ord.date_key
INNER JOIN dbo.Dim_Date d_req ON f.required_date_key = d_req.date_key
INNER JOIN dbo.Dim_Date d_shp ON f.shipped_date_key = d_shp.date_key;
GO

-- 2. Create Sales Performance & Margin Leakage Mart View
IF OBJECT_ID('dbo.vw_Sales_Margin_Leakage', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Sales_Margin_Leakage;
GO

CREATE VIEW dbo.vw_Sales_Margin_Leakage AS
SELECT 
    f.order_id_nk,
    e.full_name AS sales_representative,
    e.job_title,
    c.company_name AS customer_name,
    c.country AS customer_country,
    p.product_name,
    p.category_name,
    d.calendar_year AS sales_year,
    d.calendar_quarter AS sales_quarter,
    d.month_name AS sales_month,
    f.quantity,
    f.unit_price,
    f.discount_rate,
    f.gross_sales_amount,
    f.discount_amount,
    f.net_sales_amount,
    CASE 
        WHEN f.discount_rate > 0 THEN 1 
        ELSE 0 
    END AS has_discount
FROM dbo.Fact_Orders f
INNER JOIN dbo.Dim_Employee e ON f.employee_key = e.employee_key
INNER JOIN dbo.Dim_Customer c ON f.customer_key = c.customer_key
INNER JOIN dbo.Dim_Product p ON f.product_key = p.product_key
INNER JOIN dbo.Dim_Date d ON f.order_date_key = d.date_key;
GO

-- ----------------------------------------------------------------------------
-- AUDIT QUERY 1: Logistics Mart Screenshot Evidence
-- Matches Screenshot: Report Page 17 (Bottom Grid) & Page 18 (Bottom Grid)
-- ----------------------------------------------------------------------------
SELECT TOP 5
    order_id_nk,
    carrier_name,
    destination_country,
    order_date,
    required_date,
    shipped_date,
    shipping_lead_time_days,
    delivery_delay_days,
    is_sla_breached,
    freight_allocated
FROM dbo.vw_Logistics_SLA_Performance
WHERE is_sla_breached = 1
ORDER BY order_id_nk;
GO

-- ----------------------------------------------------------------------------
-- AUDIT QUERY 2: Sales Margin Leakage Mart Screenshot Evidence
-- Matches Screenshot: Report Page 18 (Top Grid) & Page 19 (Bottom Grid)
-- ----------------------------------------------------------------------------
SELECT TOP 5
    order_id_nk,
    sales_representative,
    customer_name,
    product_name,
    category_name,
    quantity,
    gross_sales_amount,
    discount_amount,
    net_sales_amount
FROM dbo.vw_Sales_Margin_Leakage
WHERE discount_amount > 0
ORDER BY discount_amount DESC;
GO
