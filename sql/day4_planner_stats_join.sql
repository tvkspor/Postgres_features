-- Day 4 — Planner, statistics, join

-- Xem statistics đang có gì
SELECT attname, n_distinct, null_frac, correlation,
       array_length(most_common_vals::text::text[], 1) AS n_mcv
FROM pg_stats WHERE schemaname='lab' AND tablename='fact_txn';

-- Ép từng thuật toán join để so
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.segment, count(*), sum(f.amount)
FROM lab.fact_txn f JOIN lab.dim_customer c USING (customer_id)
WHERE f.txn_ts >= '2024-12-01' GROUP BY 1;

SET enable_hashjoin = off;  -- EXPLAIN (ANALYZE) SELECT ...;  -- ép Merge/NL
SET enable_mergejoin = off; -- EXPLAIN (ANALYZE) SELECT ...;
RESET ALL;

-- work_mem ảnh hưởng plan như thế nào
SET work_mem = '1MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, count(*) FROM lab.fact_txn GROUP BY 1;
-- Tìm: "Batches: 16  Memory Usage: ...  Disk Usage: 250000kB"

SET work_mem = '512MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, count(*) FROM lab.fact_txn GROUP BY 1;
-- "Batches: 1" -> không tràn đĩa, nhanh hơn nhiều
RESET work_mem;

-- Extended statistics — thí nghiệm rõ nhất
EXPLAIN (ANALYZE)
SELECT * FROM lab.dim_customer WHERE city = 'Q1' AND province = 'HCM';
-- So rows= ước tính với actual rows= -> lệch nhiều lần

CREATE STATISTICS st_geo (dependencies, ndistinct, mcv)
  ON city, province FROM lab.dim_customer;
ANALYZE lab.dim_customer;

EXPLAIN (ANALYZE)
SELECT * FROM lab.dim_customer WHERE city = 'Q1' AND province = 'HCM';
-- Ước tính sát hơn hẳn

SELECT * FROM pg_stats_ext WHERE statistics_name = 'st_geo';

-- Tăng độ phân giải statistics
ALTER TABLE lab.fact_txn ALTER COLUMN branch_code SET STATISTICS 1000;
ANALYZE lab.fact_txn;

-- Parallel query
SET max_parallel_workers_per_gather = 4;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(amount) FROM lab.fact_txn;
-- "Workers Planned: 4  Workers Launched: 4"
SET max_parallel_workers_per_gather = 0;
EXPLAIN (ANALYZE) SELECT count(*), sum(amount) FROM lab.fact_txn;  -- so thời gian
RESET max_parallel_workers_per_gather;

-- pg_stat_statements — công cụ tìm query xấu
SELECT pg_stat_statements_reset();
-- chạy một loạt query...
SELECT round(total_exec_time::numeric, 0) AS total_ms,
       calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows,
       round(100.0*shared_blks_hit/NULLIF(shared_blks_hit+shared_blks_read,0),1) AS hit_pct,
       left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 15;

-- Checkpoint Day 4:
-- 1. Plan cho rows=1 nhưng actual rows=200000 — hậu quả gì với join phía trên?
-- 2. Khi nào Nested Loop tốt hơn Hash Join?
-- 3. work_mem là per-connection hay per-node? Rủi ro khi đặt cao?
