-- =============================================================================
-- Script       : 02_churn_overview.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0
-- Description  : Establishes the baseline churn KPIs that appear on Page 1 of
--                the Power BI executive dashboard and anchor the executive
--                summary. Every number in this script is a verified, source-
--                of-truth figure for the project.
-- Business Q   : "What is our current churn rate and how does the churned
--                customer base compare to the retained base?"
-- Depends on   : 01_database_setup.sql (customer_churn table must exist)
-- Next script  : 03_revenue_impact.sql
-- =============================================================================
-- MYSQL NOTES (changes from PostgreSQL original):
--   [M1] churn.customer_churn → USE churn; + bare table name customer_churn
--   [M5] SUM(COUNT(*)) OVER() / SUM(SUM(col)) OVER() → CTE pre-aggregation.
--        MySQL 8 does not allow a GROUP BY aggregate function to be nested
--        inside a window function in the same SELECT. Pattern used throughout:
--
--        -- POSTGRESQL (invalid in MySQL):
--        ROUND(SUM(Churn_Binary) * 100.0 / SUM(SUM(Churn_Binary)) OVER (), 1)
--
--        -- MYSQL 8 EQUIVALENT (CTE carries the grand total):
--        WITH totals AS (SELECT SUM(Churn_Binary) AS grand_total FROM customer_churn)
--        SELECT ..., ROUND(SUM(Churn_Binary) * 100.0 / t.grand_total, 1) ...
--        CROSS JOIN totals t
--
--        This pattern adds one CTE or subquery per query. All business logic
--        and output columns are identical to the PostgreSQL original.
--
--   [M6] GROUP BY on a derived CASE alias (Query 8, contract_group):
--        MySQL 8 supports GROUP BY on a SELECT-list alias — no change needed.
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- QUERY 1 : HEADLINE CHURN KPI DASHBOARD
-- =============================================================================
-- Business objective:
--   Provide a single-row executive summary of the four headline churn metrics
--   that appear on the Power BI KPI card row.
--
-- Expected output (single row):
--   total_customers | churned | retained | churn_rate_pct | retention_rate_pct
--   7,043           | 1,869   | 5,174    | 26.54          | 73.46
-- =============================================================================

SELECT
    COUNT(*)                                                      AS total_customers,
    SUM(Churn_Binary)                                             AS churned,
    COUNT(*) - SUM(Churn_Binary)                                  AS retained,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                AS churn_rate_pct,
    ROUND((COUNT(*) - SUM(Churn_Binary)) * 100.0 / COUNT(*), 2)   AS retention_rate_pct
FROM customer_churn;


-- =============================================================================
-- QUERY 2 : FULL CUSTOMER BASE PROFILE — CHURNED VS RETAINED
-- =============================================================================
-- Business objective:
--   Characterise what distinguishes a churned customer from a retained one
--   across every relevant dimension.
--
-- [M5] pct_of_base: SUM(COUNT(*)) OVER() replaced with CROSS JOIN to a
--      total-count subquery. All other columns are MySQL-native.
--
-- Expected output (two rows):
--   Churn | customer_count | pct_of_base | avg_tenure | avg_monthly | avg_total
--   Yes   | 1,869          | 26.54%      | 18.0 mo    | $74.44      | $1,531.80
--   No    | 5,174          | 73.46%      | 37.6 mo    | $61.27      | $2,549.91
-- =============================================================================

