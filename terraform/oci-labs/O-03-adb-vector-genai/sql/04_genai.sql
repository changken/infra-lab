--==============================================================
-- SQL 4: 接上 OCI Generative AI（Select AI、RAG）
--==============================================================
-- ADB 透過 DBMS_CLOUD_AI 呼叫 OCI Generative AI。Singapore 可用的 chat 模型
-- （2026-11-16 查得）：google.gemini-2.5-flash、gemini-2.5-flash-lite、gemini-2.5-pro。
--
-- Oracle 的 Select AI 範例頁有 OCI provider 搭配 Gemini 模型的 profile 範例；
-- 本 lab 尚未在 Singapore 實測，不通的處理方式見 README「卡關提示」。
--
-- 文件:
--   Select AI 範例    https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-examples.html
--   DBMS_CLOUD_AI     https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-ai-package.html
--
-- 對比 AWS：Aurora + Bedrock（aws_bedrock.invoke_model）、Bedrock Knowledge Bases。

--------------------------------------------------------------
-- TODO SQL-7: 建立 OCI 憑證（讓 ADB 以你的 API key 呼叫 GenAI）
--------------------------------------------------------------
-- 用 DBMS_CLOUD.CREATE_CREDENTIAL（OCI API key 版本）：
--   credential_name => 'OCI_GENAI_CRED'
--   user_ocid       => ???
--   tenancy_ocid    => ???
--   private_key     => ???    -- PEM 內容，去掉 BEGIN／END 行並接成一行
--   fingerprint     => ???
--   （值都在 ~/.oci/config 與它指到的私鑰檔）
--
-- ⚠️ 資安：
--   - 私鑰不要寫進這個檔案。用 SQLcl／SQL*Plus 的替代變數（&private_key）在執行時輸入，
--     或寫在 04_genai.local.sql（已 gitignore），用完刪掉
--   - 你的 API key 權限等於你本人（管理員）。正式環境應改用 resource principal
--     + dynamic group + 最小權限 policy；那屬於 envs/oci-governance 的範圍，本 lab 不做
--   - lab 結束 destroy ADB，憑證就跟著消失

-- 已改用 resource principal（見 main.tf 的 dynamic group + policy），不再建立 API key 憑證。
-- 以 ADMIN 執行一次：讓資料庫以 ADB 自己的身分取得短效 token。
-- 若先前建過 OCI_GENAI_CRED／GENAI profile，請先清掉：
--   EXEC DBMS_CLOUD_AI.DROP_PROFILE('GENAI', force => TRUE);
--   EXEC DBMS_CLOUD.DROP_CREDENTIAL('OCI_GENAI_CRED');
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL();
END;
/

--------------------------------------------------------------
-- TODO SQL-8: 建立 AI profile 並做 NL2SQL
--------------------------------------------------------------
-- 用 DBMS_CLOUD_AI.CREATE_PROFILE：
--   profile_name => 'GENAI'
--   attributes   => JSON，至少包含：
--     provider           ???    -- OCI Generative AI 對應哪個 provider 名稱
--     credential_name    ???
--     region             ???
--     oci_compartment_id ???    -- homelab compartment
--     model              ???    -- 上面列的 Gemini 模型之一
--     object_list        ???    -- 只開放 ORDERS 表給模型看
--
-- 想一想（資安）：
--   - object_list 沒限制的話，模型看得到哪些表的 metadata？
--   - 送給模型的是 schema 還是資料列？narrate 動作呢？

BEGIN
  -- TODO SQL-8
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'GENAI',
    attributes   => json_object(
      'provider'           value 'oci',
      'credential_name'    value 'OCI$RESOURCE_PRINCIPAL',
      'region'             value 'ap-singapore-1',
      'oci_compartment_id' value '<YOUR_COMPARTMENT_OCID>',
      'model'              value 'google.gemini-2.5-flash',
      'oci_apiformat'      value 'GENERIC',
      'object_list'        value json_array(json_object('owner' value 'ADMIN', 'name' value 'ORDERS'))
    )
  );
