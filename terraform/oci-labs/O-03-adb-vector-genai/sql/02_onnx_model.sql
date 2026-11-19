--==============================================================
-- SQL 2: 把 ONNX embedding 模型載入資料庫
--==============================================================
-- Singapore 的 OCI Generative AI 沒有 embedding 模型（2026-11-16 查得只有 Gemini chat），
-- 所以 embedding 在資料庫內做：模型載入後，用 SQL 函式就能產生向量，不必呼叫外部服務。
--
-- 前置：models/ 內已放好 .onnx 並 terraform apply 上傳（見 README「準備 ONNX 模型」）。
-- 把 <PAR_BASE_URL>、<MODEL_FILE> 換成實際值，另存成 02_onnx_model.local.sql。
--
-- 文件:
--   Oracle 預建模型說明（含下載連結與載入範例）
--     https://blogs.oracle.com/machinelearning+selectai/use-our-prebuilt-onnx-model-now-available-for-embedding-generation-in-oracle-database-23ai
--   SQL Quick Start（模型載入到搜尋的完整流程）
--     https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/sql-quick-start-using-vector-embedding-model-uploaded-database.html

--------------------------------------------------------------
-- TODO SQL-2: 下載模型檔到資料庫的目錄物件
--------------------------------------------------------------
-- 用 DBMS_CLOUD.GET_OBJECT：
--   object_uri     => ???    -- <PAR_BASE_URL>models/<MODEL_FILE>
--   directory_name => ???    -- ADB 內建、你有權限寫入的目錄物件（查 ALL_DIRECTORIES）
--
-- ADB 沒有 OS 存取權，所以「把檔案放到 DB server」只能透過目錄物件。

BEGIN
  -- TODO SQL-2
  DBMS_CLOUD.GET_OBJECT(
    object_uri     => '<PAR_BASE_URL>models/all_MiniLM_L12_v2.onnx',
    directory_name => 'DATA_PUMP_DIR',
    file_name      => 'all_MiniLM_L12_v2.onnx'
  );
END;
/

-- 確認檔案到了（把 ??? 換成你用的目錄物件名稱）
-- SELECT object_name, bytes FROM DBMS_CLOUD.LIST_FILES('???');

--------------------------------------------------------------
-- TODO SQL-3: 載入成資料庫內的模型
--------------------------------------------------------------
-- 用 DBMS_VECTOR.LOAD_ONNX_MODEL：
--   directory  => ???
--   file_name  => ???
--   model_name => 'DOC_MODEL'
--
-- ⚠️ 注意：
--   - Oracle 提供的「augmented」模型已內含 tokenizer 與 metadata，不必另外給 metadata；
--     自己從 Hugging Face 轉出的 ONNX 通常不能直接載入
--   - 想重來先 DBMS_VECTOR.DROP_ONNX_MODEL('DOC_MODEL')

BEGIN
  -- TODO SQL-3
  DBMS_VECTOR.LOAD_ONNX_MODEL(
    directory  => 'DATA_PUMP_DIR',
    file_name  => 'all_MiniLM_L12_v2.onnx',
    model_name => 'DOC_MODEL'
  );
END;
/

--------------------------------------------------------------
-- 驗證
--------------------------------------------------------------
SELECT model_name, mining_function, algorithm
FROM   user_mining_models;

-- 產生一個向量，並看維度（之後建 VECTOR 欄位要用到這個數字）
SELECT VECTOR_DIMENSION_COUNT(VECTOR_EMBEDDING(DOC_MODEL USING 'hello world' AS data)) AS dims
FROM   dual;
