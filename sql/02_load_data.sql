/* =============================================================================
   FILE:        02_load_data.sql  (REVISED v2 — staging pattern)
   PROJECT:     Nova Bank — Credit Risk Analytics
   PURPOSE:     Bulk-load credit_risk_raw.csv vào dbo.credit_risk_raw qua
                staging table pattern (do CSV column order ≠ table column order).

   DEPENDENCIES: File 01 đã chạy thành công (credit_risk_raw tồn tại).
   PRODUCES:    dbo.credit_risk_raw populated với 32,581 rows, đúng types.

   ⚠️ TẠI SAO DÙNG STAGING PATTERN (thay vì BULK INSERT trực tiếp):
   ════════════════════════════════════════════════════════════════════════════
   CSV gốc có column order KHÔNG khớp với CREATE TABLE trong file 01:

     CSV order:    client_ID, age, income, home_own, emp_length, LOAN_INTENT,
                   loan_grade, ..., LOAN_STATUS (vị trí 10), ..., past_delinq (29)
     Table order:  client_ID, age, income, home_own, emp_length, GENDER,
                   marital, edu, emp_type, loan_intent, ..., LOAN_STATUS (29)

   BULK INSERT match cột theo VỊ TRÍ, không theo tên. Nếu insert trực tiếp:
     CSV col 6 ("PERSONAL") → table col 6 (gender VARCHAR(10)) → FAIL khi gặp
     "DEBTCONSOLIDATION" (17 ký tự) hoặc data lệch cột silently.

   Staging pattern:
     1. CREATE staging table với column order KHỚP CSV, all VARCHAR(50) (safe).
     2. BULK INSERT CSV → staging (positional match OK).
     3. INSERT INTO credit_risk_raw SELECT ... FROM staging với explicit
        column mapping + CAST sang đúng types.
     4. DROP staging (cleanup).

   Đây là pattern chuẩn ETL (Extract-Transform-Load) trong banking — recruiter
   sẽ recognize ngay. Hơn nữa staging làm "shock absorber": nếu CSV có row
   malformed, vẫn load được vào staging (VARCHAR forgiving) → debug dễ.
   ════════════════════════════════════════════════════════════════════════════

   ⚠️ PREREQUISITE: COPY CSV VÀO DOCKER CONTAINER (đã làm rồi)
       docker cp "<path>" SQL_Server_Docker:/var/opt/mssql/data/credit_risk_raw.csv

   INSIGHT MUỐN VERIFY sau khi chạy:
     • Staging: 32,581 rows.
     • Raw: 32,581 rows, đúng schema.
     • Null distribution: loan_int_rate=3,116 nulls, person_emp_length=895 nulls.
     • Default rate ≈ 21.82%.
   ============================================================================= */


USE NovaBank;
GO


-- ─── STEP 1: Truncate raw nếu đã có data ────────────────────────────────────
-- Ý nghĩa: idempotent — re-run file 02 không bị duplicate key error.
TRUNCATE TABLE dbo.credit_risk_raw;
GO

