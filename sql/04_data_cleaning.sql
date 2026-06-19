/* =============================================================================
   FILE:        04_data_cleaning.sql
   PROJECT:     Nova Bank — Credit Risk Analytics
   PURPOSE:     Transform credit_risk_raw → credit_risk_clean theo Data
                Preprocessing Checklist. Đây là FILE QUAN TRỌNG NHẤT trong
                pipeline cleaning — mọi business decision về data được lưu ở
                đây với comment giải thích.

   DEPENDENCIES: File 02 đã load raw, File 03 đã verify data quality.
   PRODUCES:    dbo.credit_risk_clean với 32,576 rows (raw 32,581 - 5 outliers)
                và 38 columns (29 original - 1 dropped + 10 derived).

   TRANSFORMATIONS IMPLEMENTED (theo Preprocessing Checklist):
     T1. Remove age > 100 outliers (5 rows)
     T2. Cap person_emp_length tại 50 + impute missing (Unemployed=0, else median)
     T3. Winsorize person_income tại P99
     T4. Median-impute loan_int_rate by loan_grade
     T5. Drop loan_to_income_ratio (redundant với loan_percent_income)

   DERIVED COLUMNS CREATED (10):
     D1. age_bucket             (5 categorical bins cho WoE/IV)
     D2. income_bucket          (4 categorical bins)
     D3. lpi_bucket             (5 quantile bins cho threshold finding H5)
     D4. dti_bucket             (5 quantile bins cho H6)
     D5. log_income             (log transform cho linearization)
     D6. log_other_debt         (log transform)
     D7. is_homeowner           (binary OWN/MORTGAGE = 1)
     D8. thin_file              (binary cred_hist < 3 năm)
     D9. has_prior_default      (binary cb_default = Y)
    D10. is_subprime            (binary loan_grade ∈ {D,E,F,G})

   ARCHITECTURE:
   Dùng 1 INSERT...SELECT lớn với CTE (Common Table Expression) để compute
   tất cả thresholds/medians 1 lần, rồi apply transformations. Hiệu quả hơn
   chạy nhiều UPDATE statements (mỗi UPDATE quét bảng 1 lần).

   ANTI-BIAS COMMITMENTS (từ handoff):
     • Threshold tìm từ DATA TRƯỚC, regulation benchmark SAU (file 04 chỉ tạo
       buckets, không hard-code ngưỡng 0.43 QM Rule).
     • Protected variables (gender, marital_status, education_level) GIỮ trong
       clean table để fairness audit, KHÔNG drop. Quyết định exclude chỉ xảy
       ra ở modeling stage (Colab notebook).
     • loan_grade GIỮ vì cần validate model mới vs scoring hiện tại — nhưng
       trong Colab sẽ exclude khỏi feature set.
     • past_delinquencies & credit_utilization_ratio GIỮ — không drop vội dù
       corr ≈ 0. Sẽ test WoE/IV trong Colab trước khi kết luận (H12).

   INSIGHT MUỐN VERIFY sau khi chạy file này:
     ✓ Row count: 32,576 (32,581 - 5 age outliers)
     ✓ Zero NULL trong loan_int_rate và person_emp_length (sau impute)
     ✓ max(person_income) ≈ P99 (sau winsorize)
     ✓ max(person_emp_length) = 50 (sau cap)
     ✓ Không còn cột loan_to_income_ratio
     ✓ 10 derived columns đều populated, không null
   ============================================================================= */


USE NovaBank;
GO


