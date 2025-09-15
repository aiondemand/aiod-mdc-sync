CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

CREATE TABLE IF NOT EXISTS items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- Debezium MySQL source user + privileges (idempotent)
-- =========================================================
-- Create (or keep) the Debezium user
CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY 'test_pass';
-- Ensure password is set even if user already existed
ALTER USER 'test_user'@'%' IDENTIFIED BY 'test_pass';

-- Required privileges for Debezium snapshot + binlog streaming
-- NOTE: On some MySQL 8.x builds 'REPLICATION SLAVE' is aliased to 'REPLICATION REPLICA'.
-- If you ever see an error about REPLICATION SLAVE, replace it with REPLICATION REPLICA.
GRANT
  SELECT,
  RELOAD,
  SHOW DATABASES,
  REPLICATION SLAVE,
  REPLICATION CLIENT,
  LOCK TABLES
ON *.* TO 'test_user'@'%';

FLUSH PRIVILEGES;