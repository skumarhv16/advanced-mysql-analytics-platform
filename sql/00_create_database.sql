-- Create Analytics Database
-- Author: Sandeep Kumar H V
-- Description: Enterprise data warehouse database setup

DROP DATABASE IF EXISTS analytics_dw;
CREATE DATABASE analytics_dw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE analytics_dw;

-- Set default storage engine and configurations
SET default_storage_engine = InnoDB;
SET GLOBAL innodb_buffer_pool_size = 2147483648; -- 2GB
SET GLOBAL query_cache_size = 67108864; -- 64MB

-- Create dedicated user for analytics
CREATE USER IF NOT EXISTS 'analytics_user'@'localhost' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON analytics_dw.* TO 'analytics_user'@'localhost';
FLUSH PRIVILEGES;

-- Create separate schemas for organization
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS facts;
CREATE SCHEMA IF NOT EXISTS dimensions;
CREATE SCHEMA IF NOT EXISTS aggregates;

SELECT 'Database created successfully' AS status;