-- ─── STEP 1: Drop credit_risk_clean nếu đã tồn tại (idempotent) ─────────────
IF OBJECT_ID('dbo.credit_risk_clean', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_clean;
GO


-- ─── STEP 2: Create credit_risk_clean với schema mở rộng ────────────────────
-- Ý nghĩa: Tạo trước table với schema target (29 - 1 + 10 = 38 cols), sau đó
-- INSERT từ raw với transformations. Tách CREATE TABLE và INSERT giúp dễ
-- review schema mà không bị distract bởi transformation logic.

CREATE TABLE dbo.credit_risk_clean (

    -- ═══ IDENTIFIER (giữ nguyên) ═══════════════════════════════════════════
    client_ID                   VARCHAR(20)     NOT NULL,

    -- ═══ DEMOGRAPHICS (8 cols original + 3 derived) ════════════════════════
    person_age                  INT             NOT NULL,
    person_income               INT             NOT NULL,    -- winsorized
    person_home_ownership       VARCHAR(10)     NOT NULL,
    person_emp_length           DECIMAL(5,2)    NOT NULL,    -- capped + imputed
    gender                      VARCHAR(10)     NOT NULL,    -- ⚠ protected
    marital_status              VARCHAR(15)     NOT NULL,    -- ⚠ protected
    education_level             VARCHAR(15)     NOT NULL,    -- ⚠ protected
    employment_type             VARCHAR(20)     NOT NULL,

    -- Derived demographics
    age_bucket                  VARCHAR(10)     NOT NULL,    -- D1
    income_bucket               VARCHAR(15)     NOT NULL,    -- D2
    log_income                  DECIMAL(10,6)   NOT NULL,    -- D5

    -- ═══ LOAN CHARACTERISTICS (5 cols + flags) ═════════════════════════════
    loan_intent                 VARCHAR(20)     NOT NULL,
    loan_grade                  CHAR(1)         NOT NULL,    -- ⚠ circular
    loan_amnt                   INT             NOT NULL,
    loan_int_rate               DECIMAL(5,2)    NOT NULL,    -- imputed
    loan_term_months            INT             NOT NULL,

    -- Derived loan
    is_subprime                 BIT             NOT NULL,    -- D10

    -- ═══ RISK RATIOS (6 - 1 dropped = 5 cols + 2 buckets + 1 log) ══════════
    loan_percent_income         DECIMAL(6,4)    NOT NULL,
    -- loan_to_income_ratio DROPPED (redundant)
    other_debt                  DECIMAL(18,4)   NOT NULL,
    log_other_debt              DECIMAL(12,6)   NOT NULL,    -- D6
    debt_to_income_ratio        DECIMAL(20,16)  NOT NULL,
    open_accounts               INT             NOT NULL,
    credit_utilization_ratio    DECIMAL(20,16)  NOT NULL,

    -- Derived ratios
    lpi_bucket                  VARCHAR(15)     NOT NULL,    -- D3
    dti_bucket                  VARCHAR(15)     NOT NULL,    -- D4

    -- ═══ CREDIT BUREAU (3 cols + 2 derived) ════════════════════════════════
    cb_person_default_on_file   CHAR(1)         NOT NULL,
    cb_person_cred_hist_length  INT             NOT NULL,
    past_delinquencies          INT             NOT NULL,

    -- Derived bureau
    has_prior_default           BIT             NOT NULL,    -- D9
    thin_file                   BIT             NOT NULL,    -- D8

    -- ═══ GEOGRAPHIC (5 cols, giữ nguyên — cho Power BI map) ════════════════
    country                     VARCHAR(20)     NOT NULL,
    state                       VARCHAR(20)     NOT NULL,
    city                        VARCHAR(30)     NOT NULL,
    city_latitude               DECIMAL(9,6)    NOT NULL,
    city_longitude              DECIMAL(9,6)    NOT NULL,

    -- Derived geographic
    is_homeowner                BIT             NOT NULL,    -- D7

    -- ═══ TARGET ═══════════════════════════════════════════════════════════
    loan_status                 TINYINT         NOT NULL
                                CHECK (loan_status IN (0, 1)),

    CONSTRAINT PK_credit_risk_clean PRIMARY KEY CLUSTERED (client_ID)
);
GO


-- ─── STEP 3: INSERT với transformations ─────────────────────────────────────
-- CẤU TRÚC LOGIC:
--   thresholds CTE → compute global P99, median by grade, median by emp_type
--   transformed CTE → apply T1-T5 + tạo derived columns
--   INSERT từ transformed vào credit_risk_clean
--
-- WINDOW FUNCTIONS dùng nhiều ở đây vì hiệu quả hơn subquery — chỉ scan table
-- 1 lần để compute thresholds rồi apply per-row.

WITH

-- ─────────────────────────────────────────────────────────────────────────
-- CTE 1: Compute global thresholds for winsorization
-- ─────────────────────────────────────────────────────────────────────────
-- Ý nghĩa: P99 của income để winsorize (T3). DISTINCT vì PERCENTILE_CONT
-- không phải aggregate, mà window function → mỗi row trả về cùng giá trị
-- → DISTINCT collapse về 1 row.

thresholds AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY person_income) OVER ()
            AS p99_income
    FROM dbo.credit_risk_raw
),

