--==============================================================
-- SQL 3: 產生 embedding、向量搜尋、向量索引
--==============================================================
-- 文件（AI Vector Search User's Guide）:
--   https://docs.oracle.com/en/database/oracle/oracle-database/23/vecse/
--
-- 對比 AWS：Aurora PostgreSQL + pgvector
--   vector(384) 欄位、<=> 運算子、CREATE INDEX ... USING hnsw

--------------------------------------------------------------
-- TODO SQL-4: 加 VECTOR 欄位並填入 embedding
--------------------------------------------------------------
--   ALTER TABLE docs ADD (embedding VECTOR(???, ???));
--     第一個參數：維度（02_onnx_model.sql 最後查到的數字）
--     第二個參數：元素格式（查文件有哪些；影響儲存空間與精度）
--
--   UPDATE docs SET embedding = ???;
--     用 VECTOR_EMBEDDING(DOC_MODEL USING <欄位> AS data)
--
-- 想一想：只 embed content，還是 title 加 content？對搜尋結果有什麼影響？

-- TODO SQL-4

ALTER TABLE docs ADD (embedding VECTOR(384, FLOAT32));

UPDATE docs SET embedding = VECTOR_EMBEDDING(DOC_MODEL USING content AS data);

COMMIT;

--------------------------------------------------------------
-- TODO SQL-5: 精確搜尋（exact search，全表掃描）
--------------------------------------------------------------
-- 問題："How long do I have to return a product?"
-- （文件裡沒有 return 這個字，但語意上應該找到 Refund policy）
--
--   SELECT id, title, ??? AS distance
--   FROM   docs
--   ORDER  BY distance
--   FETCH  FIRST 3 ROWS ONLY;
--
-- 距離用 VECTOR_DISTANCE(向量1, 向量2, 距離函式)：
--   - 向量 2 就是把問題丟進同一個模型
--   - 距離函式有 COSINE／EUCLIDEAN／DOT 等，文字 embedding 通常用哪個？

-- TODO SQL-5

SELECT 
id
, title
, VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(DOC_MODEL USING 'How long do I have to return a product?' AS data), 'COSINE') AS distance
FROM   docs
ORDER  BY distance
FETCH  FIRST 3 ROWS ONLY;

--------------------------------------------------------------
-- TODO SQL-6: 向量索引 + 近似搜尋（approximate search）
--------------------------------------------------------------
-- 兩種索引（查文件 "Create Vector Indexes"）：
--   HNSW：ORGANIZATION INMEMORY NEIGHBOR GRAPH   （記憶體內的圖，快、吃記憶體）
--   IVF ：ORGANIZATION NEIGHBOR PARTITIONS       （分群存在磁碟，省記憶體）
--
--   CREATE VECTOR INDEX docs_embedding_idx ON docs (embedding)
--     ORGANIZATION ???
--     DISTANCE ???                 -- 必須和查詢用的距離函式一致，否則不會走索引
--     WITH TARGET ACCURACY ???;
--
-- 查詢改成 FETCH APPROX FIRST 3 ROWS ONLY，再用 EXPLAIN PLAN 確認有走向量索引。
--
-- ⚠️ 12 筆資料時 optimizer 很可能仍選全表掃描，這是正常的；
--    重點是看懂執行計畫，以及知道 accuracy 與速度的取捨。

-- TODO SQL-6

CREATE VECTOR INDEX docs_embedding_idx ON docs (embedding)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
DISTANCE COSINE
WITH TARGET ACCURACY 90;

EXPLAIN PLAN FOR
SELECT 
id
, title
, VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(DOC_MODEL USING 'How long do I have to return a product?' AS data), 'COSINE') AS distance
FROM   docs
ORDER  BY distance
FETCH APPROX FIRST 3 ROWS ONLY;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

--------------------------------------------------------------
-- 建議練習：混合條件
--------------------------------------------------------------
-- 向量搜尋可以和一般 WHERE 條件寫在同一句 SQL（這是用關聯式資料庫當向量庫的賣點）。
-- 試著只在 title 含 'policy' 或 id < 8 的範圍內做向量搜尋。
