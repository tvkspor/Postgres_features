# Postgres Learn — Middle -> Advance (7 ngày)

## Chạy môi trường

```bash
docker compose up -d
docker exec -it pg-lab psql -U postgres -d lab
```

pgAdmin: http://localhost:5050 (a@b.c / lab) — chỉ dùng để xem ERD/browse schema,
không dùng cho lab (không có \timing, \watch, EXPLAIN đẹp).

## Thứ tự chạy

1. `sql/00_setup.sql` — chạy một lần, tạo extension + seed ~10 triệu dòng (mất 2-4 phút).
2. `sql/day1_storage_mvcc.sql`
3. `sql/day2_vacuum_bloat.sql`
4. `sql/day3_index_explain.sql`
5. `sql/day4_planner_stats_join.sql`
6. `sql/day5_transaction_lock.sql` — cần 2 psql session song song cho vài thí nghiệm.
7. `sql/day6_partition_load_json_window.sql`
8. `sql/day7_wal_cdc_tuning_backup.sql` — vài lệnh chạy trong bash (pg_dump, pg_basebackup), không phải psql.

Copy-paste từng khối vào psql thay vì chạy nguyên file một lượt — nhiều đoạn có
comment hướng dẫn mở 2 session hoặc chờ thao tác thủ công.

## Quy tắc

- Ghi số đo vào [notes.md](notes.md) sau mỗi thí nghiệm (before/after).
- Trả lời checkpoint questions cuối mỗi file bằng lời, không nhìn tài liệu.
- Plan lạ → paste vào https://explain.dalibo.com để xem cây trực quan.

## Dọn dẹp / làm lại từ đầu

```bash
docker compose down -v && docker compose up -d
```
