/* =============================================================================
   FILE:        05_export_clean.sql
   PROJECT:     Nova Bank — Credit Risk Analytics
   PURPOSE:     Export bảng dbo.credit_risk_clean ra file CSV để dùng tiếp
                trong Google Colab (Python EDA) và Power BI (dashboard).

   DEPENDENCIES: File 04 đã chạy thành công (credit_risk_clean populated).
   PRODUCES:    credit_risk_clean.csv với 32,576 rows × 37 columns.

   ⚠️ T-SQL không có lệnh "SELECT INTO OUTFILE" như MySQL. Có 3 cách export:

   ┌─────────────────────────────────────────────────────────────────────────┐
   │ CÁCH A — VS Code mssql extension "Save Results as CSV" (đơn giản nhất) │
   ├─────────────────────────────────────────────────────────────────────────┤
   │ 1. Chạy query SELECT * FROM dbo.credit_risk_clean phía dưới            │
   │ 2. Khi results hiển thị, click icon "Save as CSV" ở góc result panel    │
   │ 3. Chọn folder ~/Projects/nova-bank-credit-risk/data/processed/         │
   │ 4. Đặt tên file: credit_risk_clean.csv                                 │
   │                                                                         │
   │ ✓ Đơn giản, không cần command line.                                    │
   │ ✗ Manual click — không reproducible bằng script.                       │
   └─────────────────────────────────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────────────────────────────┐
   │ CÁCH B — bcp utility từ Mac terminal (reproducible)                    │
   ├─────────────────────────────────────────────────────────────────────────┤
   │ Yêu cầu: đã cài mssql-tools18 (kèm với ODBC Driver từ Homebrew, hoặc    │
   │ download .pkg từ Microsoft).                                            │
   │                                                                         │
   │ # Từ Mac terminal:                                                      │
   │ bcp "SELECT * FROM NovaBank.dbo.credit_risk_clean" queryout \           │
   │     ~/Projects/nova-bank-credit-risk/data/processed/credit_risk_clean.csv \ │
   │     -S localhost,1433 -U sa -P 'YourPassword' \                         │
   │     -c -t',' -C 65001 -T                                                │
   │                                                                         │
   │ Flags:                                                                  │
   │   queryout = output từ query (vs in = input)                            │
   │   -c       = character mode (text, không phải binary)                   │
   │   -t','    = field terminator = comma                                   │
   │   -C 65001 = UTF-8 codepage                                             │
   │   -T       = trusted connection (skip nếu dùng -U/-P)                   │
   │                                                                         │
   │ ✓ Reproducible (lưu thành script .sh).                                 │
   │ ✗ Cần cài mssql-tools18.                                                │
   └─────────────────────────────────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────────────────────────────┐
   │ CÁCH C — docker exec + bcp trong container (no install cần)            │
   ├─────────────────────────────────────────────────────────────────────────┤
   │ Azure SQL Edge image có sẵn bcp tool bên trong. Export ra file trong    │
   │ container, rồi docker cp ra Mac.                                        │
   │                                                                         │
   │ # Bước 1: Export trong container                                        │
   │ docker exec -it azuresqledge bcp \                                      │
   │     "SELECT * FROM NovaBank.dbo.credit_risk_clean" queryout \           │
   │     /tmp/credit_risk_clean.csv \                                        │
   │     -S localhost -U sa -P 'YourPassword' -c -t',' -C 65001              │
   │                                                                         │
   │ # Bước 2: Copy file từ container ra Mac                                 │
   │ docker cp azuresqledge:/tmp/credit_risk_clean.csv \                     │
   │     ~/Projects/nova-bank-credit-risk/data/processed/credit_risk_clean.csv │
   │                                                                         │
   │ ✓ Không cần cài gì trên Mac (dùng tool trong container).               │
   │ ✗ Cần biết tên container.                                               │
   └─────────────────────────────────────────────────────────────────────────┘

   KHUYẾN NGHỊ:
     • Lần đầu chạy: dùng CÁCH A (đơn giản, learn-by-doing).
     • Lần sau (nếu cần re-export): dùng CÁCH C (1 lệnh, reproducible).
     • CÁCH B chỉ recommend nếu Phúc đã quen mssql-tools (sau project này).

   INSIGHT MUỐN VERIFY trong CSV xuất ra:
     • Header row có 37 columns (29 original - 1 dropped + 10 derived = 38?
       Wait: 29 - 1 + 10 = 38. Nhưng include client_ID làm 1, target làm 1 =
       vẫn 38? Hãy đếm trong Q1 dưới để confirm).
     • Total 32,577 lines (1 header + 32,576 data rows).
     • Encoding: UTF-8 (mở bằng TextEdit không bị lỗi ký tự).
     • Delimiter: dấu phẩy.
     • Không có dòng nào bị truncated giữa chừng.
   ============================================================================= */


