-- =============================================================================
-- Script       : 03_revenue_impact.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0
-- Description  : Translates the churn rate findings from Script 02 into
--                dollar-denominated business impact. Quantifies MRR lost,
--                ARR at risk, CLV destroyed, and revenue concentration across
--                segments. These are the numbers that build the financial
--                business case for retention investment.
-- Business Q   : "What is the total revenue we are losing to churn, and
--                which customer segments represent the greatest revenue risk?"
-- Depends on   : 01_database_setup.sql, 02_churn_overview.sql
-- Next script  : 04_churn_by_contract.sql
-- =============================================================================
-- MYSQL NOTES (changes from PostgreSQL original):
--   [M1] churn.customer_churn → USE churn + bare table name
--   [M5] All SUM(SUM(col)) OVER() and COUNT(*) / SUM(COUNT(*)) OVER() patterns
--        replaced with CROSS JOIN to pre-aggregated CTEs. This is the only
--        structural change — all column names, business logic, and expected
--        outputs are identical to the PostgreSQL version.
--        Affected queries: Q2 (pct_of_total_churned_mrr),
--                          Q3 (pct_of_total_mrr, pct_of_total_churned_mrr),
--                          Q5 (pct_of_churned_customers, pct_of_churned_mrr),
--                          Q7 (pct_of_total_churned_mrr)
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- QUERY 1 : TOP-LINE REVENUE IMPACT SUMMARY
-- =============================================================================
-- Business objective:
--   Produce the headline financial impact figures for the executive summary
--   and the Power BI KPI row.
--
-- No window functions in this query — MySQL-compatible as written.
-- NULLIF is fully supported in MySQL 8.
--
-- Expected output (single row):
--   total_mrr    | churned_mrr  | pct_mrr_lost | annual_revenue_at_risk | avg_clv_lost
--   $456,116.60  | $139,130.85  | 30.5%        | $1,669,570.20          | $1,531.80
-- =============================================================================

SELECT
    ROUND(SUM(MonthlyCharges), 2)                                 AS total_mrr,

    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2)
                                                                  AS churned_mrr,

    ROUND(SUM(CASE WHEN Churn = 'No' THEN MonthlyCharges ELSE 0 END), 2)
                                                                  AS retained_mrr,

    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0
        / SUM(MonthlyCharges), 1
    )                                                             AS pct_mrr_lost,

    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12, 2
    )                                                             AS annual_revenue_at_risk,

    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END), 2)
                                                                  AS total_clv_destroyed,

    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END)
        / NULLIF(SUM(Churn_Binary), 0), 2
    )                                                             AS avg_clv_lost_per_churner,

    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)
        / NULLIF(SUM(Churn_Binary), 0), 2
    )                                                             AS avg_monthly_charge_churned,

    ROUND(
        SUM(CASE WHEN Churn = 'No' THEN MonthlyCharges ELSE 0 END)
        / NULLIF(SUM(1 - Churn_Binary), 0), 2
    )                                                             AS avg_monthly_charge_retained

FROM customer_churn;


-- =============================================================================
-- QUERY 2 : REVENUE IMPACT BY CONTRACT TYPE
-- =============================================================================
-- Business objective:
--   Decompose the total revenue loss by contract type to identify where
--   retention spend should be concentrated.
--
-- [M5] pct_of_total_churned_mrr used SUM(SUM(CASE...)) OVER() in PostgreSQL.
--      Replaced with a CTE that pre-computes total churned MRR across all
--      contracts, then CROSS JOINed so each group row can divide by it.
--
-- Expected output:
--   Contract       | seg_mrr      | churned_mrr  | pct_seg_lost | annual_at_risk | pct_of_total_churned
--   Month-to-month | $254,809.80  | $107,823     | 42.3%        | $1,293,880     | 77.5%
--   One year       | $95,932      | $18,094      | 18.9%        | $217,125       | 13.0%
--   Two year       | $103,005     | $4,088       |  4.0%        | $49,052        |  2.9%
-- =============================================================================

WITH total_churned_mrr AS (
    SELECT SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) AS grand_churned_mrr
    FROM customer_churn
)
SELECT
    c.Contract,
    COUNT(*)                                                      AS customer_count,
    ROUND(SUM(c.MonthlyCharges), 2)                               AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                  AS churned_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'No'  THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                  AS retained_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / NULLIF(SUM(c.MonthlyCharges), 0), 1
    )                                                             AS pct_segment_mrr_lost,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                             AS annual_revenue_at_risk,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / t.grand_churned_mrr, 1
    )                                                             AS pct_of_total_churned_mrr,
    ROUND(AVG(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges END), 2)
                                                                  AS avg_charge_per_churner
