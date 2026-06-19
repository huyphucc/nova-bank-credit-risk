# HANDOFF — Banking Credit Risk Analytics Project

---

## 1. Bối cảnh project

**Người thực hiện:** Đặng Huy Phúc — sinh viên năm cuối Fintech, NEU Hà Nội, tốt nghiệp 2026. Career target: Data Analyst Intern/Fresher ngành Credit Risk Analytics tại Hà Nội (VPBank, MB Bank, Home Credit Vietnam, FiinGroup, MCredit).

**Tên project:** Banking Credit Risk Analytics — Nova Bank

**Mục tiêu tổng thể:** Xây dựng portfolio project phân tích Credit Risk, thể hiện cả technical skills (SQL/Python/Power BI) lẫn domain knowledge credit risk. Đây là deliverable quan trọng nhất trong portfolio.

**Deliverables cuối cùng:**
1. Jupyter Notebook trên GitHub (SQL queries + Python code + analysis narrative)
2. Power BI Dashboard (interactive visualization, 5-7 trang)
3. README.md trên GitHub repo
4. (Optional) PDF Report / Presentation Deck

**Tools & Tool Chain (ĐÃ CHỐT):**
1. **SQL** — ưu tiên dùng TRƯỚC cho data processing & cleaning
2. **Python** — fallback nếu SQL không xử lý được + dùng cho EDA (Pandas, NumPy, Matplotlib, Seaborn, scikit-learn, statsmodels)
3. **Power BI** — visualization & dashboard (KHÔNG dùng Python cho viz cuối cùng)
4. **Jupyter Notebook** — trình bày SQL queries + Python code + analysis narrative → upload GitHub

**Big Question (đã chốt, có feedback mentor):**
"How can Nova Bank optimize lending decisions to reduce default losses AND identify higher-quality borrower segments through data?"

→ Hai chiều: Risk Mitigation + Growth Opportunity (tìm nguồn cho vay chất lượng hơn thông qua data & info của leads tiềm năng).

---

## 2. Dataset Schema (NGUYÊN VĂN)

**File:** `Credit_Risk_Dataset.xlsx` — Sheet: `Credit Risk Data`
**Shape:** 32,581 rows × 29 columns
**Source:** Synthetic/simulated data từ cộng đồng DA
**Scenario:** Nova Bank — ngân hàng cho vay cá nhân tại US, UK, Canada

### Column Schema (verified trực tiếp từ data):

```
COLUMN                      | DTYPE    | NULL_COUNT | UNIQUE
----------------------------|----------|------------|-------
client_ID                   | str      | 0          | 32581
person_age                  | int64    | 0          | 58
person_income               | int64    | 0          | 4295
person_home_ownership       | str      | 0          | 4      (RENT/MORTGAGE/OWN/OTHER)
person_emp_length           | float64  | 895        | 36
loan_intent                 | str      | 0          | 6      (EDUCATION/MEDICAL/VENTURE/PERSONAL/DEBTCONSOLIDATION/HOMEIMPROVEMENT)
loan_grade                  | str      | 0          | 7      (A/B/C/D/E/F/G)
loan_amnt                   | int64    | 0          | 753
loan_int_rate               | float64  | 3116       | 348
loan_status                 | int64    | 0          | 2      (0=Non-default, 1=Default) ← TARGET
loan_percent_income         | float64  | 0          | 77
cb_person_default_on_file   | str      | 0          | 2      (Y/N)
cb_person_cred_hist_length  | int64    | 0          | 29
gender                      | str      | 0          | 2      (Male/Female)
marital_status              | str      | 0          | 4      (Single/Married/Divorced/Widowed)
education_level             | str      | 0          | 4      (High School/Bachelor/Master/PhD)
country                     | str      | 0          | 3      (US/UK/Canada)
state                       | str      | 0          | 9
city                        | str      | 0          | 18
city_latitude               | float64  | 0          | 18
city_longitude              | float64  | 0          | 18
employment_type             | str      | 0          | 4      (Full-time/Part-time/Self-employed/Unemployed)
loan_term_months            | int64    | 0          | 4      (12/24/36/60)
loan_to_income_ratio        | float64  | 0          | 9914
other_debt                  | float64  | 0          | 32581
debt_to_income_ratio        | float64  | 0          | 32581
open_accounts               | int64    | 0          | 16
credit_utilization_ratio    | float64  | 0          | 32581
past_delinquencies          | int64    | 0          | 7
```