-- ─── STEP 2: Drop staging cũ nếu tồn tại ────────────────────────────────────
-- Ý nghĩa: cleanup từ lần chạy trước. Staging là "throwaway table" — không
-- cần preserve giữa các lần load.
IF OBJECT_ID('dbo.credit_risk_staging', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_staging;
GO

-- Reset staging (Reset lại step 1, 2 để debug step 6)
TRUNCATE TABLE dbo.credit_risk_raw;

IF OBJECT_ID('dbo.credit_risk_staging', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_staging;


-- ─── STEP 3: CREATE staging table khớp CSV column order ─────────────────────
-- Ý nghĩa cấu trúc:
--   • Column order GIỐNG HỆT CSV header (29 cột theo thứ tự xuất hiện).
--   • Mọi cột VARCHAR(50) NULL — đây là "lazy typing" cố ý:
--       - VARCHAR không fail khi gặp số (có thể CAST sau)
--       - VARCHAR(50) đủ rộng cho mọi giá trị trong dataset
--       - NULL allowed để handle empty CSV fields (sẽ NULLIF khi insert vào raw)
--   • Không cần PRIMARY KEY hay constraints — staging là tạm thời.
--
-- ANTI-PATTERN warning: trong production thực, tránh để staging tồn tại lâu
-- (risk: dev quên drop, table mọc bụi). Pattern chuẩn: tạo → load → transform
-- → drop trong cùng 1 batch. File này làm đúng vậy.

CREATE TABLE dbo.credit_risk_staging (
    -- ─── 29 columns theo CSV order ───
    client_ID                   VARCHAR(50) NULL,
    person_age                  VARCHAR(50) NULL,
    person_income               VARCHAR(50) NULL,
    person_home_ownership       VARCHAR(50) NULL,
    person_emp_length           VARCHAR(50) NULL,
    loan_intent                 VARCHAR(50) NULL,    -- CSV pos 6 (table pos 10)
    loan_grade                  VARCHAR(50) NULL,
    loan_amnt                   VARCHAR(50) NULL,
    loan_int_rate               VARCHAR(50) NULL,
    loan_status                 VARCHAR(50) NULL,    -- CSV pos 10 (table pos 29)
    loan_percent_income         VARCHAR(50) NULL,
    cb_person_default_on_file   VARCHAR(50) NULL,
    cb_person_cred_hist_length  VARCHAR(50) NULL,
    gender                      VARCHAR(50) NULL,    -- CSV pos 14 (table pos 6)
    marital_status              VARCHAR(50) NULL,
    education_level             VARCHAR(50) NULL,
    country                     VARCHAR(50) NULL,
    state                       VARCHAR(50) NULL,
    city                        VARCHAR(50) NULL,
    city_latitude               VARCHAR(50) NULL,
    city_longitude              VARCHAR(50) NULL,
    employment_type             VARCHAR(50) NULL,
    loan_term_months            VARCHAR(50) NULL,
    loan_to_income_ratio        VARCHAR(50) NULL,
    other_debt                  VARCHAR(50) NULL,
    debt_to_income_ratio        VARCHAR(50) NULL,
    open_accounts               VARCHAR(50) NULL,
    credit_utilization_ratio    VARCHAR(50) NULL,
    past_delinquencies          VARCHAR(50) NULL
);
GO


-- ─── STEP 4: BULK INSERT CSV → staging ──────────────────────────────────────
-- Ý nghĩa flags:
--   FIRSTROW = 2          : skip header
--   FIELDTERMINATOR = ','  : comma-separated
--   ROWTERMINATOR = '0x0a' : Unix LF (Mac Excel export thường LF)
--   CODEPAGE = '65001'     : UTF-8
--   TABLOCK                : load nhanh hơn (~3-5x)
--   MAXERRORS = 0          : fail fast nếu có lỗi
-- Note: nếu CSV được tạo trên Windows có thể là CRLF → đổi thành '0x0d0a'.

BULK INSERT dbo.credit_risk_staging
FROM '/var/opt/mssql/data/credit_risk_raw.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0d0a',
    TABLOCK,
    MAXERRORS = 0
);
GO


-- ─── STEP 5: Verify staging load ────────────────────────────────────────────
-- Insight: trước khi transform sang raw, confirm staging có đủ rows. Nếu
-- staging count < 32,581 → CSV bị truncate hoặc BULK INSERT skip rows do
-- format error → debug staging trước khi đi tiếp.

SELECT COUNT(*) AS staging_rows
FROM dbo.credit_risk_staging;
-- Expected: 32581


-- ─── STEP 6: TRANSFORM staging → credit_risk_raw ────────────────────────────
-- Ý nghĩa cấu trúc:
--   • INSERT INTO ... (column list) → explicit mapping by name, bypass positional.
--   • SELECT từ staging với CAST sang đúng types đã định trong file 01.
--   • NULLIF(col, ''): biến empty string thành NULL (BULK INSERT load CSV
--     empty fields thành '' chứ không phải NULL — cần convert trước CAST).
--
-- KEY MAPPINGS (CSV pos → Raw table pos):
--   CSV.loan_intent  (6)  → raw.loan_intent  (10)
--   CSV.loan_status (10) → raw.loan_status  (29)
--   CSV.gender      (14) → raw.gender       (6)
--   CSV.employment_type (22) → raw.employment_type (9)
-- ... tất cả handled bởi explicit column list bên dưới.

INSERT INTO dbo.credit_risk_raw (
    -- Column list theo order trong CREATE TABLE (file 01)
    client_ID,
    person_age,
    person_income,
    person_home_ownership,
    person_emp_length,
    gender,
    marital_status,
    education_level,
    employment_type,
    loan_intent,
    loan_grade,
    loan_amnt,
    loan_int_rate,
    loan_term_months,
    loan_percent_income,
    loan_to_income_ratio,
    other_debt,
    debt_to_income_ratio,
    open_accounts,
    credit_utilization_ratio,
    cb_person_default_on_file,
    cb_person_cred_hist_length,
    past_delinquencies,
    country,
    state,
    city,
    city_latitude,
    city_longitude,
    loan_status
)
SELECT
    -- ─── Identifier ───
    LTRIM(RTRIM(client_ID)),

    -- ─── Demographics ───
    CAST(LTRIM(RTRIM(person_age)) AS INT),
    CAST(LTRIM(RTRIM(person_income)) AS INT),
    LTRIM(RTRIM(person_home_ownership)),
    CAST(NULLIF(LTRIM(RTRIM(person_emp_length)), '') AS DECIMAL(5,2)),
    LTRIM(RTRIM(gender)),
    LTRIM(RTRIM(marital_status)),
    LTRIM(RTRIM(education_level)),
    LTRIM(RTRIM(employment_type)),

    -- ─── Loan Characteristics ───
    LTRIM(RTRIM(loan_intent)),
    LTRIM(RTRIM(loan_grade)),
    CAST(LTRIM(RTRIM(loan_amnt)) AS INT),
    CAST(NULLIF(LTRIM(RTRIM(loan_int_rate)), '') AS DECIMAL(5,2)),
    CAST(LTRIM(RTRIM(loan_term_months)) AS INT),

    -- ─── Risk Ratios ───
    CAST(LTRIM(RTRIM(loan_percent_income)) AS DECIMAL(6,4)),
    CAST(LTRIM(RTRIM(loan_to_income_ratio)) AS DECIMAL(20,16)),
    CAST(LTRIM(RTRIM(other_debt)) AS DECIMAL(18,4)),
    CAST(LTRIM(RTRIM(debt_to_income_ratio)) AS DECIMAL(20,16)),
    CAST(LTRIM(RTRIM(open_accounts)) AS INT),
    CAST(LTRIM(RTRIM(credit_utilization_ratio)) AS DECIMAL(20,16)),

    -- ─── Credit Bureau ───
    LTRIM(RTRIM(cb_person_default_on_file)),
    CAST(LTRIM(RTRIM(cb_person_cred_hist_length)) AS INT),
    CAST(LTRIM(RTRIM(past_delinquencies)) AS INT),

    -- ─── Geographic ───
    LTRIM(RTRIM(country)),
    LTRIM(RTRIM(state)),
    LTRIM(RTRIM(city)),
    CAST(LTRIM(RTRIM(city_latitude)) AS DECIMAL(9,6)),
    CAST(LTRIM(RTRIM(city_longitude)) AS DECIMAL(9,6)),

    -- ─── Target ───
    CAST(LTRIM(RTRIM(loan_status)) AS TINYINT)

FROM dbo.credit_risk_staging;
GO

-- Tìm ra lỗi xuống dòng khi chuyển từ csv sang

SELECT TOP 10
    loan_status,
    LEN(loan_status) AS len_value,
    DATALENGTH(loan_status) AS byte_length,
    ASCII(LEFT(loan_status, 1)) AS first_char_ascii,
    ASCII(RIGHT(loan_status, 1)) AS last_char_ascii
FROM dbo.credit_risk_staging
WHERE loan_status IS NOT NULL;

-- Tìm cột nào có giá trị numeric nhưng chứa whitespace ẩn
SELECT
    'person_age'    AS col, COUNT(*) AS bad_rows FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(person_age))) = 0 AND person_age IS NOT NULL
