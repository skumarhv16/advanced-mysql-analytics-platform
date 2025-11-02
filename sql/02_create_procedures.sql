-- Stored Procedures and Functions
-- Advanced business logic implementation

USE analytics_dw;

DELIMITER $$

-- ============================================
-- PROCEDURE: Load Sales Data
-- ============================================
CREATE PROCEDURE sp_load_sales_data(
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    DECLARE v_rows_processed INT DEFAULT 0;
    DECLARE v_start_time DATETIME;
    
    SET v_start_time = NOW();
    
    -- Start transaction
    START TRANSACTION;
    
    -- Insert sales data from staging
    INSERT INTO fact_sales (
        transaction_id,
        date_key,
        customer_key,
        product_key,
        location_key,
        quantity,
        unit_price,
        discount_amount,
        tax_amount,
        total_amount,
        cost_amount,
        profit_amount,
        order_number,
        payment_method
    )
    SELECT 
        s.transaction_id,
        d.date_key,
        c.customer_key,
        p.product_key,
        l.location_key,
        s.quantity,
        s.unit_price,
        s.discount_amount,
        s.tax_amount,
        s.total_amount,
        p.unit_cost * s.quantity as cost_amount,
        s.total_amount - (p.unit_cost * s.quantity) as profit_amount,
        s.order_number,
        s.payment_method
    FROM staging.sales_raw s
    INNER JOIN dim_date d ON s.order_date = d.date
    INNER JOIN dim_customer c ON s.customer_id = c.customer_id AND c.is_current = TRUE
    INNER JOIN dim_product p ON s.product_id = p.product_id
    INNER JOIN dim_location l ON s.location_id = l.location_id
    WHERE s.order_date BETWEEN p_start_date AND p_end_date
    ON DUPLICATE KEY UPDATE
        quantity = VALUES(quantity),
        total_amount = VALUES(total_amount);
    
    SET v_rows_processed = ROW_COUNT();
    
    -- Log the load
    INSERT INTO etl_log (
        process_name,
        start_time,
        end_time,
        rows_processed,
        status
    ) VALUES (
        'sp_load_sales_data',
        v_start_time,
        NOW(),
        v_rows_processed,
        'SUCCESS'
    );
    
    COMMIT;
    
    SELECT v_rows_processed AS rows_loaded;
END$$

-- ============================================
-- PROCEDURE: Update Customer Lifetime Value
-- ============================================
CREATE PROCEDURE sp_update_customer_ltv()
BEGIN
    UPDATE dim_customer c
    SET c.lifetime_value = (
        SELECT COALESCE(SUM(f.total_amount), 0)
        FROM fact_sales f
        WHERE f.customer_key = c.customer_key
    )
    WHERE c.is_current = TRUE;
    
    SELECT ROW_COUNT() AS customers_updated;
END$$

-- ============================================
-- PROCEDURE: Create Customer SCD Type 2
-- ============================================
CREATE PROCEDURE sp_update_customer_scd(
    IN p_customer_id VARCHAR(50),
    IN p_name VARCHAR(200),
    IN p_email VARCHAR(200),
    IN p_segment VARCHAR(50),
    IN p_city VARCHAR(100),
    IN p_state VARCHAR(50)
)
BEGIN
    DECLARE v_customer_key INT;
    DECLARE v_changed BOOLEAN DEFAULT FALSE;
    
    -- Check if customer data has changed
    SELECT customer_key INTO v_customer_key
    FROM dim_customer
    WHERE customer_id = p_customer_id 
      AND is_current = TRUE
      AND (name != p_name 
           OR email != p_email 
           OR segment != p_segment
           OR city != p_city
           OR state != p_state)
    LIMIT 1;
    
    IF v_customer_key IS NOT NULL THEN
        SET v_changed = TRUE;
        
        -- Expire old record
        UPDATE dim_customer
        SET expiry_date = CURDATE(),
            is_current = FALSE
        WHERE customer_key = v_customer_key;
        
        -- Insert new record
        INSERT INTO dim_customer (
            customer_id, name, email, segment,
            city, state, effective_date, is_current, version
        )
        SELECT 
            customer_id,
            p_name,
            p_email,
            p_segment,
            p_city,
            p_state,
            CURDATE(),
            TRUE,
            version + 1
        FROM dim_customer
        WHERE customer_key = v_customer_key;
        
        SELECT 'Customer updated with SCD Type 2' AS status;
    ELSE
        SELECT 'No changes detected' AS status;
    END IF;
END$$

-- ============================================
-- FUNCTION: Calculate Discount Tier
-- ============================================
CREATE FUNCTION fn_get_discount_tier(
    p_lifetime_value DECIMAL(15,2)
)
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
    DECLARE v_tier VARCHAR(20);
    
    IF p_lifetime_value >= 50000 THEN
        SET v_tier = 'PLATINUM';
    ELSEIF p_lifetime_value >= 20000 THEN
        SET v_tier = 'GOLD';
    ELSEIF p_lifetime_value >= 5000 THEN
        SET v_tier = 'SILVER';
    ELSE
        SET v_tier = 'BRONZE';
    END IF;
    
    RETURN v_tier;
END$$

-- ============================================
-- FUNCTION: Get Sales Trend
-- ============================================
CREATE FUNCTION fn_sales_trend(
    p_customer_key INT,
    p_months INT
)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
    DECLARE v_current_total DECIMAL(15,2);
    DECLARE v_previous_total DECIMAL(15,2);
    DECLARE v_trend VARCHAR(20);
    
    -- Current period
    SELECT COALESCE(SUM(total_amount), 0) INTO v_current_total
    FROM fact_sales f
    INNER JOIN dim_date d ON f.date_key = d.date_key
    WHERE f.customer_key = p_customer_key
      AND d.date >= DATE_SUB(CURDATE(), INTERVAL p_months MONTH);
    
    -- Previous period
    SELECT COALESCE(SUM(total_amount), 0) INTO v_previous_total
    FROM fact_sales f
    INNER JOIN dim_date d ON f.date_key = d.date_key
    WHERE f.customer_key = p_customer_key
      AND d.date >= DATE_SUB(CURDATE(), INTERVAL p_months * 2 MONTH)
      AND d.date < DATE_SUB(CURDATE(), INTERVAL p_months MONTH);
    
    IF v_previous_total = 0 THEN
        SET v_trend = 'NEW';
    ELSEIF v_current_total > v_previous_total * 1.1 THEN
        SET v_trend = 'GROWING';
    ELSEIF v_current_total < v_previous_total * 0.9 THEN
        SET v_trend = 'DECLINING';
    ELSE
        SET v_trend = 'STABLE';
    END IF;
    
    RETURN v_trend;
END$$

-- ============================================
-- PROCEDURE: Generate Daily Aggregates
-- ============================================
CREATE PROCEDURE sp_generate_daily_aggregates(
    IN p_date DATE
)
BEGIN
    DECLARE v_date_key INT;
    
    SELECT date_key INTO v_date_key
    FROM dim_date
    WHERE date = p_date;
    
    -- Delete existing aggregates for the date
    DELETE FROM agg_daily_sales WHERE date_key = v_date_key;
    
    -- Generate new aggregates
    INSERT INTO agg_daily_sales (
        date_key,
        customer_key,
        product_key,
        total_quantity,
        total_revenue,
        total_cost,
        total_profit,
        order_count,
        avg_order_value
    )
    SELECT 
        date_key,
        customer_key,
        product_key,
        SUM(quantity) as total_quantity,
        SUM(total_amount) as total_revenue,
        SUM(cost_amount) as total_cost,
        SUM(profit_amount) as total_profit,
        COUNT(DISTINCT order_number) as order_count,
        AVG(total_amount) as avg_order_value
    FROM fact_sales
    WHERE date_key = v_date_key
    GROUP BY date_key, customer_key, product_key;
    
    SELECT ROW_COUNT() AS aggregates_created;
END$$

DELIMITER ;
