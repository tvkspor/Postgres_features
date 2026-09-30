-- Day 5 — Transaction, isolation, lock
--
-- Isolation      | Dirty read | Non-repeatable | Phantom | Ghi chú Postgres
-- Read Uncommitted | Không    | Có             | Có      | Postgres map thành Read Committed
-- Read Committed   | Không    | Có             | Có      | Snapshot mới mỗi statement (default)
-- Repeatable Read  | Không    | Không          | Không   | Postgres mạnh hơn chuẩn (dùng snapshot)
-- Serializable     | Không    | Không          | Không   | SSI — optimistic, abort khi conflict

-- ===== Mở 2 session psql cạnh nhau cho các thí nghiệm dưới đây =====

-- Read Committed vs Repeatable Read
-- Session A:
--   BEGIN; SELECT sum(amount) FROM lab.t_small;
-- Session B:
--   UPDATE lab.t_small SET amount = amount + 100; -- autocommit
-- Session A:
--   SELECT sum(amount) FROM lab.t_small;   -- ĐỔI (non-repeatable read)
--   COMMIT;

-- Làm lại với REPEATABLE READ
-- Session A:
--   BEGIN ISOLATION LEVEL REPEATABLE READ;
--   SELECT sum(amount) FROM lab.t_small;
-- Session B update...
-- Session A:
--   SELECT sum(amount) FROM lab.t_small;   -- KHÔNG đổi
--   COMMIT;

-- Serialization failure (SSI)
CREATE TABLE lab.ssi(id int, val int);
INSERT INTO lab.ssi VALUES (1,10),(2,20);

-- Session A:                                  Session B:
-- BEGIN ISOLATION LEVEL SERIALIZABLE;          BEGIN ISOLATION LEVEL SERIALIZABLE;
-- UPDATE lab.ssi SET val=(SELECT sum(val) FROM lab.ssi) WHERE id=1;
--                                              UPDATE lab.ssi SET val=(SELECT sum(val) FROM lab.ssi) WHERE id=2;
-- COMMIT;                                      COMMIT;  -- ERROR 40001 could not serialize access
-- Bài học: dùng SERIALIZABLE thì app phải có retry loop cho SQLSTATE 40001.

-- Deadlock
-- Session A:                                       Session B:
-- BEGIN; UPDATE lab.t_small SET amount=1 WHERE id=1;
--                                                   BEGIN; UPDATE lab.t_small SET amount=1 WHERE id=2;
-- UPDATE lab.t_small SET amount=1 WHERE id=2; -- chờ
--                                                   UPDATE lab.t_small SET amount=1 WHERE id=1;
--                                                   -- ERROR: deadlock detected
-- Xem log container: docker logs pg-lab | grep -i deadlock

-- Job queue pattern — SKIP LOCKED
CREATE TABLE lab.jobs (
    id bigserial PRIMARY KEY,
    status text NOT NULL DEFAULT 'pending',
    payload jsonb,
    locked_at timestamptz
);
INSERT INTO lab.jobs(payload)
SELECT jsonb_build_object('n', g) FROM generate_series(1,1000) g;
CREATE INDEX ON lab.jobs(status) WHERE status = 'pending';

-- Chạy đồng thời ở 2 session -> không giẫm chân nhau, không chờ nhau
UPDATE lab.jobs SET status='running', locked_at=now()
WHERE id IN (
    SELECT id FROM lab.jobs WHERE status='pending'
    ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 10
)
RETURNING id, payload;

-- Quan sát lock
SELECT blocked.pid AS blocked_pid, blocked.query AS blocked_query,
       blocking.pid AS blocking_pid, blocking.query AS blocking_query,
       blocked.wait_event_type, blocked.wait_event
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks WHERE relation IS NOT NULL ORDER BY pid;

-- DDL lock — bài học production
-- An toàn (metadata only, nhanh, PG11+)
ALTER TABLE lab.fact_txn ADD COLUMN note text DEFAULT 'x';

-- Nguy hiểm: rewrite toàn bảng + ACCESS EXCLUSIVE
-- ALTER TABLE lab.fact_txn ALTER COLUMN branch_code TYPE varchar(20);

-- Luôn đặt timeout trước DDL trên production
SET lock_timeout = '3s';

-- Checkpoint Day 5:
-- 1. Postgres REPEATABLE READ khác chuẩn SQL chỗ nào?
-- 2. FOR UPDATE vs FOR UPDATE SKIP LOCKED vs FOR NO KEY UPDATE?
-- 3. Tại sao ALTER TABLE ... ADD COLUMN ... DEFAULT nhanh từ PG11 nhưng ALTER COLUMN TYPE vẫn chậm?
