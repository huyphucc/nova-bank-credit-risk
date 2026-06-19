/* =============================================================================
   FILE:        01_create_tables.sql
   PROJECT:     Nova Bank — Credit Risk Analytics
   PURPOSE:     Tạo database NovaBank và bảng raw (landing zone) để chứa dữ
                liệu nguyên gốc từ CSV trước khi cleaning.

   DEPENDENCIES: None — đây là file đầu tiên chạy.
   PRODUCES:    Database "NovaBank" + bảng "dbo.credit_risk_raw" (rỗng).

   ARCHITECTURE NOTE:
   Dùng pattern "Raw → Clean → Mart":
     • credit_risk_raw    : data nguyên gốc, KHÔNG sửa đổi (audit trail)
     • credit_risk_clean  : data sau cleaning (file 04 sẽ tạo)
     • (future) marts     : aggregated tables cho dashboard (Power BI có thể
                            connect trực tiếp)
   Lý do tách raw/clean: nếu phát hiện lỗi cleaning logic sau này, có thể
   re-run file 04 mà không cần re-load CSV.

   INSIGHT MUỐN VERIFY:
   Sau khi chạy file này thành công, bảng raw đã có schema đúng — nghĩa là
   data type của 29 cột đã được khai báo chuẩn (INT, DECIMAL, VARCHAR, CHAR,
   TINYINT). Đây là bước "contract" giữa CSV và database: nếu CSV có giá trị
   không match schema (ví dụ chữ trong cột INT), file 02 sẽ fail → biết ngay
   có vấn đề.
   ============================================================================= */


-- ─── STEP 1: Tạo database NovaBank nếu chưa có ──────────────────────────────
-- Ý nghĩa: Mỗi project nên có database riêng để cô lập tables, dễ backup/drop
-- khi cần restart. Không dùng database "master" (default) vì master là system DB.

IF DB_ID('NovaBank') IS NULL
BEGIN
    CREATE DATABASE NovaBank;
    PRINT 'Database NovaBank created.';
END
ELSE
BEGIN
    PRINT 'Database NovaBank already exists — skipping creation.';
END
GO


-- Switch context sang NovaBank cho mọi statement phía dưới
USE NovaBank;
GO


-- ─── STEP 2: Drop bảng raw nếu đã tồn tại (idempotent) ──────────────────────
-- Ý nghĩa: "Idempotent" = chạy nhiều lần ra kết quả giống nhau. Cho phép re-run
-- file này mà không bị lỗi "table already exists". Cẩn thận: DROP sẽ xóa toàn
-- bộ data trong bảng cũ — nhưng vì raw sẽ được load lại từ CSV (file 02), nên
-- mất data không sao.