SELECT
    c.Churn,
    COUNT(*)                                                      AS customer_count,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 2)                AS pct_of_base,
    ROUND(AVG(c.tenure), 1)                                       AS avg_tenure_months,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(AVG(c.TotalCharges), 2)                                 AS avg_total_charges,
    ROUND(MIN(c.MonthlyCharges), 2)                               AS min_monthly_charge,
    ROUND(MAX(c.MonthlyCharges), 2)                               AS max_monthly_charge,
    ROUND(MIN(c.tenure), 0)                                       AS min_tenure,
    ROUND(MAX(c.tenure), 0)                                       AS max_tenure,
    ROUND(
        SUM(CASE WHEN c.SeniorCitizen = 'Yes' THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                                             AS pct_senior_citizens,
    ROUND(
        SUM(CASE WHEN c.Partner = 'Yes' THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                                             AS pct_with_partner,
    ROUND(
        SUM(CASE WHEN c.Dependents = 'Yes' THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                                             AS pct_with_dependents
FROM customer_churn c
CROSS JOIN (SELECT COUNT(*) AS total_customers FROM customer_churn) t
GROUP BY c.Churn, t.total_customers
ORDER BY c.Churn DESC;


-- =============================================================================
-- QUERY 3 : CHURN RATE BY TENURE BAND
-- =============================================================================
-- Business objective:
--   Identify at which point in the customer lifecycle churn risk is highest.
--
-- [M5] share_of_total_churn_pct uses SUM(SUM(Churn_Binary)) OVER() in
--      PostgreSQL — invalid in MySQL 8. Replaced with a CROSS JOIN to a
--      grand-total CTE that pre-computes SUM(Churn_Binary) for the full table.
--
-- Expected output:
--   tenure_band   | customers | churned | churn_rate | share_of_total_churn
--   0-12 months   | 2,186     | 1,037   | 47.4%      | 55.5%
--   13-24 months  | 1,024     |   294   | 28.7%      | 15.7%
--   25-48 months  | 1,594     |   325   | 20.4%      | 17.4%
--   49-72 months  | 2,239     |   213   |  9.5%      | 11.4%
-- =============================================================================

WITH total_churned AS (
    SELECT SUM(Churn_Binary) AS grand_total_churned
    FROM customer_churn
)
SELECT
    c.tenure_band,
    COUNT(*)                                                      AS total_customers,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(SUM(c.Churn_Binary) * 100.0 / t.grand_total_churned, 1) AS share_of_total_churn_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge
FROM customer_churn c
CROSS JOIN total_churned t
GROUP BY c.tenure_band, t.grand_total_churned
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- =============================================================================
-- QUERY 4 : CHURN RATE BY CONTRACT TYPE
-- =============================================================================
-- Business objective:
--   Quantify the relationship between contract commitment and churn behaviour.
--
-- [M5] Two window calculations replaced with CROSS JOIN to grand-total CTE:
--      (a) pct_of_base:            COUNT(*) / total customers
--      (b) share_of_total_churn:   SUM(Churn_Binary) / total churned
--      (c) pct_of_total_mrr:       SUM(MonthlyCharges) / total MRR
--
-- Expected output:
--   Contract       | customers | pct_base | churned | churn_rate | share_churn | pct_mrr
--   Month-to-month | 3,875     | 55.0%    | 1,655   | 42.7%      | 88.5%       | 55.9%
--   One year       | 1,473     | 20.9%    |   166   | 11.3%       | 8.9%       | 21.0%
--   Two year       | 1,695     | 24.1%    |    48   |  2.8%       | 2.6%       | 22.6%
-- =============================================================================

WITH base_totals AS (
    SELECT
        COUNT(*)                AS total_customers,
        SUM(Churn_Binary)       AS total_churned,
        SUM(MonthlyCharges)     AS total_mrr
    FROM customer_churn
)
SELECT
    c.Contract,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(SUM(c.Churn_Binary) * 100.0 / t.total_churned, 1)       AS share_of_total_churn_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / t.total_mrr, 1)         AS pct_of_total_mrr
FROM customer_churn c
CROSS JOIN base_totals t
GROUP BY c.Contract, t.total_customers, t.total_churned, t.total_mrr
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 5 : CHURN RATE BY SENIOR CITIZEN STATUS
-- =============================================================================
-- Business objective:
--   Determine whether demographic factors moderate churn risk.
--
-- [M5] pct_of_base window replaced with CROSS JOIN total subquery.
--
-- Expected output:
--   SeniorCitizen | customers | pct_of_base | churn_rate_pct | avg_monthly
--   No            | 5,901     | 83.8%       | 23.6%          | ~$60.49
--   Yes           | 1,142     | 16.2%       | 41.7%          | ~$79.28
-- =============================================================================

SELECT
    c.SeniorCitizen,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                       AS avg_tenure_months
FROM customer_churn c
CROSS JOIN (SELECT COUNT(*) AS total_customers FROM customer_churn) t
GROUP BY c.SeniorCitizen, t.total_customers
ORDER BY c.SeniorCitizen;


-- =============================================================================
-- QUERY 6 : CHURN RATE BY PAYMENT METHOD
-- =============================================================================
-- Business objective:
--   Assess whether payment method is a meaningful churn predictor.
--
-- [M5] pct_of_base window replaced with CROSS JOIN total subquery.
--
-- Expected output:
--   PaymentMethod             | customers | churn_rate | avg_monthly
--   Electronic check          | 2,365     | 45.3%      | ~$74.53
--   Mailed check              | 1,612     | 19.1%      | ~$60.25
--   Bank transfer (automatic) | 1,544     | 16.7%      | ~$62.72
--   Credit card (automatic)   | 1,522     | 15.2%      | ~$61.35
-- =============================================================================

SELECT
    c.PaymentMethod,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                       AS avg_tenure_months
FROM customer_churn c
CROSS JOIN (SELECT COUNT(*) AS total_customers FROM customer_churn) t
GROUP BY c.PaymentMethod, t.total_customers
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 7 : CHURN RATE BY PAPERLESS BILLING
-- =============================================================================
-- Business objective:
--   Determine whether billing modality is an independent churn signal.
--
-- [M5] pct_of_base window replaced with CROSS JOIN total subquery.
--
-- Expected output:
--   PaperlessBilling | customers | churn_rate_pct | avg_monthly
--   Yes              | 4,171     | 33.6%          | ~$70.64
--   No               | 2,872     | 16.3%          | ~$55.42
-- =============================================================================

SELECT
    c.PaperlessBilling,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge
FROM customer_churn c
CROSS JOIN (SELECT COUNT(*) AS total_customers FROM customer_churn) t
GROUP BY c.PaperlessBilling, t.total_customers
ORDER BY c.PaperlessBilling;


-- =============================================================================
-- QUERY 8 : MONTH-TO-MONTH VS COMMITTED CONTRACT COMPARISON
-- =============================================================================
-- Business objective:
--   Quantify the business case for contract conversion programmes.
--
-- [M5] Two window calculations (pct_of_base, pct_of_total_mrr) replaced with
--      CROSS JOIN to a base_totals CTE.
-- [M6] GROUP BY contract_group alias: MySQL 8 supports this natively — no change.
--
-- Expected output:
--   contract_group              | customers | pct_base | churn_rate | total_mrr  | clv_proxy
--   Flexible (Month-to-month)   | 3,875     | 55.0%    | 42.7%      | $254,810   | ~$1,359
--   Committed (1-yr or 2-yr)    | 3,168     | 45.0%    |  6.3%      | $198,938   | ~$4,030
-- =============================================================================

WITH base_totals AS (
    SELECT
        COUNT(*)            AS total_customers,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    CASE
        WHEN c.Contract = 'Month-to-month' THEN 'Flexible (Month-to-month)'
        ELSE 'Committed (1-year or 2-year)'
    END                                                           AS contract_group,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / t.total_customers, 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges), 2)                               AS total_mrr,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / t.total_mrr, 1)         AS pct_of_total_mrr,
    -- CLV proxy: avg monthly charge × avg tenure
    ROUND(AVG(c.MonthlyCharges) * AVG(c.tenure), 2)               AS clv_proxy
FROM customer_churn c
CROSS JOIN base_totals t
GROUP BY contract_group, t.total_customers, t.total_mrr
ORDER BY churn_rate_pct DESC;
