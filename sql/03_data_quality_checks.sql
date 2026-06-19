/* =============================================================================
   FILE:        03_data_quality_checks.sql
   PROJECT:     Nova Bank — Credit Risk Analytics
   PURPOSE:     Comprehensive Data Quality Assessment (DQA — đánh giá chất
                lượng dữ liệu) trước khi cleaning. File này KHÔNG modify data,
                chỉ chạy SELECT queries để kiểm tra.

   DEPENDENCIES: File 02 đã load xong (credit_risk_raw có 32,581 rows).
   PRODUCES:    None (read-only). Output là 12 query results để inspect.

   PHILOSOPHY:
   "Đo lường trước khi cắt" — biết chính xác data có vấn đề gì TRƯỚC khi viết
   logic cleaning. Mỗi query dưới đây map tới 1 ô trong Preprocessing
   Checklist và 1 hypothesis trong Issue Tree.

   INSIGHT MUỐN VERIFY (overview):
     ✓ Schema integrity: 29 cols, 32,581 rows, PK works
     ✓ Outliers identified: age > 100 (5 rows), income > 500K (~53 rows)
     ✓ Missing pattern: loan_int_rate nulls có pattern theo loan_grade hay
       random? Nếu theo grade → median impute by group hợp lý.
     ✓ Synthetic artifacts: correlation past_delinquencies vs default ≈ 0?
       credit_utilization_ratio vs default ≈ 0? Nếu yes → confirm H12.
     ✓ Redundancy: corr(loan_percent_income, loan_to_income_ratio) ≈ 1.0?
       Nếu yes → confirm drop trong file 04.

   CÁCH ĐỌC OUTPUT:
   Mỗi query sẽ có comment EXPECTED ở cuối. Nếu kết quả lệch nhiều so với
   expected, cần điều tra TRƯỚC KHI sang file 04.
   ============================================================================= */


USE NovaBank;
GO


/* ─────────────────────────────────────────────────────────────────────────────
   PART A — STRUCTURAL CHECKS (kiểm tra cấu trúc)
   ───────────────────────────────────────────────────────────────────────────── */


-- ─── Q1: Total rows & uniqueness ────────────────────────────────────────────
-- Mục đích: confirm load không bị duplicate hay thiếu rows.
-- Insight: cả 2 cột phải bằng nhau và bằng 32,581.

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT client_ID) AS unique_client_ids,
    COUNT(*) - COUNT(DISTINCT client_ID) AS duplicate_count
FROM dbo.credit_risk_raw;
-- Expected: 32581 / 32581 / 0


-- ─── Q2: Null distribution toàn bộ 29 cột ───────────────────────────────────
-- Mục đích: confirm CHỈ có 2 cột nullable (loan_int_rate, person_emp_length).
-- Mọi cột khác phải 0 null.
-- Insight: Nếu cột "không nên null" mà có null → có thể là vấn đề khi load
-- CSV (ví dụ empty string trong CSV → SQL Server có thể parse thành NULL hoặc
-- string rỗng tuỳ data type).

