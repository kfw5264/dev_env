-- 首次初始化时自动安装常用扩展（作用于 POSTGRES_DB 指定的 dev 库）

-- 向量检索
CREATE EXTENSION IF NOT EXISTS vector;

-- contrib 常用扩展
CREATE EXTENSION IF NOT EXISTS pg_trgm;        -- 模糊/相似度匹配
CREATE EXTENSION IF NOT EXISTS pgcrypto;       -- 加密函数（gen_random_uuid）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";    -- UUID 生成
CREATE EXTENSION IF NOT EXISTS hstore;         -- 键值类型
CREATE EXTENSION IF NOT EXISTS citext;         -- 大小写不敏感文本
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS ltree;          -- 树形路径

-- 注意：PostGIS 不在此镜像内，如需要请改用 postgis/postgis 镜像
