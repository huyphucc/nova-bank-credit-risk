# Nova Bank — Credit Risk Analytics

**Author:** Dang Huy Phuc — Fintech 2026, NEU Hanoi
**Status:** ✅ SQL + EDA Complete | 🚧 Power BI Dashboard In Progress

## Business Problem
Nova Bank's loan portfolio carries a 21.82% default rate. This project
analyzes 32,576 loans to identify default drivers, quantify risk thresholds,
and recommend underwriting policy changes to reduce losses while preserving
growth opportunity.

## Tech Stack
| Tool | Purpose |
|---|---|
| SQL Server 2022 (Docker) | Data cleaning & transformation |
| Python (Google Colab) | EDA, clustering, WoE/IV, baseline model |
| Power BI | Business dashboard |

## Project Structure
```
nova-bank-credit-risk/
├── data/
│   ├── raw/                  # Original CSV (32,581 rows × 29 cols)
│   └── processed/            # Cleaned CSV (32,576 rows × 38 cols)
├── sql/                      # 5 SQL scripts (DDL → Load → QA → Clean → Export)
├── notebooks/                # nova_bank_eda.ipynb — full EDA + modeling
├── powerbi/                  # Dashboard (coming soon)
└── docs/                     # Issue Tree, Preprocessing Checklist, Roadmap
```

## Key Findings

1. **LPI and DTI are the strongest predictors** (IV = 0.71, 0.50) and
   compound: borrowers high on both default at **57.8%**.
2. **Home ownership is a 4x risk differentiator**: renters 31.58% vs.
   homeowners 7.47% default rate.
3. **Sharp risk cliff at loan grade C→D**: default jumps from 20.74% to
   59.05% in one step.
4. **Pricing doesn't match risk for subprime**: Grade G pays 2.76x Grade A's
   rate but defaults 9.88x more often.
5. **Baseline Logistic Regression (AUC=0.81)** cuts default rate among
   approved loans from 21.82% to **9.31%** at a 0.5 PD threshold.
6. **64% of the portfolio is genuinely low-risk** (clustering-derived
   segments at 8.9%-15.3% default rate) — safe base for growth.
7. **Two "classic" credit features show zero signal in this dataset**
   (`credit_utilization_ratio`, `past_delinquencies`, IV ≈ 0) — flagged as
   a synthetic-data limitation, not a business finding.

## Recommendations
- Tighten underwriting for the LPI×DTI top-quintile segment (57.8% default rate)
- Reprice or restrict grades D-G (15% of portfolio, disproportionate risk)
- Pilot the PD threshold model (0.5-0.6 range) for new originations
- Build fast-track approval for the two low-risk clusters

## Methodology Notes
- All modeling excludes protected variables (`gender`, `marital_status`,
  `education_level`) per ECOA, and `loan_grade` (circular logic — it's the
  existing scoring system's output, used only for validation)
- Full hypothesis testing follows a bias-free Issue Tree (14 hypotheses,
  see `docs/Nova_Bank_Issue_Tree.pdf`)

## Notebook
Full analysis: [`notebooks/nova_bank_eda.ipynb`](notebooks/nova_bank_eda.ipynb)
