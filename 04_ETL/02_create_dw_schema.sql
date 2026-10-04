-- ============================================================================
-- SCRIPT 02: Enterprise Data Warehouse DDL (Star Schema)
-- Database: Northwind_DW
-- Report Section: Task 4 (Pages 8-10)
-- Description: Creates the dimensional star schema with Kimball surrogate keys,
--              conformed dimensions, atomic fact table, and foreign key constraints.
-- ============================================================================

USE master;
GO

IF DB_ID('Northwind_DW') IS NOT NULL
BEGIN
    ALTER DATABASE Northwind_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Northwind_DW;
END
GO

CREATE DATABASE Northwind_DW;
GO

USE Northwind_DW;
GO

-- 1. Dim_Date (Role-Playing Conformed Date Dimension)
CREATE TABLE Dim_Date (
    date_key INT PRIMARY KEY,                    -- Smart Integer Key: YYYYMMDD (-1 for Unknown/Unshipped)
    full_date DATE NULL,
    calendar_year INT NULL,
    calendar_quarter INT NULL,
    calendar_month INT NULL,
    month_name NVARCHAR(20) NULL,
    day_of_month INT NULL,
    day_of_week_name NVARCHAR(20) NULL,
    week_of_year INT NULL,
    is_weekend BIT NULL
);
GO

-- 2. Dim_Customer (Corporate Clients & Geographic Location Hierarchy)
CREATE TABLE Dim_Customer (
    customer_key INT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate Primary Key
    customer_id_nk NVARCHAR(10) NOT NULL,        -- Natural Business Key
    company_name NVARCHAR(150) NOT NULL,
    contact_name NVARCHAR(100) NULL,
    contact_title NVARCHAR(100) NULL,
    address NVARCHAR(200) NULL,
    city NVARCHAR(100) NULL,
    region NVARCHAR(100) NULL,                   -- Imputed with 'Not Specified' when null
    postal_code NVARCHAR(50) NULL,
    country NVARCHAR(100) NOT NULL,
    phone NVARCHAR(50) NULL
);
GO

-- 3. Dim_Product (Flattened Product Catalog & Categories)
CREATE TABLE Dim_Product (
    product_key INT IDENTITY(1,1) PRIMARY KEY,   -- Surrogate Primary Key
    product_id_nk INT NOT NULL,                  -- Natural Business Key
    product_name NVARCHAR(100) NOT NULL,
    category_name NVARCHAR(100) NOT NULL,        -- Denormalized from categories.csv
    category_description NVARCHAR(MAX) NULL,
    quantity_per_unit NVARCHAR(50) NULL,
    catalog_unit_price DECIMAL(10,2) NULL,
    units_in_stock INT NULL,
    units_on_order INT NULL,
    reorder_level INT NULL,
    is_discontinued BIT NOT NULL
);
GO

-- 4. Dim_Employee (Commercial Sales Representatives & Account Managers)
CREATE TABLE Dim_Employee (
    employee_key INT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate Primary Key
    employee_id_nk INT NOT NULL,                 -- Natural Business Key
    full_name NVARCHAR(150) NOT NULL,
    job_title NVARCHAR(100) NULL,
    hire_date DATE NULL,
    city NVARCHAR(100) NULL,
    country NVARCHAR(100) NULL
);
GO

-- 5. Dim_Shipper (Logistics 3PL Freight Forwarders)
CREATE TABLE Dim_Shipper (
    shipper_key INT IDENTITY(1,1) PRIMARY KEY,   -- Surrogate Primary Key
    shipper_id_nk INT NOT NULL,                  -- Natural Business Key
    company_name NVARCHAR(100) NOT NULL,
    phone NVARCHAR(50) NULL
);
GO

-- 6. Fact_Orders (Central Fact Table at Atomic Order Line-Item Grain)
CREATE TABLE Fact_Orders (
    order_fact_key BIGINT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate Fact Key
    
    -- Degenerate Dimensions (Invoice Identifier & Delivery Target)
    order_id_nk INT NOT NULL,
    ship_name NVARCHAR(100) NULL,
    ship_city NVARCHAR(100) NULL,
    ship_region NVARCHAR(100) NULL,
    ship_country NVARCHAR(100) NULL,
    
    -- Role-Playing Date Surrogate Foreign Keys
    order_date_key INT NOT NULL,
    required_date_key INT NOT NULL,
    shipped_date_key INT NOT NULL,
    
    -- Dimension Surrogate Foreign Keys
    customer_key INT NOT NULL,
    product_key INT NOT NULL,
    employee_key INT NOT NULL,
    shipper_key INT NOT NULL,
    
    -- Operational Compliance & Status Flags
    is_shipped BIT NOT NULL,
    is_sla_breached BIT NOT NULL,
    
    -- Additive Monetary and Unit Measures
    unit_price DECIMAL(10,2) NOT NULL,
    quantity INT NOT NULL,
    discount_rate REAL NOT NULL,
    gross_sales_amount DECIMAL(12,2) NOT NULL,
    discount_amount DECIMAL(12,2) NOT NULL,
    net_sales_amount DECIMAL(12,2) NOT NULL,
    freight_allocated DECIMAL(10,2) NOT NULL,
    
    -- Duration Measures (in Days)
    shipping_lead_time_days INT NULL,
    delivery_delay_days INT NOT NULL,

    -- Foreign Key Referential Integrity Constraints
    CONSTRAINT FK_FactOrders_OrderDate FOREIGN KEY (order_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactOrders_RequiredDate FOREIGN KEY (required_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactOrders_ShippedDate FOREIGN KEY (shipped_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactOrders_Customer FOREIGN KEY (customer_key) REFERENCES Dim_Customer(customer_key),
    CONSTRAINT FK_FactOrders_Product FOREIGN KEY (product_key) REFERENCES Dim_Product(product_key),
    CONSTRAINT FK_FactOrders_Employee FOREIGN KEY (employee_key) REFERENCES Dim_Employee(employee_key),
    CONSTRAINT FK_FactOrders_Shipper FOREIGN KEY (shipper_key) REFERENCES Dim_Shipper(shipper_key)
);
GO

-- Indexes for Fast Join Performance
CREATE INDEX IX_FactOrders_OrderDate ON Fact_Orders(order_date_key);
CREATE INDEX IX_FactOrders_Customer ON Fact_Orders(customer_key);
CREATE INDEX IX_FactOrders_Product ON Fact_Orders(product_key);
CREATE INDEX IX_FactOrders_Employee ON Fact_Orders(employee_key);
CREATE INDEX IX_FactOrders_Shipper ON Fact_Orders(shipper_key);
GO
