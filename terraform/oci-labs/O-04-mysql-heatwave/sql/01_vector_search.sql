-- ============================================================
-- SQL-1~4：MySQL 的 VECTOR 型別與向量搜尋（需透過 Bastion tunnel 連線）
-- 連線：mysql -h 127.0.0.1 -P 3306 -u dbadmin -p
--
-- ✅ multilingual-e5-small（384 維）在 Singapore 實測可用（2026-11-20）。
--    換模型時維度不同，要同步調整 VECTOR(N)。
-- ============================================================

CREATE DATABASE IF NOT EXISTS lab;
USE lab;

-- SQL-1: docs 表；embedding 維度要和模型一致
CREATE TABLE IF NOT EXISTS docs (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  content   TEXT NOT NULL,
  embedding VECTOR(384)
);

-- SQL-2: 範例文件（英文）
INSERT INTO docs (content) VALUES
  ('Autonomous Database supports private endpoints and access control lists.'),
  ('MySQL HeatWave accelerates analytic queries by offloading them to an in-memory cluster.'),
  ('A bastion service provides time-limited SSH tunnels into private subnets.'),
  ('High availability uses group replication across fault domains.'),
  ('Vector search finds rows whose embeddings are closest to a query embedding.'),
  ('Object storage pre-authenticated requests act like passwords and should expire.');

-- SQL-3: 用 HeatWave GenAI 產生 embedding（需 HeatWave cluster 已建立）
UPDATE docs
SET embedding = sys.ML_EMBED_ROW(content, JSON_OBJECT('model_id', 'multilingual-e5-small'))
WHERE embedding IS NULL;

-- SQL-4: 向量搜尋（cosine distance，越小越近）
SET @q = sys.ML_EMBED_ROW('How do I connect to a database in a private network?',
                          JSON_OBJECT('model_id', 'multilingual-e5-small'));

SELECT id, content, DISTANCE(embedding, @q, 'COSINE') AS dist
FROM docs
ORDER BY dist
LIMIT 3;

-- 想一想：這是 exact search（全表掃描算距離）。MySQL 沒有 HNSW／IVF 向量索引可用，
-- 資料量大時該怎麼辦？和 O-03 的 HNSW 比較。
