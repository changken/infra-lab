-- ============================================================
-- SQL-5~7：把資料載入 HeatWave，看查詢是否被 offload
-- 前置：HeatWave cluster 已建立（💰 用完就把 enable_heatwave 改回 false）
-- ============================================================

USE lab;

-- SQL-5: orders 表，灌約 100 萬筆（遞迴 CTE 先造 1 萬筆，再自我 cross join 放大）
CREATE TABLE IF NOT EXISTS orders (
  order_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  amount      DECIMAL(10,2) NOT NULL,
  created_at  DATETIME NOT NULL
);

SET SESSION cte_max_recursion_depth = 1000;

INSERT INTO orders (customer_id, amount, created_at)
WITH RECURSIVE seq (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 1000
)
SELECT (a.n * b.n) % 5000,
       ROUND(RAND() * 1000, 2),
       NOW() - INTERVAL (a.n + b.n) MINUTE
FROM seq a CROSS JOIN seq b;   -- 1000 x 1000 = 100 萬筆

-- SQL-6: 標記並載入 HeatWave
ALTER TABLE orders SECONDARY_ENGINE = RAPID;
ALTER TABLE orders SECONDARY_LOAD;

-- 確認載入狀態（LOAD_STATUS 應為 AVAIL_RPDGSTABSTATE）
SELECT NAME, LOAD_STATUS, LOAD_PROGRESS
FROM performance_schema.rpd_tables t
JOIN performance_schema.rpd_table_id i USING (ID)
WHERE i.TABLE_NAME = 'orders';

-- SQL-7: 比較同一個聚合查詢
-- (a) 只用 InnoDB，記錄耗時
SET SESSION use_secondary_engine = OFF;
SELECT customer_id, SUM(amount) AS total
FROM orders GROUP BY customer_id ORDER BY total DESC LIMIT 10;

-- (b) 允許 HeatWave：EXPLAIN 應出現 "Using secondary engine RAPID"，並記錄耗時
SET SESSION use_secondary_engine = ON;
EXPLAIN SELECT customer_id, SUM(amount) AS total
FROM orders GROUP BY customer_id ORDER BY total DESC LIMIT 10;

SELECT customer_id, SUM(amount) AS total
FROM orders GROUP BY customer_id ORDER BY total DESC LIMIT 10;

-- 對照：單筆主鍵查詢不會被 offload（走 InnoDB 比較快）
EXPLAIN SELECT * FROM orders WHERE order_id = 12345;