SELECT
    SUM(CASE WHEN client_ID IS NULL THEN 1 ELSE 0 END) AS null_client_ID,
    SUM(CASE WHEN person_age IS NULL THEN 1 ELSE 0 END) AS null_person_age,
    SUM(CASE WHEN person_income IS NULL THEN 1 ELSE 0 END) AS null_person_income,
    SUM(CASE WHEN person_home_ownership IS NULL THEN 1 ELSE 0 END) AS null_home_own,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS null_emp_length,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN marital_status IS NULL THEN 1 ELSE 0 END) AS null_marital,
    SUM(CASE WHEN education_level IS NULL THEN 1 ELSE 0 END) AS null_edu,
    SUM(CASE WHEN employment_type IS NULL THEN 1 ELSE 0 END) AS null_emp_type,
    SUM(CASE WHEN loan_intent IS NULL THEN 1 ELSE 0 END) AS null_intent,
    SUM(CASE WHEN loan_grade IS NULL THEN 1 ELSE 0 END) AS null_grade,
    SUM(CASE WHEN loan_amnt IS NULL THEN 1 ELSE 0 END) AS null_amnt,
    SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) AS null_int_rate,
    SUM(CASE WHEN loan_term_months IS NULL THEN 1 ELSE 0 END) AS null_term,
    SUM(CASE WHEN loan_percent_income IS NULL THEN 1 ELSE 0 END) AS null_lpi,
    SUM(CASE WHEN loan_to_income_ratio IS NULL THEN 1 ELSE 0 END) AS null_lti,
    SUM(CASE WHEN other_debt IS NULL THEN 1 ELSE 0 END) AS null_other_debt,
    SUM(CASE WHEN debt_to_income_ratio IS NULL THEN 1 ELSE 0 END) AS null_dti,
    SUM(CASE WHEN open_accounts IS NULL THEN 1 ELSE 0 END) AS null_open_acc,
    SUM(CASE WHEN credit_utilization_ratio IS NULL THEN 1 ELSE 0 END) AS null_cu,
    SUM(CASE WHEN cb_person_default_on_file IS NULL THEN 1 ELSE 0 END) AS null_cb_default,
    SUM(CASE WHEN cb_person_cred_hist_length IS NULL THEN 1 ELSE 0 END) AS null_cb_hist,
    SUM(CASE WHEN past_delinquencies IS NULL THEN 1 ELSE 0 END) AS null_past_delin,
    SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END) AS null_country,
    SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END) AS null_state,
    SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) AS null_city,
    SUM(CASE WHEN city_latitude IS NULL THEN 1 ELSE 0 END) AS null_lat,
    SUM(CASE WHEN city_longitude IS NULL THEN 1 ELSE 0 END) AS null_lon,
    SUM(CASE WHEN loan_status IS NULL THEN 1 ELSE 0 END) AS null_status
FROM dbo.credit_risk_raw;
-- Expected: tất cả 0 trừ null_emp_length=895 và null_int_rate=3116


/* ─────────────────────────────────────────────────────────────────────────────
   PART B — OUTLIER DETECTION (phát hiện outliers)
   ───────────────────────────────────────────────────────────────────────────── */


-- ─── Q3: Age outliers ────────────────────────────────────────────────────────
-- Mục đích: confirm có 5 rows với age > 100 (đã biết trước từ inspection).
-- Insight: nếu số rows này lệch (ví dụ 0 hoặc 50), có thể CSV bị tampered.
-- 5 rows này sẽ bị DELETE trong file 04 (transformation T1).

SELECT
    COUNT(*) AS rows_with_age_over_100,
    MIN(person_age) AS min_age,
    MAX(person_age) AS max_age
FROM dbo.credit_risk_raw
WHERE person_age > 100;
-- Expected: 5 / 123 / 144 (hoặc tương tự, max là 144)


-- ─── Q4: Income outliers (potential winsorization targets) ──────────────────
-- Mục đích: xác định P99 của income để biết winsorization sẽ cap về giá trị
-- nào. PERCENTILE_CONT trả về interpolated percentile (chính xác hơn _DISC).
-- Insight: P99 thường ≈ 200K-300K cho personal loan data. Nếu rất khác,
-- distribution lệch khác thường.

SELECT DISTINCT
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY person_income) OVER () AS p50_income,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY person_income) OVER () AS p95_income,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY person_income) OVER () AS p99_income,
    MAX(person_income) OVER () AS max_income,
    SUM(CASE WHEN person_income > 500000 THEN 1 ELSE 0 END) OVER () AS rows_above_500k
FROM dbo.credit_risk_raw;
-- Expected: median ≈ 55,000; p99 ≈ 200K-300K; max = 6,000,000; ~53 rows > 500K


-- ─── Q5: Emp_length outliers ────────────────────────────────────────────────
-- Mục đích: kiểm tra max emp_length (đã biết max=123, bất hợp lý).
-- Insight: số rows với emp_length > 50 cho biết có bao nhiêu cases cần cap.