-- ─────────────────────────────────────────────────────────────────────────
-- CTE 2: Compute median int_rate by loan_grade (cho imputation T4)
-- ─────────────────────────────────────────────────────────────────────────
-- Ý nghĩa: tính median loan_int_rate cho mỗi grade A-G, dùng để impute NULL.
-- Lý do impute by grade (không global median): preserve risk-pricing
-- relationship — grade D vẫn có rate cao hơn grade A sau imputation.
grade_medians AS (
    SELECT DISTINCT
        loan_grade,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY loan_int_rate)
            OVER (PARTITION BY loan_grade)
            AS median_rate_by_grade
    FROM dbo.credit_risk_raw
    WHERE loan_int_rate IS NOT NULL  -- chỉ tính median trên non-null values
),

-- CTE 3: Compute median emp_length by employment_type (cho imputation T2)
-- ─────────────────────────────────────────────────────────────────────────
-- Ý nghĩa: median emp_length cho TẤT CẢ groups bao gồm Unemployed.
-- Q8 finding: Unemployed null% = 2.21% ≈ các nhóm khác (2.77-2.80%), và
-- avg_emp_len của Unemployed = 4.73 năm ≈ Full-time (4.79). Đây là synthetic
-- data artifact — Unemployed borrowers vẫn được assign employment history.
-- → KHÔNG impute Unemployed = 0 (sẽ tạo outlier nhân tạo).
-- → Impute tất cả missing bằng median of SAME employment_type group.
emp_medians AS (
    SELECT DISTINCT
        employment_type,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY person_emp_length)
            OVER (PARTITION BY employment_type)
            AS median_emp_by_type
    FROM dbo.credit_risk_raw
    WHERE person_emp_length IS NOT NULL
      AND person_emp_length <= 50     -- exclude outliers khi tính median
),

-- ─────────────────────────────────────────────────────────────────────────
-- CTE 4: Compute LPI và DTI quantile boundaries (cho derived buckets D3, D4)
-- ─────────────────────────────────────────────────────────────────────────
-- Ý nghĩa: dùng 5 quantile bins để chia LPI và DTI thành Q1-Q5. Đây là input
-- cho WoE/IV trong Colab + cho threshold finding H5/H6.
-- LƯU Ý: Compute trên data ĐÃ filter age outliers (subquery nested) để
-- threshold không bị distort bởi 5 rows bất thường.
quantiles AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.20) WITHIN GROUP (ORDER BY loan_percent_income) OVER () AS lpi_q1,
        PERCENTILE_CONT(0.40) WITHIN GROUP (ORDER BY loan_percent_income) OVER () AS lpi_q2,
        PERCENTILE_CONT(0.60) WITHIN GROUP (ORDER BY loan_percent_income) OVER () AS lpi_q3,
        PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY loan_percent_income) OVER () AS lpi_q4,
        PERCENTILE_CONT(0.20) WITHIN GROUP (ORDER BY debt_to_income_ratio) OVER () AS dti_q1,
        PERCENTILE_CONT(0.40) WITHIN GROUP (ORDER BY debt_to_income_ratio) OVER () AS dti_q2,
        PERCENTILE_CONT(0.60) WITHIN GROUP (ORDER BY debt_to_income_ratio) OVER () AS dti_q3,
        PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY debt_to_income_ratio) OVER () AS dti_q4
    FROM dbo.credit_risk_raw
    WHERE person_age <= 100  -- T1 filter applied
),