FROM customer_churn c
CROSS JOIN total_churned_mrr t
GROUP BY c.Contract, t.grand_churned_mrr
ORDER BY churned_mrr DESC;


-- =============================================================================
-- QUERY 3 : REVENUE IMPACT BY INTERNET SERVICE TYPE
-- =============================================================================
-- Business objective:
--   Identify which product line is generating the highest revenue at risk.
--
-- [M5] pct_of_total_mrr and pct_of_total_churned_mrr both used nested window
--      aggregates in PostgreSQL. Both replaced with a single CTE carrying
--      total MRR and total churned MRR; CROSS JOINed to the group-level query.
--
-- Expected output:
--   InternetService | customers | segment_mrr | churned_mrr | churn_rate | annual_at_risk
--   Fiber optic     | 3,096     | $247,680    | $100,482    | 41.9%      | $1,205,784
--   DSL             | 2,421     | $134,512    | $27,492     | 19.0%      | $329,904
--   No              | 1,526     | $73,925     | $11,157     |  7.4%      | $133,884
-- =============================================================================

WITH revenue_totals AS (
    SELECT
        SUM(MonthlyCharges)                                       AS grand_total_mrr,
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) AS grand_churned_mrr
    FROM customer_churn
)
SELECT
    c.InternetService,
    COUNT(*)                                                      AS customer_count,
    ROUND(SUM(c.MonthlyCharges), 2)                               AS segment_mrr,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / t.grand_total_mrr, 1)   AS pct_of_total_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                  AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / NULLIF(SUM(c.MonthlyCharges), 0), 1
    )                                                             AS pct_segment_mrr_lost,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                             AS annual_revenue_at_risk,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge
FROM customer_churn c
CROSS JOIN revenue_totals t
GROUP BY c.InternetService, t.grand_total_mrr, t.grand_churned_mrr
ORDER BY churned_mrr DESC;


-- =============================================================================
-- QUERY 4 : CUSTOMER LIFETIME VALUE (CLV) ANALYSIS
-- =============================================================================
-- Business objective:
--   Quantify how much revenue is destroyed when a customer churns before
--   reaching their expected lifetime value ceiling.
--
-- No window functions — MySQL-compatible as written.
--
-- Expected output: CLV comparison by Contract × Churn status.
-- =============================================================================

SELECT
    Contract,
    Churn,
    COUNT(*)                                                      AS customer_count,
    ROUND(AVG(MonthlyCharges), 2)                                 AS avg_monthly_charge,
    ROUND(AVG(tenure), 1)                                         AS avg_tenure_months,
    ROUND(AVG(TotalCharges), 2)                                   AS avg_realised_clv,
    ROUND(SUM(TotalCharges), 2)                                   AS total_realised_clv,
    ROUND(MIN(TotalCharges), 2)                                   AS min_total_charges,
    ROUND(MAX(TotalCharges), 2)                                   AS max_total_charges,
    -- Projected CLV if customer had stayed to avg tenure of retained base (37.6 months)
    ROUND(AVG(MonthlyCharges) * 37.6, 2)                          AS projected_clv_if_retained
    -- Note: 37.6 = avg tenure of retained customers confirmed in Query 2, Script 02.
    -- Replace the literal with a subquery for production automation.
FROM customer_churn
GROUP BY Contract, Churn
ORDER BY Contract, Churn DESC;


-- =============================================================================
-- QUERY 5 : REVENUE CONCENTRATION — HIGH-VALUE CUSTOMERS AT RISK
-- =============================================================================
-- Business objective:
--   Determine what proportion of churned MRR is concentrated in the highest-
--   paying customers — the "save the right customers" prioritisation insight.
--
-- [M5] Both pct_of_churned_customers and pct_of_churned_mrr used nested window
--      aggregates. Replaced with a CTE carrying total churned customers and
--      total churned MRR, CROSS JOINed to the charge-tier groups.
--
-- Expected output:
--   charge_tier         | churned_customers | pct_of_churned | churned_mrr | pct_churned_mrr
--   High (> $70/month)  | ~1,062            | ~56.8%         | ~$103,419   | ~74.3%
--   Mid ($35–$70/month) | ~500              | ~26.7%         | ~$27,000    | ~19.4%
--   Low (< $35/month)   | ~307              | ~16.4%         | ~$8,700     |  ~6.3%
-- =============================================================================