USE NovaBank;
GO


-- ─── Q1: Verify schema của bảng clean trước khi export ──────────────────────
-- Insight: đếm columns để khẳng định số lượng output đúng. Lưu lại danh sách
-- cột này để dùng trong Colab notebook (Section 2 — Datasets Overview).

SELECT
    COUNT(*) AS column_count_in_clean_table
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'credit_risk_clean';
-- Expected: 37 columns
-- (29 raw - 1 dropped loan_to_income_ratio + 10 derived - 1 thừa
--  = wait, hãy tính lại):
-- 29 raw cols (gồm cả client_ID và loan_status)
-- - 1 dropped (loan_to_income_ratio)
-- + 10 derived (age_bucket, income_bucket, log_income, lpi_bucket, dti_bucket,
--               log_other_debt, is_homeowner, thin_file, has_prior_default,
--               is_subprime)
-- = 38 cột tổng
-- Nếu Q1 trả về 38 → OK. Nếu 37 → có cột nào đó missed.


-- ─── Q2: List columns theo thứ tự (để verify CSV header) ────────────────────
-- Insight: thứ tự cột trong CSV sẽ theo ORDINAL_POSITION. Copy danh sách này
-- vào Colab notebook làm reference.

SELECT
    ORDINAL_POSITION AS pos,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'credit_risk_clean'
ORDER BY ORDINAL_POSITION;


-- ─── Q3: Main SELECT để export (dùng cho CÁCH A) ────────────────────────────
-- Ý nghĩa: query này được dùng khi click "Save as CSV" trong VS Code mssql
-- extension. SELECT * preserves cột order từ CREATE TABLE.

SELECT *
FROM dbo.credit_risk_clean
ORDER BY client_ID;
-- Expected: 32,576 rows trả về. Click "Save as CSV" → save vào
--          ~/Projects/nova-bank-credit-risk/data/processed/credit_risk_clean.csv


-- ─── Q4: Quick file integrity preview (sau khi đã export) ───────────────────
-- Insight: 5 dòng đầu để spot-check format. Sau khi export, mở CSV bằng
-- TextEdit, check 5 dòng đầu khớp với output query này.

SELECT TOP 5 *
FROM dbo.credit_risk_clean
ORDER BY client_ID;


-- ─── Q5: Final summary statistics (dùng làm reference cho Colab) ────────────
-- Insight: chụp screen output này để dán vào markdown cell đầu Colab notebook
-- (Section 2 — Datasets Overview).

SELECT
    COUNT(*) AS total_rows,
    SUM(loan_status) AS total_defaults,
    CAST(AVG(CAST(loan_status AS FLOAT)) * 100 AS DECIMAL(5,2)) AS default_rate_pct,
    MIN(person_age) AS min_age,
    MAX(person_age) AS max_age,
    MIN(person_income) AS min_income,
    MAX(person_income) AS max_income_after_winsor,
    MIN(loan_int_rate) AS min_int_rate,
    MAX(loan_int_rate) AS max_int_rate
FROM dbo.credit_risk_clean;
-- Expected:
--   total_rows: 32,576
--   total_defaults: ~7,107 (sau khi -5 outliers, có thể vài defaults trong 5
--                            outliers đó nên giảm ít)
--   default_rate_pct: ~21.81-21.82%
--   max_age: 100 (sau T1)
--   max_income: ~P99 value (≈ 200-300K USD)
--   max_int_rate: ≤ 23.22%


-- ─── BƯỚC TIẾP THEO sau khi có CSV: ─────────────────────────────────────────
-- 1. Commit credit_risk_clean.csv lên GitHub repo (nova-bank-credit-risk)
--    trong folder data/processed/. Push lên branch main.
--
-- 2. Mở Google Colab → tạo notebook mới → load CSV qua URL raw GitHub:
--      import pandas as pd
--      url = "https://raw.githubusercontent.com/<username>/nova-bank-credit-risk/main/data/processed/credit_risk_clean.csv"
--      df = pd.read_csv(url)
--
-- 3. Bắt đầu Phase 4 (EDA + insights) theo Roadmap v2.0 Section 4.3.
--
-- 4. Power BI: File → Get Data → Text/CSV → chọn credit_risk_clean.csv local.

PRINT 'File 05 completed.';
PRINT 'Sau khi export CSV, commit lên GitHub và bắt đầu Phase 4 (Colab EDA).';
GO