-- ─────────────────────────────────────────────────────────────────────────
-- CTE 5: Main transformation — apply T1-T5 và compute derived columns
-- ─────────────────────────────────────────────────────────────────────────
-- Đây là CTE chính. JOIN với 4 CTE trước để lấy thresholds, sau đó apply
-- transformations per-row qua CASE WHEN.
transformed AS (
    SELECT
        r.client_ID,

        -- ═══ Demographics (T1 filter applied via WHERE phía dưới) ══════════
        r.person_age,

        -- T3: Winsorize income tại P99
        -- Insight: cap top 1% income về P99 value. Linear models sẽ không bị
        -- distort bởi 1 borrower có income 6M USD (outlier kéo mean lệch).
        CAST(
            CASE
                WHEN r.person_income > t.p99_income THEN t.p99_income
                ELSE r.person_income
            END
        AS INT) AS person_income,

        r.person_home_ownership,

        -- T2: Cap emp_length tại 50, impute NULL
        -- Logic 2-tầng (revised sau Q8 findings):
        --   Q8 data: Unemployed null% = 2.21% ≈ nhóm khác (2.77-2.80%)
        --            Unemployed avg_emp_len = 4.73 ≈ Full-time (4.79)
        --   → Synthetic artifact: Unemployed vẫn có employment history trong dataset.
        --   → Impute TẤT CẢ missing = median of SAME employment_type group.
        --   1. NULL → median by employment_type (bao gồm cả Unemployed group)
        --   2. Non-NULL > 50 → cap tại 50
        --   3. Non-NULL <= 50 → giữ nguyên
        CAST(
            CASE
                WHEN r.person_emp_length IS NULL THEN em.median_emp_by_type
                WHEN r.person_emp_length > 50 THEN 50
                ELSE r.person_emp_length
            END
        AS DECIMAL(5,2)) AS person_emp_length,

        r.gender,
        r.marital_status,
        r.education_level,
        r.employment_type,

        -- D1: age_bucket — 5 bins cho WoE/IV
        -- Insight: hypothesis H1 cho rằng trẻ tuổi có default cao hơn. Bins
        -- này cho phép test bằng default rate per bucket trong Colab.
        CASE
            WHEN r.person_age <= 25 THEN '20-25'
            WHEN r.person_age <= 30 THEN '26-30'
            WHEN r.person_age <= 40 THEN '31-40'
            WHEN r.person_age <= 55 THEN '41-55'
            ELSE '56+'
        END AS age_bucket,

        -- D2: income_bucket — 4 bins
        -- Insight: dùng income đã winsorize. Bins dựa trên domain (US median
        -- household income ≈ 70K), Vietnamese reader có thể dịch sang VND
        -- cho Power BI dashboard nếu cần.
        CASE
            WHEN CASE WHEN r.person_income > t.p99_income THEN t.p99_income
                      ELSE r.person_income END < 30000 THEN 'Low'
            WHEN CASE WHEN r.person_income > t.p99_income THEN t.p99_income
                      ELSE r.person_income END < 75000 THEN 'Mid'
            WHEN CASE WHEN r.person_income > t.p99_income THEN t.p99_income
                      ELSE r.person_income END < 150000 THEN 'Upper'
            ELSE 'High'
        END AS income_bucket,

        -- D5: log_income — natural log của (income + 1)
        -- Insight: linearize right-skewed distribution. Logistic regression
        -- assume linearity of log-odds → log transform giúp coefficient ổn định.
        -- LOG(x + 1) thay vì LOG(x) để handle income = 0 (mặc dù min = 4K).
        CAST(LOG(
            CAST(
                CASE WHEN r.person_income > t.p99_income THEN t.p99_income
                     ELSE r.person_income END + 1
            AS FLOAT)
        ) AS DECIMAL(10,6)) AS log_income,

        -- ═══ Loan Characteristics ═════════════════════════════════════════
        r.loan_intent,
        r.loan_grade,
        r.loan_amnt,

        -- T4: Median-impute loan_int_rate by loan_grade
        -- Insight: preserve risk-pricing relationship. Grade A median rate
        -- khác grade G median rate, impute by group giữ structure này.
        CAST(
            COALESCE(r.loan_int_rate, gm.median_rate_by_grade)
        AS DECIMAL(5,2)) AS loan_int_rate,

        r.loan_term_months,

        -- D10: is_subprime — binary cho loan_grade ∈ {D,E,F,G}
        -- Insight: subprime tier theo industry convention. Dùng cho policy
        -- simulation H11 (reject high-risk scenarios).
        CAST(
            CASE WHEN r.loan_grade IN ('D', 'E', 'F', 'G') THEN 1 ELSE 0 END
        AS BIT) AS is_subprime,

        -- ═══ Risk Ratios (T5: drop loan_to_income_ratio) ══════════════════
        r.loan_percent_income,
        -- loan_to_income_ratio: KHÔNG SELECT → effectively dropped

        r.other_debt,

        -- D6: log_other_debt
        -- Insight: other_debt range 225 → 1.18M, right-skew rất nặng. Log
        -- transform là chuẩn cho monetary amounts trong financial modeling.
        CAST(LOG(CAST(r.other_debt + 1 AS FLOAT)) AS DECIMAL(12,6))
            AS log_other_debt,

        r.debt_to_income_ratio,
        r.open_accounts,
        r.credit_utilization_ratio,

        -- D3: lpi_bucket — 5 quantile bins
        -- Insight: ngưỡng được tìm từ DATA (q1-q4), KHÔNG hard-code 0.3 (per
        -- anti-bias rule). Sau khi có default rate per bucket trong Colab,
        -- mới benchmark với industry "danger zone" như LPI > 0.3.
        CASE
            WHEN r.loan_percent_income <= q.lpi_q1 THEN 'Q1 (lowest)'
            WHEN r.loan_percent_income <= q.lpi_q2 THEN 'Q2'
            WHEN r.loan_percent_income <= q.lpi_q3 THEN 'Q3'
            WHEN r.loan_percent_income <= q.lpi_q4 THEN 'Q4'
            ELSE 'Q5 (highest)'
        END AS lpi_bucket,

        -- D4: dti_bucket — 5 quantile bins
        -- Insight: ngưỡng từ data trước. Sẽ benchmark với QM Rule 0.43 sau
        -- (US Qualified Mortgage Rule regulatory cutoff).
        CASE
            WHEN r.debt_to_income_ratio <= q.dti_q1 THEN 'Q1 (lowest)'
            WHEN r.debt_to_income_ratio <= q.dti_q2 THEN 'Q2'
            WHEN r.debt_to_income_ratio <= q.dti_q3 THEN 'Q3'
            WHEN r.debt_to_income_ratio <= q.dti_q4 THEN 'Q4'
            ELSE 'Q5 (highest)'
        END AS dti_bucket,

        -- ═══ Credit Bureau ════════════════════════════════════════════════
        r.cb_person_default_on_file,
        r.cb_person_cred_hist_length,
        r.past_delinquencies,

        -- D9: has_prior_default
        -- Insight: binary feature cho modeling. Y/N text → 0/1 int.
        CAST(
            CASE WHEN r.cb_person_default_on_file = 'Y' THEN 1 ELSE 0 END
        AS BIT) AS has_prior_default,

        -- D8: thin_file flag — cred history < 3 năm
        -- Insight: thin file borrowers thiếu data lịch sử → uncertain risk.
        -- Industry threshold thường 2-3 năm, dùng 3 để safe.
        CAST(
            CASE WHEN r.cb_person_cred_hist_length < 3 THEN 1 ELSE 0 END
        AS BIT) AS thin_file,

        -- ═══ Geographic (giữ nguyên cho Power BI map) ═════════════════════
        r.country,
        r.state,
        r.city,
        r.city_latitude,
        r.city_longitude,

        -- D7: is_homeowner — binary OWN/MORTGAGE = 1
        -- Insight: simplify 4-category home_ownership thành binary. OWN và
        -- MORTGAGE đều imply ownership stake → cùng nhóm. RENT/OTHER = renter.
        CAST(
            CASE WHEN r.person_home_ownership IN ('OWN', 'MORTGAGE')
                 THEN 1 ELSE 0 END
        AS BIT) AS is_homeowner,

        -- ═══ Target ═══════════════════════════════════════════════════════
        r.loan_status

    FROM dbo.credit_risk_raw r
    CROSS JOIN thresholds t
    LEFT JOIN grade_medians gm ON r.loan_grade = gm.loan_grade
    LEFT JOIN emp_medians em ON r.employment_type = em.employment_type
    CROSS JOIN quantiles q
    WHERE r.person_age <= 100  -- T1: Remove 5 outlier rows (age 123-144)
)