UNION ALL SELECT 'person_income',    COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(person_income))) = 0 AND person_income IS NOT NULL
UNION ALL SELECT 'loan_amnt',        COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(loan_amnt))) = 0 AND loan_amnt IS NOT NULL
UNION ALL SELECT 'loan_term_months', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(loan_term_months))) = 0 AND loan_term_months IS NOT NULL
UNION ALL SELECT 'open_accounts',    COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(open_accounts))) = 0 AND open_accounts IS NOT NULL
UNION ALL SELECT 'cb_person_cred_hist_length', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(cb_person_cred_hist_length))) = 0 AND cb_person_cred_hist_length IS NOT NULL
UNION ALL SELECT 'past_delinquencies', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(past_delinquencies))) = 0 AND past_delinquencies IS NOT NULL
UNION ALL SELECT 'loan_status',      COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(loan_status))) = 0 AND loan_status IS NOT NULL
UNION ALL SELECT 'loan_percent_income', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(loan_percent_income))) = 0 AND loan_percent_income IS NOT NULL
UNION ALL SELECT 'loan_to_income_ratio', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(loan_to_income_ratio))) = 0 AND loan_to_income_ratio IS NOT NULL
UNION ALL SELECT 'other_debt',       COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(other_debt))) = 0 AND other_debt IS NOT NULL
UNION ALL SELECT 'debt_to_income_ratio', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(debt_to_income_ratio))) = 0 AND debt_to_income_ratio IS NOT NULL
UNION ALL SELECT 'credit_utilization_ratio', COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(credit_utilization_ratio))) = 0 AND credit_utilization_ratio IS NOT NULL
UNION ALL SELECT 'city_latitude',    COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(city_latitude))) = 0 AND city_latitude IS NOT NULL
UNION ALL SELECT 'city_longitude',   COUNT(*) FROM dbo.credit_risk_staging WHERE ISNUMERIC(LTRIM(RTRIM(city_longitude))) = 0 AND city_longitude IS NOT NULL;

