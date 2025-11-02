-- Triggers for audit logging and data validation

USE analytics_dw;

DELIMITER $$

-- ============================================
-- Audit Log Table
-- ============================================
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id VARCHAR(100),
    old_values JSON,
    new_values JSON,
    user_name VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_table (table_name),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB;

-- ============================================
-- TRIGGER: Customer Insert Audit
-- ============================================
CREATE TRIGGER trg_customer_insert_audit
AFTER INSERT ON dim_customer
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name,
        operation,
        record_id,
        new_values,
        user_name
    ) VALUES (
        'dim_customer',
        'INSERT',
        NEW.customer_id,
        JSON_OBJECT(
            'name', NEW.name,
            'email', NEW.email,
            'segment', NEW.segment
        ),
        USER()
    );
END$$

-- ============================================
-- TRIGGER: Customer Update Audit
-- ============================================
CREATE TRIGGER trg_customer_update_audit
AFTER UPDATE ON dim_customer
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name,
        operation,
        record_id,
        old_values,
        new_values,
        user_name
    ) VALUES (
        'dim_customer',
        'UPDATE',
        NEW.customer_id,
        JSON_OBJECT(
            'name', OLD.name,
            'email', OLD.email,
            'segment', OLD.segment
        ),
        JSON_OBJECT(
            'name', NEW.name,
            'email', NEW.email,
            'segment', NEW.segment
        ),
        USER()
    );
END$$

-- ============================================
-- TRIGGER: Sales Data Validation
-- ============================================
CREATE TRIGGER trg_sales_validation
BEFORE INSERT ON fact_sales
FOR EACH ROW
BEGIN
    -- Validate quantity
    IF NEW.quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity must be greater than 0';
    END IF;
    
    -- Validate price
    IF NEW.unit_price < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Unit price cannot be negative';
    END IF;
    
    -- Calculate profit if not provided
    IF NEW.profit_amount IS NULL THEN
        SET NEW.profit_amount = NEW.total_amount - NEW.cost_amount;
    END IF;
END$$

-- ============================================
-- TRIGGER: Auto-update Product Status
-- ============================================
CREATE TRIGGER trg_product_status_update
BEFORE UPDATE ON dim_product
FOR EACH ROW
BEGIN
    -- Auto-mark as inactive if discontinued
    IF NEW.discontinue_date IS NOT NULL AND NEW.discontinue_date <= CURDATE() THEN
        SET NEW.is_active = FALSE;
    END IF;
END$$

DELIMITER ;
