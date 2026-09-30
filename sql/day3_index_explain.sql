-- Day 3 — Index & đọc EXPLAIN

-- Baseline: chưa có index phụ
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab.fact_txn WHERE customer_id = 12345;
-- Parallel Seq Scan, đọc vài trăm nghìn buffer

CREATE INDEX ix_txn_cust ON lab.fact_txn(customer_id);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab.fact_txn WHERE customer_id = 12345;
-- Index Scan, buffer giảm hàng nghìn lần

-- So sánh các loại index trên cùng dữ liệu
CREATE INDEX ix_txn_ts_btree ON lab.fact_txn(txn_ts);
CREATE INDEX ix_txn_ts_brin ON lab.fact_txn USING BRIN(txn_ts) WITH (pages_per_range = 32);

SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes WHERE relname = 'fact_txn';
-- B-tree ~200MB+, BRIN vài chục KB

-- Kiểm tra correlation trước khi tin BRIN
SELECT attname, correlation FROM pg_stats
WHERE schemaname='lab' AND tablename='fact_txn' AND attname IN ('txn_ts','customer_id');
-- txn_ts ~1.0 -> BRIN tốt. customer_id ~0 -> BRIN vô dụng.

-- So plan: ép từng bên
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM lab.fact_txn
WHERE txn_ts BETWEEN '2024-06-01' AND '2024-06-07';
RESET enable_bitmapscan;

DROP INDEX lab.ix_txn_ts_btree;   -- giờ chỉ còn BRIN
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM lab.fact_txn
WHERE txn_ts BETWEEN '2024-06-01' AND '2024-06-07';

-- Partial / expression / covering
CREATE INDEX ix_txn_failed ON lab.fact_txn(txn_ts)
  WHERE status = 'failed';
EXPLAIN (ANALYZE) SELECT * FROM lab.fact_txn
WHERE status='failed' AND txn_ts > '2024-12-01';

CREATE INDEX ix_cust_lower ON lab.dim_customer(lower(full_name));
EXPLAIN (ANALYZE) SELECT * FROM lab.dim_customer WHERE lower(full_name) = 'cust_500';

CREATE INDEX ix_txn_cover ON lab.fact_txn(customer_id) INCLUDE (amount, status);
VACUUM ANALYZE lab.fact_txn;                -- bắt buộc: cập nhật visibility map
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, sum(amount) FROM lab.fact_txn
WHERE customer_id BETWEEN 100 AND 200 GROUP BY 1;
-- Tìm "Index Only Scan" và "Heap Fetches: 0"

-- GIN cho JSONB và trigram
CREATE INDEX ix_txn_payload ON lab.fact_txn USING GIN (payload jsonb_path_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab.fact_txn WHERE payload @> '{"channel":"atm"}';

CREATE INDEX ix_cust_trgm ON lab.dim_customer USING GIN (full_name gin_trgm_ops);
EXPLAIN (ANALYZE) SELECT * FROM lab.dim_customer WHERE full_name ILIKE '%1234%';

-- Tạo index không khoá bảng
CREATE INDEX CONCURRENTLY ix_txn_branch ON lab.fact_txn(branch_code);
-- Nếu fail -> index INVALID, phải drop tay:
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;

-- Tìm index vô dụng
SELECT schemaname||'.'||relname AS tbl, indexrelname,
       idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND schemaname = 'lab'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Checkpoint Day 3:
-- 1. Khi nào planner chọn Bitmap Heap Scan thay vì Index Scan?
-- 2. Heap Fetches cao trong Index Only Scan nghĩa là gì, sửa thế nào?
-- 3. Index (a, b, c) — query WHERE b = 1 AND c = 2 dùng được không? Trước PG18 và từ PG18 khác nhau chỗ nào?