INSERT INTO dbo.credit_risk_clean (
    client_ID,
    person_age,
    person_income,
    person_home_ownership,
    person_emp_length,
    gender,
    marital_status,
    education_level,
    employment_type,
    age_bucket,
    income_bucket,
    log_income,
    loan_intent,
    loan_grade,
    loan_amnt,
    loan_int_rate,
    loan_term_months,
    is_subprime,
    loan_percent_income,
    other_debt,
    log_other_debt,
    debt_to_income_ratio,
    open_accounts,
    credit_utilization_ratio,
    lpi_bucket,
    dti_bucket,
    cb_person_default_on_file,
    cb_person_cred_hist_length,
    past_delinquencies,
    has_prior_default,
    thin_file,
    country,
    state,
    city,
    city_latitude,
    city_longitude,
    is_homeowner,
    loan_status    
)

-- ─────────────────────────────────────────────────────────────────────────
-- Final INSERT statement
-- ─────────────────────────────────────────────────────────────────────────
SELECT
    client_ID,
    person_age,
    person_income,
    person_home_ownership,
    person_emp_length,
    gender,
    marital_status,
    education_level,
    employment_type,
    age_bucket,
    income_bucket,
    log_income,
    loan_intent,
    loan_grade,
    loan_amnt,
    loan_int_rate,
    loan_term_months,
    is_subprime,
    loan_percent_income,
    other_debt,
    log_other_debt,
    debt_to_income_ratio,
    open_accounts,
    credit_utilization_ratio,
    lpi_bucket,
    dti_bucket,
    cb_person_default_on_file,
    cb_person_cred_hist_length,
    past_delinquencies,
    has_prior_default,
    thin_file,
    country,
    state,
    city,
    city_latitude,
    city_longitude,
    is_homeowner,
    loan_status
