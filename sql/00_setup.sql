-- Day 0 — Setup & seed data. Chạy một lần sau khi `docker compose up -d`.
-- docker exec -it pg-lab psql -U postgres -d lab -f /path/to/00_setup.sql
-- hoặc copy-paste từng khối vào psql.

\timing on
\pset pager off

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pageinspect;   -- xem bên trong heap page
CREATE EXTENSION IF NOT EXISTS pgstattuple;   -- đo bloat chính xác
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS tablefunc;

CREATE SCHEMA IF NOT EXISTS lab;
SET search_path = lab, public;

-- Bảng nhỏ để mổ xẻ từng tuple
CREATE TABLE t_small (id int PRIMARY KEY, name text, amount numeric(12,2));
INSERT INTO t_small
SELECT g, 'name_' || g, (random()*1000)::numeric(12,2)
FROM generate_series(1, 1000) g;

-- Bảng fact ~10 triệu dòng, có correlation thời gian (cho BRIN)
CREATE TABLE fact_txn (
    txn_id       bigserial PRIMARY KEY,
    txn_ts       timestamptz NOT NULL,
    customer_id  int NOT NULL,
    product_id   int NOT NULL,
    branch_code  text NOT NULL,
    status       text NOT NULL,
    amount       numeric(14,2) NOT NULL,
    payload      jsonb
);

INSERT INTO fact_txn (txn_ts, customer_id, product_id, branch_code, status, amount, payload)
SELECT
    '2024-01-01'::timestamptz + (g * interval '3 seconds'),   -- tăng đều -> correlation ~1
    (random()*200000)::int + 1,
    (random()*500)::int + 1,
    'BR' || lpad(((random()*80)::int + 1)::text, 3, '0'),
    (ARRAY['pending','settled','failed','reversed'])[1 + floor(random()*4)::int],
    (random()*5000)::numeric(14,2),
    jsonb_build_object(
        'channel', (ARRAY['mobile','web','atm','pos'])[1 + floor(random()*4)::int],
        'device',  md5(random()::text),
        'flags',   ARRAY['a','b','c']
    )
FROM generate_series(1, 10000000) g;

CREATE TABLE dim_customer (
    customer_id int PRIMARY KEY,
    full_name   text,
    city        text,
    province    text,
    segment     text
);
INSERT INTO dim_customer
SELECT g, 'cust_' || g,
       c.city, c.province,
       (ARRAY['mass','affluent','priority'])[1 + floor(random()*3)::int]
FROM generate_series(1, 200000) g
CROSS JOIN LATERAL (
    SELECT * FROM (VALUES
        ('Q1','HCM'),('Q3','HCM'),('Thu Duc','HCM'),
        ('Ba Dinh','HN'),('Cau Giay','HN'),
        ('Hai Chau','DN')
    ) v(city, province) ORDER BY random() LIMIT 1
) c;

VACUUM ANALYZE;

-- Kiểm tra:
-- SELECT pg_size_pretty(pg_total_relation_size('lab.fact_txn'));  -- ~2-3 GB