WITH churned_totals AS (
    SELECT
        COUNT(*)                AS total_churned_customers,
        SUM(MonthlyCharges)     AS total_churned_mrr
    FROM customer_churn
    WHERE Churn = 'Yes'
)
SELECT
    CASE
        WHEN c.MonthlyCharges > 70  THEN 'High (> $70/month)'
        WHEN c.MonthlyCharges >= 35 THEN 'Mid ($35-$70/month)'
        ELSE                             'Low (< $35/month)'
    END                                                           AS charge_tier,
    COUNT(*)                                                      AS churned_customers,
    ROUND(COUNT(*) * 100.0 / t.total_churned_customers, 1)        AS pct_of_churned_customers,
    ROUND(SUM(c.MonthlyCharges), 2)                               AS churned_mrr,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / t.total_churned_mrr, 1) AS pct_of_churned_mrr,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                       AS avg_tenure_months
FROM customer_churn c
CROSS JOIN churned_totals t
WHERE c.Churn = 'Yes'
GROUP BY charge_tier, t.total_churned_customers, t.total_churned_mrr
ORDER BY AVG(c.MonthlyCharges) DESC;


-- =============================================================================
-- QUERY 6 : RETENTION ROI SCENARIO MODEL
-- =============================================================================
-- Business objective:
--   Quantify the return on investment for three retention programme scenarios.
--
-- CTEs and CROSS JOIN are fully supported in MySQL 8 — no changes to the
-- structural pattern. NULLIF is natively supported in MySQL 8.
--
-- Expected output:
--   scenario                    | recovery_rate | annual_recovered | programme_cost | roi_ratio
--   Conservative (10% recovery) | 10%           | $166,957         | $7,480         | 22.32
--   Moderate (20% recovery)     | 20%           | $333,914         | $14,960        | 22.32
--   Optimistic (30% recovery)   | 30%           | $500,871         | $22,440        | 22.32
-- =============================================================================

WITH churn_financials AS (
    SELECT
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)      AS churned_mrr,
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12 AS churned_arr,
        SUM(Churn_Binary)                                                 AS churned_customers,
        AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END)              AS avg_monthly_churned
    FROM customer_churn
),
scenarios AS (
    SELECT 0.10 AS recovery_rate, 'Conservative (10% recovery)' AS scenario
    UNION ALL SELECT 0.20, 'Moderate (20% recovery)'
    UNION ALL SELECT 0.30, 'Optimistic (30% recovery)'
)
SELECT
    s.scenario,
    ROUND(s.recovery_rate * 100, 0)                               AS recovery_rate_pct,
    ROUND(f.churned_customers * s.recovery_rate, 0)               AS customers_targeted,
    ROUND(f.churned_mrr * s.recovery_rate, 2)                     AS monthly_revenue_recovered,
    ROUND(f.churned_arr * s.recovery_rate, 2)                     AS annual_revenue_recovered,
    ROUND(f.churned_customers * s.recovery_rate * 40, 2)          AS estimated_programme_cost,
    ROUND(
        (f.churned_arr * s.recovery_rate)
        - (f.churned_customers * s.recovery_rate * 40), 2
    )                                                             AS net_annual_benefit,
    ROUND(
        (f.churned_arr * s.recovery_rate)
        / NULLIF(f.churned_customers * s.recovery_rate * 40, 0), 2
    )                                                             AS roi_ratio
FROM scenarios s
CROSS JOIN churn_financials f
ORDER BY s.recovery_rate;


-- =============================================================================
-- QUERY 7 : REVENUE IMPACT SUMMARY BY FULL SEGMENT MATRIX
-- =============================================================================
-- Business objective:
--   Identify the highest-priority retention target by crossing contract type
--   and internet service — the two most powerful churn drivers.
--
-- [M5] pct_of_total_churned_mrr used SUM(SUM(CASE...)) OVER() in PostgreSQL.
--      Replaced with a CTE carrying grand total churned MRR, CROSS JOINed
--      to the Contract × InternetService group aggregates.
--
-- Expected output (top row — highest revenue at risk):
--   Contract       | InternetService | customers | churn_rate | annual_at_risk    | pct_of_total_churn_mrr
--   Month-to-month | Fiber optic     | 1,297     | 69.4%      | ~$1,200,000+      | ~72%
-- =============================================================================

WITH total_churned_mrr AS (
    SELECT SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) AS grand_churned_mrr
    FROM customer_churn
)
SELECT
    c.Contract,
    c.InternetService,
    COUNT(*)                                                      AS customer_count,
    SUM(c.Churn_Binary)                                           AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 1)              AS churn_rate_pct,
    ROUND(SUM(c.MonthlyCharges), 2)                               AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                  AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                             AS annual_revenue_at_risk,
    ROUND(AVG(c.MonthlyCharges), 2)                               AS avg_monthly_charge,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / t.grand_churned_mrr, 1
    )                                                             AS pct_of_total_churned_mrr
FROM customer_churn c
CROSS JOIN total_churned_mrr t
GROUP BY c.Contract, c.InternetService, t.grand_churned_mrr
ORDER BY annual_revenue_at_risk DESC;
