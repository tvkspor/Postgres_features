-- Day 2 — VACUUM, bloat, freeze, wraparound
-- Mục tiêu: hiểu chu trình rác của Postgres và biết chẩn đoán.

-- Tạo bloat có kiểm soát
CREATE TABLE lab.bloat_demo AS
SELECT g AS id, md5(g::text) AS payload FROM generate_series(1,500000) g;
ALTER TABLE lab.bloat_demo SET (autovacuum_enabled = off);
CREATE INDEX ON lab.bloat_demo(id);
VACUUM ANALYZE lab.bloat_demo;

SELECT pg_size_pretty(pg_relation_size('lab.bloat_demo'));  -- ghi lại

-- Update toàn bảng 5 lần
DO $$ BEGIN
  FOR i IN 1..5 LOOP
    UPDATE lab.bloat_demo SET payload = md5(random()::text);
  END LOOP;
END $$;

SELECT pg_size_pretty(pg_relation_size('lab.bloat_demo'));  -- phình ~5-6x

-- Đo bloat chính xác
SELECT * FROM pgstattuple('lab.bloat_demo');
-- dead_tuple_percent cao, free_percent thấp

-- VACUUM: space tái dùng nhưng KHÔNG trả OS
VACUUM (VERBOSE, ANALYZE) lab.bloat_demo;
SELECT pg_size_pretty(pg_relation_size('lab.bloat_demo'));  -- vẫn to
SELECT dead_tuple_percent, free_percent FROM pgstattuple('lab.bloat_demo');  -- free cao

-- VACUUM FULL: trả OS, nhưng khoá bảng
VACUUM FULL lab.bloat_demo;
SELECT pg_size_pretty(pg_relation_size('lab.bloat_demo'));  -- về gần ban đầu

-- Thí nghiệm transaction dài chặn VACUUM — mở 2 psql session:
-- Session A:
--   BEGIN;
--   SELECT 1;                        -- giữ snapshot
--   -- ĐỪNG commit
-- Session B:
--   UPDATE lab.bloat_demo SET payload = md5(random()::text);
--   VACUUM (VERBOSE) lab.bloat_demo;
--   -- Log: "N dead row versions cannot be removed yet, oldest xmin: ..."

SELECT pid, state, age(backend_xmin) AS xmin_age,
       now() - xact_start AS txn_duration, left(query, 60)
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL ORDER BY xact_start;

-- Session A: COMMIT;
-- Session B: VACUUM lại -> giờ mới dọn được

-- Freeze & wraparound
SELECT datname, age(datfrozenxid) AS xid_age,
       round(100.0*age(datfrozenxid)/2000000000, 4) AS pct_wraparound
FROM pg_database ORDER BY 2 DESC;

SELECT relname, age(relfrozenxid) AS xid_age,
       pg_size_pretty(pg_total_relation_size(oid))
FROM pg_class WHERE relkind = 'r' AND relnamespace = 'lab'::regnamespace
ORDER BY age(relfrozenxid) DESC;

-- Ép freeze
VACUUM (FREEZE, VERBOSE) lab.t_small;

-- Bộ query giám sát — lưu lại dùng mãi
SELECT schemaname||'.'||relname AS tbl, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric/NULLIF(n_live_tup,0), 3) AS dead_ratio,
       last_autovacuum, last_autoanalyze, autovacuum_count
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC;

SELECT slot_name, active, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;

-- Checkpoint Day 2:
-- 1. VACUUM khác VACUUM FULL thế nào về lock và về space?
-- 2. Tại sao bảng append-only vẫn cần autovacuum? (gợi ý: PG13+ có autovacuum_vacuum_insert_threshold)
-- 3. Bạn thấy dead_ratio = 0.4 dù autovacuum chạy liên tục — nghi ngờ ba nguyên nhân nào?