### Target Variable:
- `loan_status`: 0 = Non-default (25,473 = 78.2%), 1 = Default (7,108 = 21.8%)
- Imbalanced nhẹ — dùng `class_weight='balanced'` thay vì SMOTE

### 29 columns chia 5 nhóm logic:
1. **Demographics (9):** client_ID, person_age, person_income, person_home_ownership, person_emp_length, gender, marital_status, education_level, employment_type
2. **Loan Characteristics (5):** loan_intent, loan_grade, loan_amnt, loan_int_rate, loan_term_months
3. **Risk Ratios (6):** loan_percent_income, loan_to_income_ratio, other_debt, debt_to_income_ratio, credit_utilization_ratio, open_accounts
4. **Credit Bureau (4):** cb_person_default_on_file, cb_person_cred_hist_length, past_delinquencies, (open_accounts cũng có thể xếp đây)
5. **Geographic (5):** country, state, city, city_latitude, city_longitude

### Data Quality Issues đã xác định (chưa xử lý — chưa code):
- `person_age`: 5 rows >100 (max=144) — vô lý sinh học
- `person_emp_length`: Missing 895 rows (2.7%), max=123 — vô lý
- `person_income`: 53 rows >500K (max=6M) — extreme outliers
- `loan_int_rate`: Missing 3,116 rows (9.6%) — cần analyze pattern by grade trước khi impute
- `loan_percent_income` ≈ `loan_to_income_ratio`: correlation ~1.0 — redundant, cần verify rồi drop 1

---

## 3. Instructions / Quy tắc đã thống nhất (NGUYÊN VĂN)

### 3A. Typical Analytics Deck Format (7 sections — theo hình Phúc gửi):
```
1. Project Overview     — Overview of the project's context and goals
2. Datasets Overview    — Summary of datasets used in the project
3. Terms & Metrics      — Definitions of key terms and metrics applied
4. Approaches           — Description of methodologies and strategies employed
5. Executive Summary    — Concise summary of the project's findings
6. Recommendation       — Suggested actions based on analysis results
7. Detailed Analysis    — In-depth examination of data and findings
```
**Lưu ý thứ tự:** Trình bày theo 1→7, nhưng khi LÀM thì Detailed Analysis (7) phải làm TRƯỚC Executive Summary (5) và Recommendation (6).

### 3B. Mentor Feedback (NGUYÊN VĂN):
```
"1. tổng quan tree a thấy cũng đủ ý và match với big question rồi, btw a nghĩ 
big question nên mở rộng ra xíu để đúng hơn vs các ý e đang brainstorm: goal 
sẽ là giảm default rate + tìm kiếm các nguồn cho vay chất lượng hơn thông qua 
data & info của những leads tìm năng

2. btw khi sử dụng các metrics trong bài nhớ chú thích rõ định nghĩa để người 
đọc cùng hiểu nhé, mấy domain về credit, banking nhiều chỉ số đặc thù"
```

### 3C. Anti-Bias Rules (ĐÃ CHỐT — rất quan trọng):

**7 loại bias đã audit và phải tránh:**

1. **Không ghi kết luận sẵn trong issue tree** — Leaf nodes phải là câu hỏi/hypothesis, không phải findings với con số. Con số chỉ xuất hiện trong Detailed Analysis SAU KHI data đã clean.

2. **Không anchoring on regulatory numbers** — Phải tìm threshold TỪ DATA trước (optimal cutoff), rồi mới benchmark với regulation (DTI 43% QM Rule). Không phải: bắt đầu từ 43% rồi nói "data confirm."

3. **Không dismiss variables quá sớm** — `past_delinquencies` và `credit_utilization_ratio` có correlation ~0 với target, nhưng CHƯA THỂ kết luận "vô dụng." Phải check: (1) correlation with other predictors (multicollinearity — loan_grade có thể đã absorb signal), (2) interaction effects, (3) WoE/IV khi bin hợp lý. Rồi MỚI kết luận.

