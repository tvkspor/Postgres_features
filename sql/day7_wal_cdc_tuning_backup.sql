-- Day 7 — WAL, checkpoint, CDC, tuning, backup

-- 7.1 WAL & checkpoint
SELECT pg_current_wal_lsn();
SELECT * FROM pg_stat_checkpointer;   -- PG17+; PG16 trở xuống: pg_stat_bgwriter

-- Đo WAL sinh ra bởi một thao tác
SELECT pg_current_wal_lsn() AS before \gset
INSERT INTO lab.t_small SELECT g+100000, 'x', 1 FROM generate_series(1,100000) g;
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), :'before')) AS wal_generated;
-- Lặp lại với UNLOGGED table -> WAL gần bằng 0

CHECKPOINT;   -- ép checkpoint
-- bash: docker logs pg-lab 2>&1 | grep checkpoint | tail -5
-- "checkpoint complete: wrote N buffers (X%) ... write=.. s, sync=.. s"

-- 7.2 Logical replication / CDC
SHOW wal_level;   -- phải là logical (đã set ở Day 0)

ALTER TABLE lab.fact_txn REPLICA IDENTITY FULL;   -- gửi cả before-image
CREATE PUBLICATION pub_lab FOR TABLE lab.fact_txn, lab.dim_customer;

-- Tạo slot và đọc thay đổi bằng tay (mô phỏng Debezium)
SELECT pg_create_logical_replication_slot('slot_test', 'test_decoding');

UPDATE lab.fact_txn SET amount = amount + 1 WHERE txn_id < 5;
DELETE FROM lab.fact_txn WHERE txn_id = 6;

SELECT lsn, xid, data FROM pg_logical_slot_peek_changes('slot_test', NULL, NULL);
-- Thấy old-key/new-tuple. Đổi REPLICA IDENTITY DEFAULT rồi thử lại -> khác hẳn

-- QUAN TRỌNG: slot chết giữ WAL vô hạn
SELECT slot_name, active, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;

SELECT pg_drop_replication_slot('slot_test');   -- luôn dọn

-- 7.3 Backup & PITR (chạy trong bash, không phải psql)
-- Logical:
--   docker exec pg-lab pg_dump -U postgres -d lab -Fc -f /tmp/lab.dump
--   docker exec pg-lab pg_restore -U postgres -d lab_restore -j 4 /tmp/lab.dump
-- Physical (nền của PITR):
--   docker exec pg-lab pg_basebackup -U postgres -D /tmp/basebackup -Ft -z -P
-- Khái niệm: pg_basebackup + WAL archive -> restore tới thời điểm bất kỳ bằng
-- recovery_target_time trong postgresql.conf + file recovery.signal.

-- 7.4 Tuning tổng hợp — bài tập cuối
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

-- Chạy một workload hỗn hợp (5-10 query nặng đã viết trong tuần), rồi:

-- 1. Query nào tốn nhất
SELECT round(total_exec_time::numeric) AS total_ms, calls,
       round(mean_exec_time::numeric,2) AS mean_ms, left(query,70)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

-- 2. Cache hit
SELECT round(100.0*blks_hit/NULLIF(blks_hit+blks_read,0),2) AS hit_pct,
       temp_files, pg_size_pretty(temp_bytes) AS temp
FROM pg_stat_database WHERE datname='lab';

-- 3. Chờ ở đâu
SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity WHERE state='active' GROUP BY 1,2 ORDER BY 3 DESC;

-- 4. Đang cache cái gì
SELECT c.relname, count(*) AS buffers,
       pg_size_pretty(count(*)*8192::bigint) AS size
FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- Rồi đổi shared_buffers / work_mem / random_page_cost trong docker-compose.yml,
-- restart, đo lại. Ghi số vào notes.md — bài tập quan trọng nhất cả tuần.

-- 7.5 PG18 AIO
SHOW io_method;                 -- worker
SHOW io_workers;                -- 3
SHOW effective_io_concurrency;  -- 16
SHOW io_combine_limit;          -- 128kB

-- So sync vs worker trên sequential scan
-- ALTER SYSTEM SET io_method = 'sync';  -- cần restart
-- docker compose restart pg
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM lab.fact_txn;
-- rồi đổi lại worker, đo lại