SELECT
    COUNT(*) AS total_non_null,
    MIN(person_emp_length) AS min_emp_len,
    MAX(person_emp_length) AS max_emp_len,
    SUM(CASE WHEN person_emp_length > 50 THEN 1 ELSE 0 END) AS rows_over_50,
    SUM(CASE WHEN person_emp_length > 80 THEN 1 ELSE 0 END) AS rows_over_80
FROM dbo.credit_risk_raw
WHERE person_emp_length IS NOT NULL;
-- Expected: ~31686 / 0 / 123 / một số ít rows > 50, các rows này sẽ bị cap


-- ─── Q6: DTI > 1.0 (debt exceeds income) ────────────────────────────────────
-- Mục đích: count edge cases với DTI bất thường.
-- Insight: nếu chỉ vài rows → có thể là legitimate high-risk borrowers,
-- giữ lại. Nếu nhiều (>5%) → có thể data error, cần điều tra.

SELECT
    COUNT(*) AS rows_with_dti_over_1,
    MIN(debt_to_income_ratio) AS min_dti_in_subset,
    MAX(debt_to_income_ratio) AS max_dti_in_subset
FROM dbo.credit_risk_raw
WHERE debt_to_income_ratio > 1.0;
-- Expected: vài đến vài chục rows (cần inspect)


/* ─────────────────────────────────────────────────────────────────────────────
   PART C — MISSING VALUE PATTERN ANALYSIS (phân tích pattern của missing)
   ───────────────────────────────────────────────────────────────────────────── */


-- ─── Q7: Missing loan_int_rate by loan_grade ────────────────────────────────
-- Mục đích: kiểm tra missingness pattern. Nếu nulls phân bố đều theo grade →
-- missing at random (MCAR) → median impute đơn giản. Nếu tập trung 1-2 grade
-- cụ thể → missing NOT at random (MNAR) → cần investigate kỹ hơn.
-- Insight: Đây là KEY DECISION cho transformation T4 trong file 04. Nếu
-- pattern hợp lý theo grade, median impute by grade là cách hợp lý nhất.