END;
/

-- 之後用 DBMS_CLOUD_AI.GENERATE 試不同 action（把 ??? 換掉）：
--   showsql ：只產生 SQL，不執行（先看這個，確認模型沒有亂寫）
--   runsql  ：產生並執行
--   narrate ：執行後用自然語言描述結果
--   chat    ：不看 schema，純聊天
--
-- SELECT DBMS_CLOUD_AI.GENERATE(
--          prompt       => 'What is the total revenue of delivered orders by category?',
--          profile_name => 'GENAI',
--          action       => '???')
-- FROM dual;

Select DBMS_CLOUD_AI.GENERATE(
         prompt       => 'What is the total revenue of delivered orders by category?',
         profile_name => 'GENAI',
         action       => 'showsql')
FROM dual;

--
-- 自己核對：revenue = quantity * unit_price，只算 status = 'DELIVERED'。
-- 模型產生的 SQL 和你手寫的結果一樣嗎？

--------------------------------------------------------------
-- TODO SQL-9: 手刻 RAG（retrieval 在 SQL，generation 交給模型）
--------------------------------------------------------------
-- 步驟：
--   1. 用 03_vector_search.sql 的查詢找出和問題最接近的 3 筆 docs
--   2. 把它們的 content 接成一段 context（LISTAGG）
--   3. 組 prompt：「只根據以下內容回答；內容裡沒有就說不知道」+ context + 問題
--   4. 用 DBMS_CLOUD_AI.GENERATE(action => 'chat') 送出
--
-- 測兩題：
--   'How long do I have to return a product?'    -- 文件內有答案
--   'What is the CEO''s phone number?'           -- 文件內沒有，模型應該拒答
--
-- 想一想（NFR）：
--   - prompt injection：如果 docs.content 裡被塞了一句「忽略以上指示」會怎樣？
--   - 延遲：retrieval 與 generation 各花多久？（SET TIMING ON）
--   - 這段邏輯該放在資料庫，還是放在你的後端 application service？

-- TODO SQL-9

SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => '只根據以下內容回答；內容裡沒有就說不知道。' ||
                         'Context: ' || context || ' Question: ' || question,
         profile_name => 'GENAI',
         action       => 'chat')
 FROM (
  SELECT
    LISTAGG(content, ' ') WITHIN GROUP (ORDER BY distance) AS context,
    'How long do I have to return a product?' AS question
  FROM (
    SELECT content,
           VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(DOC_MODEL USING 'How long do I have to return a product?' AS data), COSINE) AS distance
    FROM   docs
    ORDER  BY distance
    FETCH  FIRST 3 ROWS ONLY
  )
); 

--------------------------------------------------------------
-- 進階（選做）：讓 Select AI 自己做 RAG
--------------------------------------------------------------
-- DBMS_CLOUD_AI.CREATE_VECTOR_INDEX 可以直接對 Object Storage 的文件建向量索引，
-- 再用 action => 'narrate' 回答。查文件 "Select AI with RAG"，
-- 並比較它和 TODO SQL-9 手刻版本的差異（可控性、可測試性）。

--------------------------------------------------------------
-- SQL-9 第二題：文件外的問題（應拒答「不知道」）
--------------------------------------------------------------
SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => '只根據以下內容回答；內容裡沒有就說不知道。' ||
                         'Context: ' || context || ' Question: ' || question,
         profile_name => 'GENAI',
         action       => 'chat')
FROM (
  SELECT
    LISTAGG(content, ' ') WITHIN GROUP (ORDER BY distance) AS context,
    'What is the CEO''s phone number?' AS question
  FROM (
    SELECT content,
           VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(DOC_MODEL USING 'What is the CEO''s phone number?' AS data), COSINE) AS distance
    FROM   docs
    ORDER  BY distance
    FETCH  FIRST 3 ROWS ONLY
  )
);
