-- Day 1 — Storage & MVCC internals
-- Mục tiêu: hiểu vật lý một row nằm ở đâu, tại sao UPDATE tạo bản mới, HOT update là gì.

-- 1. Xem địa chỉ vật lý và visibility
SELECT ctid, xmin, xmax, id, name FROM lab.t_small WHERE id <= 5;

-- 2. UPDATE làm gì? Chạy từng dòng
UPDATE lab.t_small SET amount = amount + 1 WHERE id = 1;
SELECT ctid, xmin, xmax, id FROM lab.t_small WHERE id = 1;
-- ctid đổi -> row mới ở vị trí khác. Row cũ vẫn nằm đó (dead tuple).

-- 3. Mổ bên trong page
SELECT lp, lp_off, lp_len, t_xmin, t_xmax, t_ctid,
       (t_infomask2 & 16384)::bool AS hot_updated,
       (t_infomask  & 256)::bool   AS xmin_committed
FROM heap_page_items(get_raw_page('lab.t_small', 0))
ORDER BY lp LIMIT 20;
-- Sẽ thấy dòng có t_xmax khác 0 -> đó là dead tuple

-- 4. Kích thước thật vs số dòng
SELECT pg_size_pretty(pg_relation_size('lab.t_small')) AS heap_size,
       count(*) FROM lab.t_small;

-- Thí nghiệm HOT update — phần đáng giá nhất
CREATE TABLE lab.hot_demo (id int PRIMARY KEY, indexed_col int, plain_col int)
  WITH (fillfactor = 70, autovacuum_enabled = off);
CREATE INDEX ix_hot ON lab.hot_demo(indexed_col);
INSERT INTO lab.hot_demo SELECT g, g, g FROM generate_series(1,50000) g;
VACUUM ANALYZE lab.hot_demo;

-- Baseline
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname='hot_demo';

-- Case A: update cột KHÔNG có index -> HOT
UPDATE lab.hot_demo SET plain_col = plain_col + 1;
SELECT n_tup_upd, n_tup_hot_upd,
       round(100.0*n_tup_hot_upd/n_tup_upd,1) AS hot_pct
FROM pg_stat_user_tables WHERE relname='hot_demo';   -- hot_pct cao

-- Case B: update cột CÓ index -> không HOT
UPDATE lab.hot_demo SET indexed_col = indexed_col + 1;
SELECT n_tup_upd, n_tup_hot_upd,
       round(100.0*n_tup_hot_upd/n_tup_upd,1) AS hot_pct
FROM pg_stat_user_tables WHERE relname='hot_demo';   -- hot_pct tụt

SELECT pg_size_pretty(pg_relation_size('lab.hot_demo')) AS heap,
       pg_size_pretty(pg_relation_size('ix_hot'))       AS idx;

-- Checkpoint Day 1 (trả lời không nhìn tài liệu):
-- 1. Tại sao SELECT count(*) trên Postgres chậm hơn SQL Server?
-- 2. Tại sao thêm một index có thể làm UPDATE chậm đi nhiều hơn là chỉ chi phí ghi index?
-- 3. ctid thay đổi khi nào?