FROM transformed;
GO


-- ─── STEP 4: Update statistics sau bulk insert ──────────────────────────────
UPDATE STATISTICS dbo.credit_risk_clean WITH FULLSCAN;
GO


-- ─── STEP 5: Verification queries (insight muốn xem) ────────────────────────


-- ─── V1: Row count sau cleaning ─────────────────────────────────────────────
-- Insight: phải bằng 32,576 = 32,581 - 5 (age outliers removed by T1).
-- Nếu khác, có nghĩa transformation bị skip rows ngoài ý muốn.
SELECT
    (SELECT COUNT(*) FROM dbo.credit_risk_raw) AS raw_rows,
    (SELECT COUNT(*) FROM dbo.credit_risk_clean) AS clean_rows,
    (SELECT COUNT(*) FROM dbo.credit_risk_raw)
        - (SELECT COUNT(*) FROM dbo.credit_risk_clean) AS rows_removed;
-- Expected: 32581 / 32576 / 5


-- ─── V2: Verify zero nulls trong cleaned table ──────────────────────────────
-- Insight: clean table phải KHÔNG có NULL anywhere (mọi cột NOT NULL).
-- Nếu query trả về > 0 → có cột nào đó bị missed trong imputation.
SELECT
    SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) AS still_null_int_rate,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS still_null_emp_len
