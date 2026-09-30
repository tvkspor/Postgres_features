-- Day 6 — Ngày Data Engineering

-- 6.1 Partitioning
CREATE TABLE lab.fact_part (
    txn_id      bigint,
    txn_ts      timestamptz NOT NULL,
    customer_id int,
    amount      numeric(14,2),
    status      text
) PARTITION BY RANGE (txn_ts);

DO $$
DECLARE d date := '2024-01-01';
BEGIN
  WHILE d < '2025-01-01' LOOP
    EXECUTE format(
      'CREATE TABLE lab.fact_part_%s PARTITION OF lab.fact_part
         FOR VALUES FROM (%L) TO (%L)',
      to_char(d,'YYYYMM'), d, d + interval '1 month');
    d := d + interval '1 month';
  END LOOP;
END $$;

INSERT INTO lab.fact_part
SELECT txn_id, txn_ts, customer_id, amount, status FROM lab.fact_txn;
ANALYZE lab.fact_part;

-- Partition pruning
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab.fact_part WHERE txn_ts >= '2024-07-01' AND txn_ts < '2024-08-01';
-- Chỉ scan 1 partition

-- Detach nhanh thay vì DELETE (điểm mạnh lớn nhất)
ALTER TABLE lab.fact_part DETACH PARTITION lab.fact_part_202401 CONCURRENTLY;

-- 6.2 Bulk load
-- bash:
-- docker exec pg-lab psql -U postgres -d lab -c \
--   "\copy (SELECT * FROM lab.fact_txn LIMIT 1000000) TO '/tmp/f.csv' CSV HEADER"

CREATE TABLE lab.load_test (LIKE lab.fact_txn INCLUDING ALL);

-- Cách nhanh nhất
TRUNCATE lab.load_test;
-- COPY lab.load_test FROM '/tmp/f.csv' CSV HEADER;

-- Pattern ETL: bảng tạm không ghi WAL
CREATE UNLOGGED TABLE lab.stg_txn (LIKE lab.fact_txn);
-- COPY lab.stg_txn FROM '/tmp/f.csv' CSV HEADER;   -- nhanh hơn nữa
-- Lưu ý: UNLOGGED mất dữ liệu khi crash, không replicate — chỉ dùng cho staging

-- 6.3 Upsert & SCD2
CREATE TABLE lab.dim_cust_scd2 (
    sk          bigserial PRIMARY KEY,
    customer_id int NOT NULL,
    full_name   text,
    segment     text,
    row_hash    text,
    valid_from  timestamptz NOT NULL DEFAULT now(),
    valid_to    timestamptz,
    is_current  boolean NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX ux_scd2_current ON lab.dim_cust_scd2(customer_id) WHERE is_current;

-- Upsert Type 1
INSERT INTO lab.dim_cust_scd2 AS t (customer_id, full_name, segment, row_hash)
SELECT customer_id, full_name, segment, md5(full_name||segment)
FROM lab.dim_customer LIMIT 1000
ON CONFLICT (customer_id) WHERE is_current
DO UPDATE SET full_name = EXCLUDED.full_name, segment = EXCLUDED.segment
WHERE t.row_hash IS DISTINCT FROM EXCLUDED.row_hash;   -- tránh update vô nghĩa -> tránh bloat

-- MERGE (PG15+, chuẩn SQL, giống T-SQL)
MERGE INTO lab.dim_cust_scd2 t
USING (SELECT customer_id, full_name, segment,
              md5(full_name||segment) AS row_hash FROM lab.dim_customer LIMIT 1000) s
ON t.customer_id = s.customer_id AND t.is_current
WHEN MATCHED AND t.row_hash IS DISTINCT FROM s.row_hash THEN
    UPDATE SET valid_to = now(), is_current = false
WHEN NOT MATCHED THEN
    INSERT (customer_id, full_name, segment, row_hash) VALUES (s.customer_id, s.full_name, s.segment, s.row_hash);

-- Chống overlap ở tầng DB — thứ không RDBMS nào khác làm được
CREATE TABLE lab.scd2_range (
    customer_id int NOT NULL,
    attrs       jsonb,
    valid       tstzrange NOT NULL,
    EXCLUDE USING gist (customer_id WITH =, valid WITH &&)
);
INSERT INTO lab.scd2_range VALUES (1, '{"seg":"mass"}', '[2024-01-01, 2024-06-01)');
-- Chèn khoảng chồng lấn để thấy exclusion constraint chặn:
-- INSERT INTO lab.scd2_range VALUES (1, '{"seg":"vip"}',  '[2024-05-01, 2024-12-01)');
-- ERROR: conflicting key value violates exclusion constraint

-- 6.4 Window & grouping sets
SELECT branch_code, status, date_trunc('month', txn_ts) AS m,
       count(*), sum(amount),
       GROUPING(branch_code, status) AS grp
FROM lab.fact_txn WHERE txn_ts >= '2024-10-01'
GROUP BY GROUPING SETS ((branch_code, date_trunc('month', txn_ts)), (status), ());

SELECT branch_code, m, total,
       sum(total) OVER (PARTITION BY branch_code ORDER BY m
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running,
       lag(total) OVER (PARTITION BY branch_code ORDER BY m) AS prev_month,
       rank() OVER (PARTITION BY m ORDER BY total DESC) AS rnk
FROM (
  SELECT branch_code, date_trunc('month', txn_ts) AS m, sum(amount) AS total
  FROM lab.fact_txn GROUP BY 1,2
) q ORDER BY branch_code, m;

-- Thí nghiệm ROWS vs RANGE khi có giá trị trùng — bẫy interview kinh điển
SELECT id, amount,
       sum(amount) OVER (ORDER BY amount ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS by_rows,
       sum(amount) OVER (ORDER BY amount RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS by_range
FROM lab.t_small ORDER BY amount LIMIT 30;

-- 6.5 JSONB
SELECT payload->>'channel' AS channel, count(*)
FROM lab.fact_txn WHERE payload @> '{"channel":"atm"}' GROUP BY 1;

SELECT jsonb_path_query_first(payload, '$.flags[0]') FROM lab.fact_txn LIMIT 5;

-- Bóc JSON thành bảng quan hệ (pattern bronze -> silver)
SELECT txn_id, j.channel, j.device
FROM lab.fact_txn, jsonb_to_record(payload) AS j(channel text, device text)
LIMIT 10;
