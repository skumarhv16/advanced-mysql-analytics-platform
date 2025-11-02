-- Data Warehouse Schema Creation
-- Implements Star Schema with fact and dimension tables

USE analytics_dw;

-- ============================================
-- DIMENSION TABLES
-- ============================================

-- Date Dimension (Pre-populated with dates)
CREATE TABLE dim_date (
    date_key INT PRIMARY KEY,
    date DATE NOT NULL UNIQUE,
    year INT NOT NULL,
    quarter INT NOT NULL,
    month INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    week INT NOT NULL,
    day_of_month INT NOT NULL,
    day_of_week INT NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_holiday BOOLEAN DEFAULT FALSE,
    fiscal_year INT NOT NULL,
    fiscal_quarter INT NOT NULL,
    INDEX idx_date (date),
    INDEX idx_year_month (year, month),
    INDEX idx_fiscal (fiscal_year, fiscal_quarter)
) ENGINE=InnoDB;

-- Customer Dimension (SCD Type 2)
CREATE TABLE dim_customer (
    customer_key INT AUTO_INCREMENT PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(200),
    phone VARCHAR(20),
    segment VARCHAR(50),
    lifetime_value DECIMAL(15,2) DEFAULT 0,
    acquisition_channel VARCHAR(50),
    -- Address information
    address_line1 VARCHAR(200),
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    -- SCD Type 2 columns
    effective_date DATE NOT NULL,
    expiry_date DATE,
    is_current BOOLEAN DEFAULT TRUE,
    version INT DEFAULT 1,
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- Indexes
    INDEX idx_customer_id (customer_id),
    INDEX idx_is_current (is_current),
    INDEX idx_segment (segment),
    INDEX idx_location (country, state, city),
    INDEX idx_effective_date (effective_date),
    UNIQUE KEY uk_customer_version (customer_id, version)
) ENGINE=InnoDB;

-- Product Dimension
CREATE TABLE dim_product (
    product_key INT AUTO_INCREMENT PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL UNIQUE,
    sku VARCHAR(100) NOT NULL,
    name VARCHAR(300) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    subcategory VARCHAR(100),
    brand VARCHAR(100),
    supplier VARCHAR(200),
    unit_cost DECIMAL(10,2),
    unit_price DECIMAL(10,2),
    margin_percent DECIMAL(5,2),
    weight DECIMAL(10,2),
    dimensions VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    launch_date DATE,
    discontinue_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- Indexes
    INDEX idx_product_id (product_id),
    INDEX idx_category (category, subcategory),
    INDEX idx_brand (brand),
    INDEX idx_active (is_active),
    FULLTEXT idx_product_search (name, description)
) ENGINE=InnoDB;

-- Location Dimension
CREATE TABLE dim_location (
    location_key INT AUTO_INCREMENT PRIMARY KEY,
    location_id VARCHAR(50) NOT NULL UNIQUE,
    location_name VARCHAR(200) NOT NULL,
    location_type VARCHAR(50), -- warehouse, store, office
    address_line1 VARCHAR(200),
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    region VARCHAR(100),
    timezone VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    opened_date DATE,
    closed_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_location_id (location_id),
    INDEX idx_type (location_type),
    INDEX idx_region (region),
    INDEX idx_geo (latitude, longitude)
) ENGINE=InnoDB;

-- ============================================
-- FACT TABLES
-- ============================================

-- Sales Fact Table
CREATE TABLE fact_sales (
    sales_key BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) NOT NULL UNIQUE,
    -- Foreign keys to dimensions
    date_key INT NOT NULL,
    customer_key INT NOT NULL,
    product_key INT NOT NULL,
    location_key INT NOT NULL,
    -- Measures
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL,
    cost_amount DECIMAL(12,2),
    profit_amount DECIMAL(12,2),
    -- Degenerate dimensions
    order_number VARCHAR(100),
    payment_method VARCHAR(50),
    shipping_method VARCHAR(50),
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Foreign key constraints
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    FOREIGN KEY (product_key) REFERENCES dim_product(product_key),
    FOREIGN KEY (location_key) REFERENCES dim_location(location_key),
    -- Indexes for analytics
    INDEX idx_date (date_key),
    INDEX idx_customer (customer_key),
    INDEX idx_product (product_key),
    INDEX idx_location (location_key),
    INDEX idx_order (order_number),
    INDEX idx_transaction (transaction_id),
    INDEX idx_composite (date_key, customer_key, product_key)
) ENGINE=InnoDB
PARTITION BY RANGE (date_key) (
    PARTITION p2023 VALUES LESS THAN (20240101),
    PARTITION p2024_q1 VALUES LESS THAN (20240401),
    PARTITION p2024_q2 VALUES LESS THAN (20240701),
    PARTITION p2024_q3 VALUES LESS THAN (20241001),
    PARTITION p2024_q4 VALUES LESS THAN (20250101),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Inventory Fact Table
CREATE TABLE fact_inventory (
    inventory_key BIGINT AUTO_INCREMENT PRIMARY KEY,
    snapshot_date_key INT NOT NULL,
    product_key INT NOT NULL,
    location_key INT NOT NULL,
    -- Measures
    quantity_on_hand INT NOT NULL,
    quantity_reserved INT DEFAULT 0,
    quantity_available INT GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,
    reorder_point INT,
    reorder_quantity INT,
    unit_cost DECIMAL(10,2),
    inventory_value DECIMAL(15,2) GENERATED ALWAYS AS (quantity_on_hand * unit_cost) STORED,
    last_count_date DATE,
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Foreign keys
    FOREIGN KEY (snapshot_date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (product_key) REFERENCES dim_product(product_key),
    FOREIGN KEY (location_key) REFERENCES dim_location(location_key),
    -- Indexes
    INDEX idx_snapshot (snapshot_date_key),
    INDEX idx_product (product_key),
    INDEX idx_location (location_key),
    UNIQUE KEY uk_inventory (snapshot_date_key, product_key, location_key)
) ENGINE=InnoDB;

-- Web Events Fact Table (Clickstream data)
CREATE TABLE fact_web_events (
    event_key BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id VARCHAR(100) NOT NULL UNIQUE,
    date_key INT NOT NULL,
    customer_key INT,
    -- Event details
    event_type VARCHAR(50) NOT NULL, -- page_view, click, purchase, etc.
    page_url VARCHAR(500),
    referrer_url VARCHAR(500),
    session_id VARCHAR(100),
    device_type VARCHAR(50),
    browser VARCHAR(50),
    os VARCHAR(50),
    -- Measures
    duration_seconds INT,
    scroll_depth_percent INT,
    -- Metadata stored as JSON
    event_metadata JSON,
    -- Timestamp
    event_timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Foreign keys
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    -- Indexes
    INDEX idx_date (date_key),
    INDEX idx_customer (customer_key),
    INDEX idx_event_type (event_type),
    INDEX idx_session (session_id),
    INDEX idx_timestamp (event_timestamp)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(event_timestamp) * 100 + MONTH(event_timestamp)) (
    PARTITION p202401 VALUES LESS THAN (202402),
    PARTITION p202402 VALUES LESS THAN (202403),
    PARTITION p202403 VALUES LESS THAN (202404),
    PARTITION p_current VALUES LESS THAN MAXVALUE
);
