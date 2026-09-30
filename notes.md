# Postgres Lab Notes

Ghi lại con số thật cho mọi thí nghiệm — không có số thì tuần sau quên sạch.
Điền vào ngay sau khi chạy từng lab, đừng để dồn cuối ngày.

## Day 1 — Storage & MVCC

| Thí nghiệm | Trước | Sau | Ghi chú |
|---|---|---|---|
| ctid của id=1 trước/sau UPDATE | | | |
| hot_demo: hot_pct (update cột không index) | | | |
| hot_demo: hot_pct (update cột có index) | | | |
| hot_demo: heap size / index size | | | |

**Checkpoint answers:**
1. Tại sao count(*) chậm hơn SQL Server?
2. Tại sao thêm index làm UPDATE chậm hơn?
3. ctid đổi khi nào?

## Day 2 — VACUUM & bloat

| Thí nghiệm | Giá trị |
|---|---|
| bloat_demo size ban đầu | |
| bloat_demo size sau 5x UPDATE | |
| dead_tuple_percent (pgstattuple) | |
| size sau VACUUM thường | |
| size sau VACUUM FULL | |
| xid_age lớn nhất trong lab schema | |

**Checkpoint answers:**
1. VACUUM vs VACUUM FULL (lock + space)?
2. Vì sao append-only vẫn cần autovacuum?
3. dead_ratio=0.4 dù autovacuum chạy — 3 nghi ngờ?

## Day 3 — Index & EXPLAIN

| Query | Plan trước index | Plan sau index | Buffers trước | Buffers sau |
|---|---|---|---|---|
| customer_id = 12345 | | | | |
| txn_ts range (btree) | | | | |
| txn_ts range (brin) | | | | |

- correlation(txn_ts) = ____  correlation(customer_id) = ____
- Index Only Scan Heap Fetches (trước/sau VACUUM ANALYZE): ____ / ____

**Checkpoint answers:**
1. Bitmap Heap Scan vs Index Scan — khi nào?
2. Heap Fetches cao nghĩa là gì, sửa sao?
3. Index (a,b,c), query WHERE b=1 AND c=2 — trước/từ PG18?

## Day 4 — Planner & statistics

| Thí nghiệm | rows ước tính | actual rows | thời gian |
|---|---|---|---|
| join customer/txn (hash join) | | | |
| join (ép merge join) | | | |
| group by customer_id, work_mem=1MB (batches=?) | | | |
| group by customer_id, work_mem=512MB (batches=?) | | | |
| city+province trước extended stats | | | |
| city+province sau CREATE STATISTICS | | | |
| count(*) parallel workers=4 | | | |
| count(*) parallel workers=0 | | | |

**Checkpoint answers:**
1. rows=1 vs actual=200000 — hậu quả cho join phía trên?
2. Nested Loop tốt hơn Hash Join khi nào?
3. work_mem per-connection hay per-node? rủi ro?

## Day 5 — Transaction & lock

- Non-repeatable read xảy ra ở Read Committed: có / không
- Non-repeatable read ở Repeatable Read: có / không
- SSI: session nào bị abort với lỗi 40001?
- Deadlock: log ghi gì? (paste đoạn log)
- SKIP LOCKED: 2 session lấy đúng 10 job khác nhau mỗi bên: có / không

**Checkpoint answers:**
1. Postgres REPEATABLE READ khác chuẩn SQL chỗ nào?
2. FOR UPDATE vs SKIP LOCKED vs FOR NO KEY UPDATE?
3. Vì sao ADD COLUMN DEFAULT nhanh nhưng ALTER COLUMN TYPE chậm?

## Day 6 — Partition / Load / JSONB / Window

- Partition pruning: query 1 tháng chỉ scan mấy partition? ____
- COPY thường vs UNLOGGED: thời gian nạp 1 triệu dòng: ____ / ____
- Exclusion constraint chặn overlap: test thành công? có/không
- ROWS vs RANGE running sum khi trùng giá trị: khác nhau ở đâu?

## Day 7 — WAL / CDC / Tuning / Backup

- WAL sinh ra khi insert 100k dòng (logged table): ____
- WAL sinh ra khi insert 100k dòng (unlogged table): ____
- pg_dump + pg_restore: thời gian ____
- pg_basebackup: thời gian, dung lượng ____
- Trước tuning: cache hit % = ____, temp_files = ____
- Sau tuning (shared_buffers/work_mem/random_page_cost mới): cache hit % = ____
- io_method=sync vs worker trên seq scan: thời gian ____ / ____

### Cấu hình đã thử

| shared_buffers | work_mem | random_page_cost | Kết quả (query nào, thời gian) |
|---|---|---|---|
| 1GB | 8MB | 1.1 | baseline |
| | | | |