FROM dbo.credit_risk_clean;
-- Expected: 0 / 0


-- ─── V3: Verify winsorization có effect ─────────────────────────────────────
-- Insight: max(person_income) sau clean phải = P99 (không còn 6M nữa).
SELECT
    MAX(person_income) AS max_income_after_winsorize,
    MIN(person_income) AS min_income,
    AVG(person_income) AS avg_income
FROM dbo.credit_risk_clean;
-- Expected: max ≈ P99 value (200K-300K, không phải 6M)


-- ─── V4: Verify emp_length cap ──────────────────────────────────────────────
SELECT
    MAX(person_emp_length) AS max_emp_len_after_cap,
    MIN(person_emp_length) AS min_emp_len
FROM dbo.credit_risk_clean;
-- Expected: max = 50.00 (không phải 123 nữa)


-- ─── V5: Distribution của derived buckets ───────────────────────────────────
-- Insight: mỗi bucket phải có rows hợp lý (không bucket nào rỗng).
-- Quantile buckets (lpi, dti) phải xấp xỉ 20% mỗi bin (5 quantile = 20% each).
SELECT 'age_bucket' AS feature, age_bucket AS value, COUNT(*) AS n
FROM dbo.credit_risk_clean GROUP BY age_bucket
UNION ALL
SELECT 'income_bucket', income_bucket, COUNT(*)
FROM dbo.credit_risk_clean GROUP BY income_bucket
UNION ALL
SELECT 'lpi_bucket', lpi_bucket, COUNT(*)
FROM dbo.credit_risk_clean GROUP BY lpi_bucket
UNION ALL
SELECT 'dti_bucket', dti_bucket, COUNT(*)
FROM dbo.credit_risk_clean GROUP BY dti_bucket
ORDER BY feature, value;
-- Expected: lpi_bucket và dti_bucket: ~6,515 rows mỗi bin (20%)


-- ─── V6: Quick test default rate by derived bucket (preview Colab analysis) ─
-- Insight: nếu lpi_bucket Q5 có default rate cao hơn nhiều Q1, confirm có
-- threshold effect (H5). Đây là preview cho EDA bivariate trong Colab.
SELECT
    lpi_bucket,
    COUNT(*) AS n,
    SUM(loan_status) AS defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct
FROM dbo.credit_risk_clean
GROUP BY lpi_bucket
ORDER BY lpi_bucket;
-- Expected: default rate tăng dần từ Q1 → Q5 (LPI cao = rủi ro cao).


-- ─── V7: Default rate by is_subprime (preview pricing analysis) ─────────────
SELECT
    is_subprime,
    COUNT(*) AS n,
    SUM(loan_status) AS defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct,
    AVG(loan_int_rate) AS avg_rate
FROM dbo.credit_risk_clean
GROUP BY is_subprime;
-- Expected: is_subprime=1 có default rate cao hơn nhiều + avg_rate cao hơn.


PRINT 'File 04 completed. credit_risk_clean is ready.';
PRINT 'Next: run 05_export_clean.sql to export cleaned data to CSV for Colab.';
GO