4. **Không confounding trong loan intent** — DebtConsolidation default cao nhất nhưng có thể vì người vay DC đã có sẵn DTI cao + credit history xấu. Phải control for confounders trước khi nói "intent drives risk."

5. **Không giả định 21.8% "quá cao"** — Không có industry benchmark cho dataset synthetic này. Phải acknowledge: "We analyze default rate as the target metric but note that without industry benchmarks, we cannot state whether 21.8% is above or below acceptable thresholds."

6. **Không kết luận "undercharging" quá sớm** — Rate gap nhỏ giữa Grade C và D có thể do nhiều yếu tố không có trong data (recovery rate, cost of funds, collateral). Chỉ có thể nói: "the rate differential appears small relative to the default differential" — observation, không phải conclusion.

7. **Không manual profile "quality borrower"** — Phải dùng data-driven segmentation (clustering), không phải cherry-pick variables có correlation cao rồi gọi đó là "quality profile."

### 3D. Bài mẫu NTT (SHBFinance) — Learnings:
- File: `Credit_risk_analysis__NTT.pdf` (43 slides, trong Project Files)
- Dùng **SCQA framework** cho Executive Summary: Situation → Complication → Question → Answer
- **Terms & Metrics** section riêng biệt trước analysis: DPD buckets, delinquency matrix, vintage analysis, roll rate
- **Company Overview** profile borrower portfolio (age segmentation, income, loan purpose) trước Detailed Analysis
- **Customer segmentation** bằng K-means clustering → 5 clusters → personalized recommendations (Control / Growth / Loyalty)
- Navigation bar ở bottom mỗi slide
- Mỗi chart page có: headline takeaway ở top, chart ở giữa, key findings box ở bên phải

### 3E. Issue Tree Structure (ĐÃ CHỐT — bias-free version):

**Page 1 — Overview:**
- Root: "How can Nova Bank optimize lending decisions to reduce default losses AND identify higher-quality borrower segments through data?"
- 3 nhánh: Risk Mitigation (🔴) / Growth Opportunity (🟢) / Data Integrity Check (🟡)

**Page 2 — Branch 1: Risk Mitigation (Hypotheses to Test):**
- Borrower characteristics → (H1) Does home ownership differentiate default risk? (H2) Does prior default history predict future default?
- Loan product features → (H3) Does loan intent drive risk or is it proxy? (H4) Is there a non-linear cliff across grades?
- Financial ratio thresholds → (H5) At what LPI does default escalate? (find from data first) (H6) At what DTI does default spike? (H7) Do LPI and DTI interact?

**Page 3 — Branch 2 & 3: Growth + Data Integrity:**
- Borrower segmentation → (H8) Can clustering reveal low-risk segments? (H9) What feature combination separates low vs high default?
- Pricing alignment → (H10) Does rate differential reflect actual default gap? (H11) Policy simulation trade-off?
- Data quality → (H12) Are low-corr variables truly non-predictive or absorbed? (H13) Do outliers/missing distort findings? (H14) Should protected variables be excluded?

**PDF file đã xuất:** `Nova_Bank_Issue_Tree.pdf` (3 trang, A3 landscape, font ≥ 11)

### 3F. Roadmap phân tích — 3 tầng:
- **Tầng 1 — Descriptive:** Data Cleaning → EDA → Default Rate by Segments → Correlation Analysis
- **Tầng 2 — Diagnostic:** Risk Segmentation → Threshold Analysis → Pricing Check → Geographic Interaction
- **Tầng 3 — Predictive (optional showcase):** WoE/IV → Logistic Regression → Scorecard → Expected Loss → Policy Simulation

### 3G. Domain Knowledge cần nhớ:
- **Expected Loss** = PD × LGD × EAD
- **DTI** = Total Debt / Annual Income
- **LPI** = Loan Amount / Annual Income
- **WoE** = ln(% Non-default / % Default) per bin
- **IV** = Σ(% Non-default − % Default) × WoE → IV > 0.1: useful, > 0.3: strong
- **LGD assumption** cho unsecured personal loans: 40-60% (dataset không có recovery data → assume 40%)
- **loan_grade** = OUTPUT của scoring system hiện tại → KHÔNG dùng làm input khi build new model (circular logic). Dùng để VALIDATE hệ thống hiện tại.
- **Protected variables:** gender, education, marital_status → exclude vì (1) không có discriminating power, (2) vi phạm ECOA / fair lending