IF OBJECT_ID('dbo.credit_risk_raw', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_raw;
GO


-- ─── STEP 3: CREATE TABLE credit_risk_raw ───────────────────────────────────
-- Ý nghĩa cấu trúc:
--   • Mỗi cột có data type chính xác (không dùng VARCHAR cho mọi thứ — lazy!)
--   • PRIMARY KEY trên client_ID enforce uniqueness + tự động tạo clustered
--     index → query WHERE client_ID = 'X' sẽ rất nhanh.
--   • NOT NULL nơi không có missing trong dataset, NULL nơi có (loan_int_rate,
--     person_emp_length). Điều này document data quality ngay trong schema.
--   • CHECK constraint trên loan_status enforce business rule (binary 0/1).
--   • Decimal precision phù hợp với range thực tế của data (đã inspect từ
--     Excel trước đó):
--       - loan_percent_income: range [0, 0.83] với 4 decimals → DECIMAL(6,4)
--       - các ratio chính xác cao (16 decimals): DECIMAL(20, 16)
--       - other_debt: max 1.18M → DECIMAL(18, 4) đủ rộng

CREATE TABLE dbo.credit_risk_raw (

    -- ═══ IDENTIFIER ═══════════════════════════════════════════════════════
    client_ID                   VARCHAR(20)     NOT NULL,
        -- Mã định danh khách hàng. Format "CUST_XXXXX" → 10 ký tự, dùng
        -- VARCHAR(20) để có buffer. Sẽ là PRIMARY KEY (định nghĩa cuối).

    -- ═══ DEMOGRAPHICS ═════════════════════════════════════════════════════
    person_age                  INT             NOT NULL,
        -- Tuổi (năm). Min=20, Max=144 (có outliers, sẽ filter trong file 04).

    person_income               INT             NOT NULL,
        -- Thu nhập năm (USD). Min=4K, Max=6M (có outliers, sẽ winsorize P99).

    person_home_ownership       VARCHAR(10)     NOT NULL,
        -- 4 giá trị: RENT, OWN, MORTGAGE, OTHER. VARCHAR(10) đủ cho dài nhất.

    person_emp_length           DECIMAL(5,2)    NULL,
        -- Số năm làm việc. ⚠️ Có 895 NULL (2.75%). Max=123 (cần cap).
        -- DECIMAL(5,2) cho phép giá trị như 12.50, max 999.99.

    gender                      VARCHAR(10)     NOT NULL,
        -- Male / Female. ⚠️ Protected variable — exclude khỏi model (ECOA).

    marital_status              VARCHAR(15)     NOT NULL,
        -- Single, Married, Divorced, Widowed. ⚠️ Protected variable.

    education_level             VARCHAR(15)     NOT NULL,
        -- High School, Bachelor, Master, PhD. ⚠️ Protected variable.

    employment_type             VARCHAR(20)     NOT NULL,
        -- Full-time, Part-time, Self-employed, Unemployed.

    -- ═══ LOAN CHARACTERISTICS ═════════════════════════════════════════════
    loan_intent                 VARCHAR(20)     NOT NULL,
        -- PERSONAL, EDUCATION, MEDICAL, VENTURE, HOMEIMPROVEMENT,
        -- DEBTCONSOLIDATION. Dài nhất 17 ký tự → VARCHAR(20) đủ.

    loan_grade                  CHAR(1)         NOT NULL,
        -- A → G. CHAR(1) fixed-width vì luôn đúng 1 ký tự, tiết kiệm storage
        -- hơn VARCHAR(1). ⚠️ OUTPUT của scoring hiện tại — circular logic,
        -- exclude khỏi model mới.

    loan_amnt                   INT             NOT NULL,
        -- Số tiền vay (USD). Range 500 - 35,000. INT đủ rộng.

    loan_int_rate               DECIMAL(5,2)    NULL,
        -- Lãi suất (%). ⚠️ Có 3,116 NULL (9.56%). Range 5.42 - 23.22.

    loan_term_months            INT             NOT NULL,
        -- Kỳ hạn (tháng). 4 giá trị: 12, 24, 36, 60.

    -- ═══ RISK RATIOS ══════════════════════════════════════════════════════
    loan_percent_income         DECIMAL(6,4)    NOT NULL,
        -- LPI = loan_amnt / income. Range [0, 0.83]. 4 chữ số sau dấu phẩy.

    loan_to_income_ratio        DECIMAL(20,16)  NOT NULL,
        -- ⚠️ REDUNDANT với loan_percent_income (expected corr ≈ 1.0).
        -- File 04 sẽ drop sau khi verify trong file 03.
        -- DECIMAL(20,16) vì data gốc lưu 16 decimals.

    other_debt                  DECIMAL(18,4)   NOT NULL,
        -- Tổng nợ khác (USD). Range 225 - 1,187,999. Right-skew nặng.

    debt_to_income_ratio        DECIMAL(20,16)  NOT NULL,
        -- DTI. Range [0.065, 1.054]. Max > 1.0 nghĩa là nợ vượt thu nhập.

    open_accounts               INT             NOT NULL,
        -- Số tài khoản tín dụng đang mở. Range 0 - 15.

    credit_utilization_ratio    DECIMAL(20,16)  NOT NULL,
        -- ⚠️ Phân phối đều [0.05, 0.95], corr ≈ 0 với target → nghi synthetic
        -- artifact (H12). Sẽ test trong file 03 + Colab notebook.

    -- ═══ CREDIT BUREAU ════════════════════════════════════════════════════
    cb_person_default_on_file   CHAR(1)         NOT NULL,
        -- Y / N. CHAR(1) tiết kiệm storage.

    cb_person_cred_hist_length  INT             NOT NULL,
        -- Độ dài lịch sử tín dụng (năm). Range 2 - 30.

    past_delinquencies          INT             NOT NULL,
        -- Số lần chậm trả quá khứ. Range 0 - 6.
        -- ⚠️ corr ≈ 0 với target → nghi synthetic artifact (H12).

    -- ═══ GEOGRAPHIC ═══════════════════════════════════════════════════════
    country                     VARCHAR(20)     NOT NULL,
        -- USA, UK, Canada (3 giá trị).

    state                       VARCHAR(20)     NOT NULL,
        -- 9 bang/tỉnh/vùng (mix US states + Canadian provinces + UK regions).

    city                        VARCHAR(30)     NOT NULL,
        -- 18 thành phố. Dài nhất "San Francisco" 13 ký tự → VARCHAR(30) dư.

    city_latitude               DECIMAL(9,6)    NOT NULL,
        -- Vĩ độ. DECIMAL(9,6) chuẩn cho GPS coordinates (6 decimals ≈ 11cm).

    city_longitude              DECIMAL(9,6)    NOT NULL,
        -- Kinh độ.

    -- ═══ TARGET ═══════════════════════════════════════════════════════════
    loan_status                 TINYINT         NOT NULL
                                CHECK (loan_status IN (0, 1)),
        -- 0 = Non-default (78.18%), 1 = Default (21.82%).
        -- TINYINT (1 byte) thay vì INT (4 bytes) — tiết kiệm storage cho
        -- binary target, đồng thời signal "đây là binary" cho người đọc.
        -- CHECK constraint từ chối bất kỳ value nào khác 0/1 → data integrity.

    -- ═══ CONSTRAINTS ══════════════════════════════════════════════════════
    CONSTRAINT PK_credit_risk_raw PRIMARY KEY CLUSTERED (client_ID)
        -- PRIMARY KEY clustered: tự động tạo index trên client_ID, đồng thời
        -- sắp xếp physical storage theo client_ID. Query WHERE client_ID = 'X'
        -- sẽ là O(log N) thay vì O(N) full table scan.
);
GO


-- ─── STEP 4: Verify table đã được tạo đúng schema ───────────────────────────
-- Insight muốn thấy: 29 columns, đúng data types, có 1 PRIMARY KEY trên
-- client_ID, 1 CHECK constraint trên loan_status.

-- Query 1: Đếm số columns
SELECT COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'credit_risk_raw'
  AND TABLE_SCHEMA = 'dbo';
-- Expected: 29


-- Query 2: List toàn bộ columns với data type
-- Insight: scan nhanh để confirm không có cột nào bị nhầm type (ví dụ
-- loan_status không được là FLOAT, person_age không được là VARCHAR).
SELECT
    ORDINAL_POSITION AS pos,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH AS max_len,
    NUMERIC_PRECISION AS num_prec,
    NUMERIC_SCALE AS num_scale,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'credit_risk_raw'
  AND TABLE_SCHEMA = 'dbo'
ORDER BY ORDINAL_POSITION;


-- Query 3: Confirm PRIMARY KEY và CHECK constraints
SELECT
    tc.CONSTRAINT_TYPE,
    tc.CONSTRAINT_NAME,
    cc.CHECK_CLAUSE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
LEFT JOIN INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc
    ON tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
WHERE tc.TABLE_NAME = 'credit_risk_raw';
-- Expected: 1 PRIMARY KEY + 1 CHECK (loan_status IN (0,1))


PRINT 'File 01 completed. Next: run 02_load_data.sql to populate raw table.';
GO