SELECT TOP 3
    past_delinquencies,
    LEN(past_delinquencies) AS len_val,
    DATALENGTH(past_delinquencies) AS byte_len,
    ASCII(RIGHT(past_delinquencies, 1)) AS last_char_ascii
FROM dbo.credit_risk_staging;

-- ─── STEP 7: Cleanup — drop staging ─────────────────────────────────────────
-- Ý nghĩa: staging đã hoàn thành nhiệm vụ. Drop để release storage + tránh
-- confusion sau này. Đây là good citizenship trong data warehouse.

DROP TABLE dbo.credit_risk_staging;
GO


-- ─── STEP 8: Update statistics ──────────────────────────────────────────────
UPDATE STATISTICS dbo.credit_risk_raw WITH FULLSCAN;
GO


-- ─── STEP 9: Sanity checks (4 queries verify load đúng) ─────────────────────


-- Check 1: Unique IDs khớp tổng rows
-- Insight: nếu duplicate → bug trong INSERT...SELECT hoặc CSV có dòng trùng.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT client_ID) AS unique_ids,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT client_ID) THEN 'PASS'
        ELSE 'FAIL — duplicate client_ID'
    END AS uniqueness_check
FROM dbo.credit_risk_raw;
-- Expected: 32581 / 32581 / PASS


-- Check 2: Null distribution của 2 cột có missing đã biết
-- Insight: phải khớp CHÍNH XÁC 3116 và 895. Nếu lệch:
--   < expected → NULLIF không hoạt động (có thể CSV dùng " " thay vì empty)
--   > expected → có row CSV thiếu values ngoài 2 cột này → cần debug
SELECT
    SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) AS loan_int_rate_nulls,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS emp_length_nulls
FROM dbo.credit_risk_raw;
-- Expected: 3116 / 895


-- Check 3: Default rate ≈ 21.82%
-- Insight: target distribution là "ngón tay cái" verify entire pipeline.
-- Sai số này = column mapping sai (loan_status bị nhét vào cột khác).
SELECT
    loan_status,
    COUNT(*) AS n,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM dbo.credit_risk_raw
GROUP BY loan_status
ORDER BY loan_status;
-- Expected:
--   0 | 25473 | 78.18
--   1 |  7108 | 21.82


-- Check 4: Spot-check 5 rows đầu — verify data đúng cột (BONUS, visual check)
-- Insight: nhìn mắt trần để confirm gender không phải "PERSONAL" (loan_intent),
-- loan_intent không phải "Male"/"Female", v.v. Đây là final defense layer
-- chống column mapping bug.
SELECT TOP 5
    client_ID,
    person_age,
    gender,                 -- phải là Male/Female
    employment_type,        -- phải là Full-time/Part-time/Self-employed/Unemployed
    loan_intent,            -- phải là PERSONAL/EDUCATION/...
    loan_grade,             -- phải là 1 ký tự A-G
    loan_status             -- phải là 0 hoặc 1
FROM dbo.credit_risk_raw
ORDER BY client_ID;
-- Expected row 1: CUST_00001, 22, Male, Self-employed, PERSONAL, D, 1


PRINT 'File 02 (revised) completed. Staging table dropped.';
PRINT 'Next: run 03_data_quality_checks.sql for full QA.';
GO