### 3H. Tool Chain & Workflow (ĐÃ CHỐT — QUAN TRỌNG):

**Thứ tự ưu tiên: SQL TRƯỚC → Python fallback → Power BI visualization**

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE         │  TOOL       │  GHI CHÚ                        │
├─────────────────────────────────────────────────────────────────┤
│  Data Loading  │  SQL        │  Import Excel → SQL database     │
│                │             │  (SQLite hoặc DuckDB)            │
│  Data Cleaning │  SQL        │  Outlier removal, missing value  │
│                │             │  handling, redundancy check       │
│                │             │  → viết SQL queries trong Notebook│
│  Data Cleaning │  Python     │  CHỈ KHI SQL không xử lý được   │
│  (fallback)    │             │  (e.g., complex imputation,      │
│                │             │  log transform, Winsorize)        │
│  EDA           │  Python     │  Pandas + Matplotlib/Seaborn     │
│                │             │  cho analysis & quick charts      │
│  Visualization │  Power BI   │  Dashboard cuối cùng (5-7 trang) │
│                │             │  Import cleaned data từ SQL/Python│
│  Modeling      │  Python     │  scikit-learn, statsmodels        │
│  (optional)    │             │  WoE/IV, Logistic Regression      │
└─────────────────────────────────────────────────────────────────┘
```

**Trong Jupyter Notebook:** Sẽ có cả SQL cells (via sqlite3/sqlalchemy hoặc %%sql magic) VÀ Python cells. SQL queries cho data processing, Python cho EDA & modeling. Notebook phải show cả SQL queries lẫn Python code — đây là điểm demonstrate SQL skill cho portfolio.

**Power BI:** Nhận cleaned data output từ SQL/Python → build dashboard riêng biệt. Không dùng Python matplotlib cho final visualization trong deliverable.

---

## 4. Đã hoàn thành

| # | Phần | Output | Ghi chú |
|---|------|--------|---------|
| 1 | Dataset profile & verification | Confirmed 32,581 × 29 | Đã load và verify schema matches research |
| 2 | EDA sơ bộ (conversation trước) | Documented trong project context files | 7 key findings, correlation rankings, data quality issues — tất cả từ RAW data chưa clean |
| 3 | Typical Analytics Deck Blueprint | Interactive React artifact | 7 sections theo format TheHauData, mapping vào Notebook + Power BI |
| 4 | Issue Tree v4 (bias-free) | `Nova_Bank_Issue_Tree.pdf` (3 trang A3) | Tất cả leaf = hypotheses, không kết luận sẵn |
| 5 | Bias audit | 7 biases identified & flagged | Đã chốt anti-bias rules cho toàn bộ project |
| 6 | Bài mẫu NTT review | Đã đọc & rút learnings | SCQA framework, Terms & Metrics section, K-means clustering |
| 7 | Mentor feedback integration | Big question mở rộng 2 chiều | Risk mitigation + Growth opportunity |

---

## 5. Đang làm / Bị vướng ở đâu

**Chưa viết dòng code nào cho project thực tế.** Toàn bộ phần trên là planning & structuring (bước "Ask" trong DA process).

**Bước hiện tại:** Sẵn sàng bắt đầu code Jupyter Notebook — Phase 1 (Setup: Project Overview, Dataset Overview, Terms & Metrics, Approaches) → Phase 2 (Core Analysis: Data Cleaning + EDA).

**Không có vấn đề vướng** — tất cả đã align.

---

## 6. Bước tiếp theo (Action cụ thể theo thứ tự)

### Phase 1: Setup Notebook (ước tính ~1.5h)
1. **Cell 1-2:** Project Overview — Title, SCQA framework (Situation → Complication → Question → Answer), scope
2. **Cell 3-6:** Datasets Overview — Load Excel → SQL database (SQLite/DuckDB), SQL queries: row count, column info, missing analysis, column grouping table 5 nhóm
3. **Cell 7-8:** Terms & Metrics — Glossary table: Default, Default Rate, DTI, LPI, Loan Grade, NPL, WoE, IV, EL, PD/LGD/EAD
4. **Cell 9-15:** Approaches — 3-tier methodology, tool chain (SQL → Python → Power BI), data cleaning strategy with decision log, fair lending note

### Phase 2: Core Analysis (ước tính ~7-8h)
5. **Data Cleaning (SQL):** Viết SQL queries cho: outlier removal (age, emp_length, income), missing value analysis by segment (int_rate by grade), redundancy check (loan_percent_income vs loan_to_income_ratio). Nếu SQL không đủ (e.g., Winsorize, complex imputation) → switch sang Python với ghi chú rõ lý do.
6. **EDA Part A (Python):** Univariate analysis — distributions, value counts (Pandas + Matplotlib/Seaborn)
7. **EDA Part B (Python):** Bivariate/Correlation — heatmap, top predictors ranking, test H1-H7
8. **EDA Part C (Python):** Segment deep-dives — test hypotheses from issue tree
9. **EDA Part D (Python):** Advanced diagnostics — risk segmentation matrix, threshold optimization (find from data first), pricing check

### Phase 3: Synthesis (~1h)
10. **Executive Summary:** 5-7 key findings TỪ analysis (con số chỉ xuất hiện ở đây, sau khi đã clean & analyze)
11. **Recommendations:** Quick Wins + Strategic Changes + Fair Lending — mỗi cái có data backing
12. **Limitations:** Synthetic data artifacts, no time dimension, assumptions

### Phase 4: Deliverables (~4-5h)
13. Power BI Dashboard (5-7 trang)
14. README.md + GitHub
15. Review & Polish

---

## 7. Lưu ý tránh lặp lỗi

### ĐÃ THỬ VÀ KHÔNG HIỆU QUẢ:
1. **Issue tree v1:** Nhồi quá nhiều nodes + con số vào 1 trang → quá khó đọc. Phúc yêu cầu font ≥ 11, thoáng, nhiều trang.
2. **Issue tree v2-v3:** Ghi sẵn findings (con số) trong leaf nodes → mentor & Phúc flag confirmation bias. PHẢI là câu hỏi.
3. **Table format (4 cột ngang):** Phúc không muốn format bảng, muốn format tree ngang (Root → Parent → Child Level 1 → Child Level 2) giống ảnh mẫu đã gửi.
4. **Visualizer tool:** Bị timeout, không dùng được. Dùng matplotlib + reportlab export PDF thay thế.

### QUY TẮC ĐÃ CHỐT KHÔNG ĐƯỢC THAY ĐỔI:
- **Tool chain: SQL trước → Python fallback + EDA → Power BI visualization** (KHÔNG dùng Python cho final viz)
- Big question = 2 chiều (reduce default + find quality leads)
- Issue tree = hypotheses only, no pre-baked numbers
- Analytics Deck = 7 sections theo format TheHauData
- Anti-bias rules = 7 điểm ở Section 3C
- loan_grade = không dùng làm input cho model (circular logic)
- Protected variables = exclude (gender, education, marital)
- Threshold finding = from data first, benchmark with regulation second
- Terms & Metrics section = phải có (mentor nhấn mạnh)

### FILES TRONG PROJECT:
- `/mnt/project/Credit_Risk_Dataset.xlsx` — Dataset chính (32,581 × 29)
- `/mnt/project/Đề_bài.txt` — Đề bài tiếng Việt
- `/mnt/project/Credit_risk_analysis__NTT.pdf` — Bài mẫu được đánh giá cao (43 slides, SHBFinance)

### CONTEXT DOCUMENTS (đính kèm trong chat):
- Document 2: Project Memory — Banking Credit Risk Analytics (structured context)
- Document 3: Column-by-column explanation (ý nghĩa business + ghi chú quan trọng cho từng cột)
- Document 4: Full analysis overview (4 phần: Đọc hiểu → Đề bài → Findings → Hướng đi)
- Document 5: Condensed project context (copy-paste version)

→ Tất cả 4 documents này đã được đính kèm sẵn trong Project, Claude ở chat mới sẽ thấy.

---

*Handoff created: June 14, 2026. Ready for Phase 1: Setup Notebook.*