SELECT
    loan_grade,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) AS nulls,
    CAST(SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS null_pct,
    AVG(loan_int_rate) AS avg_rate_non_null
FROM dbo.credit_risk_raw
GROUP BY loan_grade
ORDER BY loan_grade;
-- Insight muốn thấy: avg_rate tăng dần theo grade A → G (risk-based pricing).
-- null_pct: nếu spread đều ~9-10% across grades thì OK; nếu chỉ 1-2 grades có
-- nulls cao thì cần dig deeper.


-- ─── Q8: Missing person_emp_length by employment_type ───────────────────────
-- Mục đích: confirm hypothesis rằng nulls trong emp_length có thể liên quan
-- đến employment_type = 'Unemployed' (logic: unemployed không có years of
-- employment).
-- Insight: nếu phần lớn nulls thuộc Unemployed → impute = 0 hợp lý.
-- Nếu phân bố đều → cần impute median by group.

SELECT
    employment_type,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS nulls,
    CAST(SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS null_pct,
    AVG(person_emp_length) AS avg_emp_len_non_null
FROM dbo.credit_risk_raw
GROUP BY employment_type
ORDER BY employment_type;
-- Insight: chú ý null_pct của Unemployed. Nếu cao (>50%) → impute = 0 đúng.
-- Nếu đều (~3%) cho mọi nhóm → impute median by group an toàn hơn.


/* ─────────────────────────────────────────────────────────────────────────────
   PART D — REDUNDANCY & MULTICOLLINEARITY (trùng lặp, đa cộng tuyến)
   ───────────────────────────────────────────────────────────────────────────── */


-- ─── Q9: Correlation loan_percent_income vs loan_to_income_ratio ────────────
-- Mục đích: confirm 2 cột này redundant (gần như identical).
-- T-SQL không có CORR() built-in, dùng Pearson formula thủ công:
--   r = (n*Σxy - Σx*Σy) / sqrt((n*Σx² - (Σx)²) * (n*Σy² - (Σy)²))
-- Insight: nếu r > 0.99 → confirm DROP loan_to_income_ratio trong file 04.
-- Đây là decision điểm cốt lõi cho anti-multicollinearity.

WITH stats AS (
    SELECT
        COUNT(*) AS n,
        SUM(CAST(loan_percent_income AS FLOAT)) AS sum_x,
        SUM(CAST(loan_to_income_ratio AS FLOAT)) AS sum_y,
        SUM(CAST(loan_percent_income AS FLOAT) * CAST(loan_to_income_ratio AS FLOAT)) AS sum_xy,
        SUM(CAST(loan_percent_income AS FLOAT) * CAST(loan_percent_income AS FLOAT)) AS sum_x2,
        SUM(CAST(loan_to_income_ratio AS FLOAT) * CAST(loan_to_income_ratio AS FLOAT)) AS sum_y2
    FROM dbo.credit_risk_raw
)
SELECT
    n,
    (n * sum_xy - sum_x * sum_y)
    / SQRT( (n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y) )
    AS pearson_correlation
FROM stats;
-- Expected: correlation > 0.999 → confirm redundancy → drop trong file 04.


/* ─────────────────────────────────────────────────────────────────────────────
   PART E — TARGET RELATIONSHIP CHECKS (kiểm tra quan hệ với target)
   ───────────────────────────────────────────────────────────────────────────── */


-- ─── Q10: Default rate by home_ownership (test H1) ──────────────────────────
-- Mục đích: quick sanity check rằng home ownership có discriminating power.
-- Insight: nếu default rate giữa RENT vs OWN khác biệt rõ → H1 likely TRUE.
-- Đây không phải full test (sẽ làm trong Colab notebook với chi-square), chỉ
-- là descriptive check để biết direction.

SELECT
    person_home_ownership,
    COUNT(*) AS n,
    SUM(loan_status) AS defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct
FROM dbo.credit_risk_raw
GROUP BY person_home_ownership
ORDER BY default_rate_pct DESC;
-- Expected: RENT có default rate cao nhất (~30%), OWN/MORTGAGE thấp hơn (~7-15%).
-- Đây là một trong những finding chính của project.


-- ─── Q11: Default rate by cb_person_default_on_file (test H2) ───────────────
-- Mục đích: confirm prior default mạnh predict future default.
-- Insight: gap giữa Y vs N càng lớn → predictor càng mạnh.
-- Đây là baseline cho domain knowledge (past behavior predicts future).

SELECT
    cb_person_default_on_file,
    COUNT(*) AS n,
    SUM(loan_status) AS defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct
FROM dbo.credit_risk_raw
GROUP BY cb_person_default_on_file
ORDER BY cb_person_default_on_file;
-- Expected: Y default rate ~38%, N ~18% → 2x gap → strong predictor.


-- ─── Q12: Synthetic artifact suspects — past_delinquencies vs default ───────
-- Mục đích: TEST H12 — nghi ngờ past_delinquencies là synthetic artifact.
-- Trong thực tế, past_delinquencies là top 3 predictor của default. Nếu trong
-- data này default rate KHÔNG tăng theo số delinquencies → confirm artifact.
-- Insight: nếu default rate flat across all delinquency levels (5 vs 0 vẫn
-- gần ~22%) → KHÔNG dùng feature này trong model + document trong Section 7.6
-- (Data Quality Findings).

SELECT
    past_delinquencies,
    COUNT(*) AS n,
    SUM(loan_status) AS defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct
FROM dbo.credit_risk_raw
GROUP BY past_delinquencies
ORDER BY past_delinquencies;
-- Expected: nếu default_rate_pct dao động nhỏ (ví dụ tất cả ~ 21-23%) → CONFIRM
-- H12 (synthetic artifact). Nếu tăng dần theo delinquencies → predictor thật.


PRINT 'File 03 completed. Review kết quả 12 queries trên trước khi sang 04.';
PRINT 'Đặc biệt chú ý: Q7 (pattern nulls), Q8 (Unemployed null pattern),';
PRINT 'Q9 (correlation), Q12 (synthetic artifact).';
GO
