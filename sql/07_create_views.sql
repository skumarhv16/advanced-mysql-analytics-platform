-- Analytical Views for Reporting

USE analytics_dw;

-- ============================================
-- VIEW: Sales Summary by Customer
-- ============================================
CREATE OR REPLACE VIEW vw_customer_sales_summary AS
SELECT 
    c.customer_id,
    c.name as customer_name,
    c.segment,
    c.city,
    c.state,
    COUNT(DISTINCT f.order_number) as total_orders,
    SUM(f.quantity) as total_items,
    SUM(f.total_amount) as total_revenue,
    AVG(f.total_amount) as avg_order_value,
    MAX(d.date) as last_order_date,
    DATEDIFF(CURDATE(), MAX(d.date)) as days_since_last_order,
    fn_get_discount_tier(c.lifetime_value) as discount_tier
FROM dim_customer c
INNER JOIN fact_sales f ON c.customer_key = f.customer_key
INNER JOIN dim_date d ON f.date_key = d.date_key
WHERE c.is_current = TRUE
GROUP BY c.customer_key, c.customer_id, c.name, c.segment, c.city, c.state, c.lifetime_value;

-- ============================================
-- VIEW: Product Performance
-- ============================================
CREATE OR REPLACE VIEW vw_product_performance AS
SELECT 
    p.product_id,
    p.name as product_name,
    p.category,
    p.brand,
    SUM(f.quantity) as units_sold,
    SUM(f.total_amount) as total_revenue,
    SUM(f.profit_amount) as total_profit,
    AVG(f.unit_price) as avg_selling_price,
    COUNT(DISTINCT f.customer_key) as unique_customers,
    (SUM(f.profit_amount) / SUM(f.total_amount)) * 100 as profit_margin_percent
FROM dim_product p
INNER JOIN fact_sales f ON p.product_key = f.product_key
GROUP BY p.product_key, p.product_id, p.name, p.category, p.brand
HAVING units_sold > 0;

-- ============================================
-- VIEW: Monthly Sales Trend
-- ============================================
CREATE OR REPLACE VIEW vw_monthly_sales_trend AS
SELECT 
    d.year,
    d.month,
    d.month_name,
    COUNT(DISTINCT f.transaction_id) as transaction_count,
    SUM(f.quantity) as total_quantity,
    SUM(f.total_amount) as total_revenue,
    SUM(f.profit_amount) as total_profit,
    COUNT(DISTINCT f.customer_key) as unique_customers,
    AVG(f.total_amount) as avg_transaction_value
FROM fact_sales f
INNER JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;

-- ============================================
-- VIEW: Inventory Status
-- ============================================
CREATE OR REPLACE VIEW vw_inventory_status AS
SELECT 
    p.product_id,
    p.name as product_name,
    p.category,
    l.location_name,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_available,
    i.reorder_point,
    CASE 
        WHEN i.quantity_available <= 0 THEN 'OUT_OF_STOCK'
        WHEN i.quantity_available <= i.reorder_point THEN 'LOW_STOCK'
        ELSE 'IN_STOCK'
    END as stock_status,
    i.inventory_value
FROM fact_inventory i
INNER JOIN dim_product p ON i.product_key = p.product_key
INNER JOIN dim_location l ON i.location_key = l.location_key
INNER JOIN dim_date d ON i.snapshot_date_key = d.date_key
WHERE d.date = CURDATE();

-- ============================================
-- VIEW: Customer Segmentation
-- ============================================
CREATE OR REPLACE VIEW vw_customer_segmentation AS
SELECT 
    c.customer_id,
    c.name,
    c.segment,
    c.lifetime_value,
    fn_get_discount_tier(c.lifetime_value) as tier,
    fn_sales_trend(c.customer_key, 3) as trend_3month,
    COUNT(DISTINCT f.order_number) as order_count,
    AVG(f.total_amount) as avg_order_value,
    DATEDIFF(CURDATE(), MAX(d.date)) as recency_days,
    SUM(f.total_amount) as total_spent
FROM dim_customer c
LEFT JOIN fact_sales f ON c.customer_key = f.customer_key
LEFT JOIN dim_date d ON f.date_key = d.date_key
WHERE c.is_current = TRUE
GROUP BY c.customer_key, c.customer_id, c.name, c.segment, c.lifetime_value;
