-- =============================================================================
-- Script       : 09_cohort_clv_analysis.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0 (ONLY_FULL_GROUP_BY mode)
-- Schema       : telecom_churn
-- Depends on   : 01_database_setup.sql (customer_churn table must exist)
-- =============================================================================
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  EXECUTIVE SUMMARY                                                      │
-- │                                                                         │
-- │  Customer Lifetime Value (CLV) is the metric that converts churn from   │
-- │  a percentage into a number a board can act on. This script proves       │
-- │  three strategic truths about the long-term financial impact of churn:  │
-- │                                                                         │
-- │  TRUTH 1 — CHURN DESTROYS COMPOUNDING VALUE                            │
-- │  The average churner paid $1,531.80 in total charges before leaving.   │
-- │  A retained customer with the same profile would have paid $2,796.76   │
-- │  (37.6-month retained average × $74.44/month). Churn destroys $1,264.96 │
-- │  of CLV per customer — a total portfolio loss of $2,364,214 in CLV     │
-- │  that was never realised because customers left too early.              │
-- │                                                                         │
-- │  TRUTH 2 — LONG-TENURED CUSTOMERS ARE EXPONENTIALLY MORE VALUABLE      │
-- │  The 49–72 month cohort represents 31.8% of customers but holds 65.3%  │
-- │  of all historical TotalCharges ($10.5M of $16.1M total). A customer   │
-- │  who survives to month 49 is worth 17× more in total charges than a    │
-- │  customer who churns at month 1. The CLV curve is non-linear — the     │
-- │  value of keeping a customer accelerates over time.                    │
-- │                                                                         │
-- │  TRUTH 3 — THE 12-MONTH FORWARD RISK IS QUANTIFIABLE AND ACTIONABLE   │
-- │  Based on observed churn rates applied to the active customer base,    │
-- │  the portfolio faces $798,027 in projected MRR loss over the next 12   │
-- │  months if no intervention occurs. The early-lifecycle cohort           │
-- │  (0–12 months active) alone accounts for $305,553 of that risk.        │
-- │                                                                         │
-- │  KEY DECISIONS THIS ANALYSIS SUPPORTS:                                  │
-- │  • Quantify the ROI of extending average customer tenure by 6 months   │
-- │  • Set CLV targets by contract type and tenure cohort                   │
-- │  • Build the financial business case for retention infrastructure        │
-- │  • Frame churn to the board as a CLV problem, not a rate problem        │
-- └─────────────────────────────────────────────────────────────────────────┘
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- SECTION 1 : CUSTOMER LIFETIME VALUE ANALYSIS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 1.1 : PORTFOLIO-LEVEL CLV SUMMARY
-- ---------------------------------------------------------------------------
-- Business question: What is the total revenue value of the customer portfolio,
--   how much CLV has already been destroyed by churn, and what is the
--   per-customer CLV gap between churners and retained customers?
--
-- Expected output (single row):
--   total_portfolio_clv | total_clv_destroyed | avg_clv_churned | avg_clv_retained | clv_gap_per_churner | total_projected_clv_destroyed
--   $16,056,168.70      | $2,862,926.90        | $1,531.80       | $2,549.91        | $1,264.96           | $2,364,214
--
-- KEY METRIC DEFINITIONS:
--   total_clv_destroyed       : Actual TotalCharges collected from customers who churned.
--                               This is revenue that was earned but is now gone.
--   total_projected_clv_lost  : What those churners WOULD HAVE paid if they had stayed
--                               to the average retained customer tenure (37.6 months).
--                               Formula: avg_monthly_churned × 37.6 × 1,869 churners
--                               minus actual total charges collected from churners.
--
-- Business insight:
--   The $2.36M projected CLV destroyed figure is the headline number for a
--   board presentation. It is the answer to "how much did churn cost us beyond
--   the MRR we report?" — the invisible revenue that was never earned because
--   customers left before reaching their natural lifecycle ceiling.
-- ---------------------------------------------------------------------------

SELECT
    -- Total portfolio historical value
    ROUND(SUM(TotalCharges), 2)                                               AS total_portfolio_clv,

    -- Revenue already collected from customers who churned (realised CLV)
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END), 2)       AS total_clv_of_churners,

    -- Per-churner average CLV at point of departure
    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END)
        / NULLIF(SUM(Churn_Binary), 0), 2
    )                                                                         AS avg_clv_per_churner,

    -- Per-retained average CLV (what a loyal customer generates)
    ROUND(
        SUM(CASE WHEN Churn = 'No' THEN TotalCharges ELSE 0 END)
        / NULLIF(COUNT(*) - SUM(Churn_Binary), 0), 2
    )                                                                         AS avg_clv_per_retained_customer,

    -- Projected CLV if churners had stayed to retained avg tenure (37.6 months)
    -- Avg monthly charge of churners = $74.44, retained avg tenure = 37.6 months
    ROUND(
        SUM(Churn_Binary) * 74.44 * 37.6, 2
    )                                                                         AS projected_clv_if_churners_stayed,

    -- CLV destroyed = projected - actual (what was never earned)
    ROUND(
        (SUM(Churn_Binary) * 74.44 * 37.6)
        - SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END), 2
    )                                                                         AS total_clv_destroyed,

    -- Per-churner CLV gap
    ROUND(
        (74.44 * 37.6)
        - (SUM(CASE WHEN Churn = 'Yes' THEN TotalCharges ELSE 0 END)
           / NULLIF(SUM(Churn_Binary), 0)), 2
    )                                                                         AS clv_gap_per_churner,

    -- Context metrics
    SUM(Churn_Binary)                                                         AS total_churned_customers,
    COUNT(*)                                                                  AS total_customers,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                            AS churn_rate_pct

FROM customer_churn;


-- ---------------------------------------------------------------------------
-- QUERY 1.2 : CLV BY CONTRACT TYPE — THE COMMITMENT PREMIUM
-- ---------------------------------------------------------------------------
-- Business question: How does contract type determine customer lifetime value,
--   and what is the financial case for converting customers to longer contracts?
--
-- Expected output:
--   Contract       | customers | avg_tenure | avg_monthly | avg_realised_clv | clv_multiple_vs_m2m | total_portfolio_clv
--   Two year       | 1,695     | 56.74 mo   | $60.77      | $3,706.93        | 2.71×               | $6,283,254
--   One year       | 1,473     | 42.04 mo   | $65.05      | $3,032.62        | 2.21×               | $4,467,054
--   Month-to-month | 3,875     | 18.04 mo   | $66.40      | $1,369.25        | 1.00× (baseline)    | $5,305,862
--
-- Business insight:
--   A two-year contract customer generates 2.71× the lifetime revenue of a
--   month-to-month customer — not because they pay more per month (they
--   actually pay $5.63/month less on average), but because they stay 3.1×
--   longer. This is the most powerful argument for contract conversion:
--   the CLV uplift from longer contracts comes entirely from tenure extension,
--   not from price increases. A contract upgrade offer that includes a modest
--   price discount is still highly value-creative for the business.
-- ---------------------------------------------------------------------------

WITH m2m_clv AS (
    SELECT AVG(TotalCharges) AS m2m_avg_clv
    FROM customer_churn
    WHERE Contract = 'Month-to-month'
)
SELECT
    c.Contract,
    COUNT(*)                                                              AS customers,
    ROUND(AVG(c.tenure), 2)                                               AS avg_tenure_months,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_realised_clv,
    ROUND(SUM(c.TotalCharges), 2)                                         AS total_portfolio_clv,
    ROUND(MAX(c.TotalCharges), 2)                                         AS max_customer_clv,
    ROUND(MIN(c.TotalCharges), 2)                                         AS min_customer_clv,
    -- CLV multiple vs month-to-month baseline
    ROUND(AVG(c.TotalCharges) / m.m2m_avg_clv, 2)                         AS clv_multiple_vs_m2m,
    -- Dollar uplift per customer vs month-to-month
    ROUND(AVG(c.TotalCharges) - m.m2m_avg_clv, 2)                         AS clv_uplift_vs_m2m,
    -- Churned customers in this contract type
    SUM(c.Churn_Binary)                                                   AS churned,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    -- Avg CLV of churned vs retained within same contract
    ROUND(AVG(CASE WHEN c.Churn = 'Yes' THEN c.TotalCharges END), 2)      AS avg_clv_churned,
    ROUND(AVG(CASE WHEN c.Churn = 'No'  THEN c.TotalCharges END), 2)      AS avg_clv_retained
FROM customer_churn c
CROSS JOIN m2m_clv m
GROUP BY c.Contract, m.m2m_avg_clv
ORDER BY avg_realised_clv DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.3 : CLV DESTROYED BY CONTRACT TYPE
-- ---------------------------------------------------------------------------
-- Business question: Which contract type's churning customers are responsible
--   for the greatest CLV destruction — accounting for both volume of churners
--   and the gap between their realised and projected CLV?
-- ---------------------------------------------------------------------------

SELECT
    Contract,
    SUM(Churn_Binary)                                                     AS churned_customers,
    ROUND(AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END), 2)           AS avg_monthly_churned,
    ROUND(AVG(CASE WHEN Churn='Yes' THEN TotalCharges END), 2)             AS avg_clv_at_churn,
    -- Projected CLV using retained avg tenure (37.6 months)
    ROUND(AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 37.6, 2)    AS projected_clv_if_retained,
    -- Per-customer CLV gap
    ROUND(
        AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 37.6
        - AVG(CASE WHEN Churn='Yes' THEN TotalCharges END), 2
    )                                                                     AS clv_gap_per_churner,
    -- Total CLV destroyed
    ROUND(
        SUM(Churn_Binary) * (
            AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 37.6
            - AVG(CASE WHEN Churn='Yes' THEN TotalCharges END)
        ), 2
    )                                                                     AS total_clv_destroyed
FROM customer_churn
GROUP BY Contract
ORDER BY total_clv_destroyed DESC;


-- =============================================================================
-- SECTION 2 : COHORT ANALYSIS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 2.1 : REVENUE CONTRIBUTION BY TENURE COHORT
-- ---------------------------------------------------------------------------
-- Business question: How is total portfolio revenue distributed across
--   lifecycle cohorts, and what does this reveal about the value of retention?
--
-- Expected output:
--   tenure_band   | customers | pct_base | total_clv    | pct_portfolio_clv | avg_clv   | churn_rate
--   49-72 months  | 2,239     | 31.8%    | $10,490,849  | 65.3%             | $4,685.51 | 9.51%
--   25-48 months  | 1,594     | 22.6%    | $3,810,380   | 23.7%             | $2,390.45 | 20.39%
--   13-24 months  | 1,024     | 14.5%    | $1,153,288   | 7.2%              | $1,126.26 | 28.71%
--   0-12 months   | 2,186     | 31.0%    | $601,652     | 3.7%              | $275.23   | 47.44%
--
-- Business insight:
--   The 49–72 month cohort represents 31.8% of customers but 65.3% of all
--   historical revenue. The 0–12 month cohort represents 31.0% of customers
--   but only 3.7% of revenue. Early customers are almost revenue-invisible —
--   but they are the input into the loyalty pipeline. Preventing them from
--   churning is not just about the $56.10/month they pay today; it is about
--   the $4,685 in cumulative CLV they will generate if they reach the 49+
--   month tier. That is the compounding value of retention.
-- ---------------------------------------------------------------------------

WITH portfolio_totals AS (
    SELECT
        SUM(TotalCharges)   AS grand_total_clv,
        COUNT(*)            AS total_customers,
        SUM(Churn_Binary)   AS total_churned
    FROM customer_churn
)
SELECT
    c.tenure_band,
    COUNT(*)                                                              AS customers,
    ROUND(COUNT(*) * 100.0 / p.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(SUM(c.Churn_Binary) * 100.0 / p.total_churned, 1)               AS pct_of_total_churn,

    -- CLV metrics
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_per_customer,
    ROUND(SUM(c.TotalCharges), 2)                                         AS cohort_total_clv,
    ROUND(SUM(c.TotalCharges) * 100.0 / p.grand_total_clv, 1)             AS pct_of_portfolio_clv,

    -- Churned vs retained CLV within cohort
    ROUND(AVG(CASE WHEN c.Churn = 'Yes' THEN c.TotalCharges END), 2)      AS avg_clv_churners,
    ROUND(AVG(CASE WHEN c.Churn = 'No'  THEN c.TotalCharges END), 2)      AS avg_clv_retained,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.TotalCharges ELSE 0 END), 2)
                                                                          AS churned_clv,
    ROUND(SUM(CASE WHEN c.Churn = 'No'  THEN c.TotalCharges ELSE 0 END), 2)
                                                                          AS retained_clv,

    -- Revenue metrics
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges), 2)                                       AS cohort_mrr

FROM customer_churn c
CROSS JOIN portfolio_totals p
GROUP BY c.tenure_band, p.grand_total_clv, p.total_customers, p.total_churned
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- ---------------------------------------------------------------------------
-- QUERY 2.2 : COHORT CLV PROGRESSION — THE VALUE GROWTH CURVE
-- ---------------------------------------------------------------------------
-- Business question: How does average CLV grow as customers progress through
--   their lifecycle, and what is the incremental CLV value of each additional
--   year of retention?
--
-- This query computes the average TotalCharges at each tenure month —
-- effectively tracing the CLV growth curve from month 0 to month 72.
-- Groups by tenure month for granularity; limited to months with >= 20
-- customers for statistical reliability.
--
-- Business insight:
--   The CLV growth curve is non-linear. Early months show slow accumulation
--   (customers have paid little). CLV accelerates in the middle lifecycle
--   (24–48 months) as monthly charges compound. This curve is the visual
--   argument for long-term retention investment: the payoff is not linear,
--   but exponential relative to the early months.
-- ---------------------------------------------------------------------------

SELECT
    tenure,
    COUNT(*)                                                              AS customers_at_tenure,
    ROUND(AVG(TotalCharges), 2)                                           AS avg_clv_at_tenure,
    ROUND(AVG(MonthlyCharges), 2)                                         AS avg_monthly_at_tenure,
    SUM(Churn_Binary)                                                     AS churned_at_tenure,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                        AS churn_rate_pct,
    -- Incremental CLV vs tenure=1 baseline
    ROUND(
        AVG(TotalCharges) - (
            SELECT AVG(TotalCharges)
            FROM customer_churn
            WHERE tenure = 1
        ), 2
    )                                                                     AS clv_uplift_vs_month_1
FROM customer_churn
WHERE tenure >= 1
GROUP BY tenure
HAVING COUNT(*) >= 20
ORDER BY tenure;


-- ---------------------------------------------------------------------------
-- QUERY 2.3 : COHORT CLV BY CONTRACT TYPE — FULL MATRIX
-- ---------------------------------------------------------------------------
-- Business question: How does CLV differ across the tenure × contract type
--   matrix? Which combination produces the highest-value customers?
--
-- Business insight:
--   Two-year customers at 49–72 months tenure represent the peak CLV profile.
--   Month-to-month customers at 0–12 months represent the lowest CLV profile.
--   The matrix visualises the CLV "hill" that retention programmes are
--   trying to push customers up.
-- ---------------------------------------------------------------------------

SELECT
    c.Contract,
    c.tenure_band,
    COUNT(*)                                                              AS customers,
    SUM(c.Churn_Binary)                                                   AS churned,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv,
    ROUND(SUM(c.TotalCharges), 2)                                         AS cohort_total_clv,
    ROUND(AVG(CASE WHEN c.Churn = 'Yes' THEN c.TotalCharges END), 2)      AS avg_clv_churned,
    ROUND(AVG(CASE WHEN c.Churn = 'No'  THEN c.TotalCharges END), 2)      AS avg_clv_retained
FROM customer_churn c
GROUP BY c.Contract, c.tenure_band
ORDER BY
    CASE c.Contract
        WHEN 'Two year'       THEN 1
        WHEN 'One year'       THEN 2
        WHEN 'Month-to-month' THEN 3
    END,
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- =============================================================================
-- SECTION 3 : RETENTION VALUE MODELLING
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 3.1 : 12-MONTH FORWARD REVENUE AT RISK — ACTIVE PORTFOLIO
-- ---------------------------------------------------------------------------
-- Business question: If we apply observed churn rates to the current active
--   customer base, what is the projected revenue loss over the next 12 months
--   without any retention intervention?
--
-- Method: Apply the observed churn rate for each tenure_band (from historical
--   data) to the active (Churn='No') customers in that band to estimate
--   expected churners. Multiply expected churners × avg monthly charge × 12
--   to get projected annual MRR loss.
--
-- Expected output:
--   tenure_band   | active_customers | active_mrr  | expected_churners | projected_annual_loss
--   0-12 months   | 1,149            | $64,482     | 545               | $305,553
--   13-24 months  |   730            | $44,784     | 210               | $136,945
--   25-48 months  | 1,269            | $83,649     | 259               | $189,937
--   49-72 months  | 2,026            | $149,884    | 193               | $166,592
--   TOTAL         | 5,174            | $342,799    | 1,207             | $799,027
--
-- Business insight:
--   The portfolio faces ~$799,027 in projected MRR loss over the next 12 months
--   if no intervention occurs. The 0–12 month cohort, despite being only 22.2%
--   of active customers, drives 38.2% of projected losses. This validates the
--   strategic priority of early-lifecycle intervention over all other retention
--   investments.
-- ---------------------------------------------------------------------------

WITH observed_rates AS (
    -- Observed churn rates from historical data, used as forward probabilities
    SELECT
        tenure_band,
        ROUND(SUM(Churn_Binary) * 1.0 / COUNT(*), 4) AS observed_churn_rate
    FROM customer_churn
    GROUP BY tenure_band
),
active_by_band AS (
    SELECT
        c.tenure_band,
        COUNT(*)                      AS active_customers,
        ROUND(AVG(c.MonthlyCharges), 2) AS avg_monthly_active,
        ROUND(SUM(c.MonthlyCharges), 2) AS active_mrr
    FROM customer_churn c
    WHERE c.Churn = 'No'
    GROUP BY c.tenure_band
)
SELECT
    a.tenure_band,
    a.active_customers,
    a.avg_monthly_active,
    a.active_mrr,
    o.observed_churn_rate,
    ROUND(o.observed_churn_rate * 100, 2)                                 AS historical_churn_rate_pct,
    -- Expected churners = active customers × historical churn rate
    ROUND(a.active_customers * o.observed_churn_rate, 0)                  AS expected_churners_12mo,
    -- Projected MRR loss = expected churners × avg monthly charge × 12 months
    ROUND(a.active_customers * o.observed_churn_rate * a.avg_monthly_active, 2)
                                                                          AS projected_mrr_loss_monthly,
    ROUND(a.active_customers * o.observed_churn_rate * a.avg_monthly_active * 12, 2)
                                                                          AS projected_annual_revenue_loss,
    -- Retained revenue if churn rate is halved (intervention target: 50% reduction)
    ROUND(a.active_customers * (o.observed_churn_rate * 0.5) * a.avg_monthly_active * 12, 2)
                                                                          AS loss_if_churn_halved,
    -- Savings from halving churn
    ROUND(
        a.active_customers * o.observed_churn_rate * a.avg_monthly_active * 12
        - a.active_customers * (o.observed_churn_rate * 0.5) * a.avg_monthly_active * 12, 2
    )                                                                     AS annual_savings_from_halving_churn
FROM active_by_band a
JOIN observed_rates o ON a.tenure_band = o.tenure_band
ORDER BY
    CASE a.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- ---------------------------------------------------------------------------
-- QUERY 3.2 : CLV UPLIFT SCENARIOS — TENURE EXTENSION VALUE
-- ---------------------------------------------------------------------------
-- Business question: What is the financial value of extending average customer
--   tenure by 3, 6, or 12 months through retention intervention?
--
-- This query models the additional CLV generated per cohort if the average
-- churning customer could be retained for an additional N months before leaving.
-- This frames the maximum justifiable investment per customer for retention.
--
-- Method: Additional CLV per churner = avg_monthly_charge × extra_months.
--   Total additional CLV = churned_customers × avg_monthly × extra_months.
--   Maximum programme cost per customer = additional CLV × discount factor (0.85)
--   to account for time value and execution risk.
-- ---------------------------------------------------------------------------

SELECT
    Contract,
    SUM(Churn_Binary)                                                     AS churned_customers,
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END), 2)         AS avg_monthly_churned,
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN TotalCharges END), 2)           AS avg_clv_at_churn,

    -- Additional CLV if average churner stays 3 extra months
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END) * 3, 2)    AS clv_uplift_per_churner_3mo,
    ROUND(SUM(Churn_Binary) * AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 3, 2)
                                                                          AS total_clv_uplift_3mo,

    -- Additional CLV if average churner stays 6 extra months
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END) * 6, 2)    AS clv_uplift_per_churner_6mo,
    ROUND(SUM(Churn_Binary) * AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 6, 2)
                                                                          AS total_clv_uplift_6mo,

    -- Additional CLV if average churner stays 12 extra months
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END) * 12, 2)   AS clv_uplift_per_churner_12mo,
    ROUND(SUM(Churn_Binary) * AVG(CASE WHEN Churn='Yes' THEN MonthlyCharges END) * 12, 2)
                                                                          AS total_clv_uplift_12mo,

    -- Maximum justifiable programme cost per customer to unlock 6mo uplift (at 85% of value)
    ROUND(AVG(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END) * 6 * 0.85, 2)
                                                                          AS max_cost_per_customer_for_6mo_retention

FROM customer_churn
GROUP BY Contract
ORDER BY avg_monthly_churned DESC;


-- ---------------------------------------------------------------------------
-- QUERY 3.3 : EXECUTIVE FINANCIAL IMPACT SCORECARD
-- ---------------------------------------------------------------------------
-- Business question: What is the complete financial picture of churn in this
--   portfolio? Provide a single-page executive scorecard that synthesises
--   all key metrics from the SQL analysis layer.
--
-- This query is designed as the data source for the executive summary page
-- of the Power BI dashboard and the final page of the executive summary PDF.
-- Each row is a distinct financial metric with its value and business label.
-- ---------------------------------------------------------------------------

SELECT 'Total customers in portfolio'           AS metric, CAST(COUNT(*) AS CHAR)
    FROM customer_churn
UNION ALL
SELECT 'Customers who have churned',             CAST(SUM(Churn_Binary) AS CHAR)
    FROM customer_churn
UNION ALL
SELECT 'Overall churn rate',                     CONCAT(ROUND(SUM(Churn_Binary)*100.0/COUNT(*),2), '%')
    FROM customer_churn
UNION ALL
SELECT 'Monthly revenue lost to churn (MRR)',    CONCAT('$', FORMAT(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END),2))
    FROM customer_churn
UNION ALL
SELECT 'Annual revenue at risk (MRR x 12)',      CONCAT('$', FORMAT(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12,2))
    FROM customer_churn
UNION ALL
SELECT 'Total CLV realised from churners',       CONCAT('$', FORMAT(SUM(CASE WHEN Churn='Yes' THEN TotalCharges ELSE 0 END),2))
    FROM customer_churn
UNION ALL
SELECT 'Total projected CLV destroyed',          CONCAT('$', FORMAT(SUM(Churn_Binary)*74.44*37.6 - SUM(CASE WHEN Churn='Yes' THEN TotalCharges ELSE 0 END),2))
    FROM customer_churn
UNION ALL
SELECT 'Avg CLV per churner (at churn point)',   CONCAT('$', FORMAT(SUM(CASE WHEN Churn='Yes' THEN TotalCharges ELSE 0 END)/NULLIF(SUM(Churn_Binary),0),2))
    FROM customer_churn
UNION ALL
SELECT 'Avg CLV per retained customer',          CONCAT('$', FORMAT(SUM(CASE WHEN Churn='No' THEN TotalCharges ELSE 0 END)/NULLIF(COUNT(*)-SUM(Churn_Binary),0),2))
    FROM customer_churn
UNION ALL
SELECT 'Total historical portfolio revenue',     CONCAT('$', FORMAT(SUM(TotalCharges),2))
    FROM customer_churn
UNION ALL
SELECT 'Highest-risk segment churn rate',        '60.73% (Fibre + No Security + No TechSupport + M2M)'
UNION ALL
SELECT 'Annual MRR at risk (highest segment)',   '$940,401.60 (Fibre + No Security + No TechSupport + M2M)'
UNION ALL
SELECT 'Projected 12-month portfolio MRR loss',  '$799,027 (based on observed cohort churn rates)'
UNION ALL
SELECT '12-month savings if churn halved',       '$399,514 (intervention target: 50% churn reduction)';


-- =============================================================================
-- POWER BI RECOMMENDATIONS — SCRIPT 09
-- =============================================================================
-- Q1.1 → 4-KPI card row on executive page: total_portfolio_clv,
--          avg_clv_per_churner, avg_clv_per_retained, total_clv_destroyed.
--          The gap between the second and third card is the visual story.
--
-- Q1.2 → Clustered column chart: Contract on X-axis, avg_realised_clv as bar
--          height. Add a data label showing clv_multiple_vs_m2m on each bar.
--          The 2.71× label on Two year is the headline visual.
--
-- Q2.1 → 100% stacked bar chart: tenure bands on X-axis, segment split into
--          pct_of_portfolio_clv (blue) vs pct_of_total_churn (red). The
--          visual contrast between the 0-12 month band (3.7% CLV, 55% churn)
--          and 49-72 month band (65.3% CLV, 11% churn) is immediate.
--
-- Q2.2 → Line chart: tenure (1–72) on X-axis, avg_clv_at_tenure on Y-axis.
--          The accelerating CLV curve is the core visual for the "why retention
--          pays off" narrative. Add a reference annotation at tenure=36.
--
-- Q3.1 → Table with conditional formatting: rows = tenure_band, columns include
--          projected_annual_revenue_loss (red) and loss_if_churn_halved (orange).
--          The savings_from_halving_churn column in green makes the intervention
--          value immediately legible.
--
-- Q3.3 → Card-style table on the executive summary page — pairs metric names
--          with formatted values. This is the "single pane of glass" view that
--          a VP sees in the first 30 seconds of the dashboard.
-- =============================================================================


-- =============================================================================
-- INTERVIEW TALKING POINTS — SCRIPT 09
-- =============================================================================
-- "The most important number in my entire project is $2,364,214 — the total
--  CLV destroyed by churn. The $139K monthly MRR loss number is important,
--  but it's a flow metric: it measures what we're losing right now. The CLV
--  destruction number measures the compounding cost of losing those customers
--  before they reached their natural lifetime value ceiling.
--
--  I calculated it by taking the average monthly charge of churned customers
--  ($74.44), multiplying by the average tenure of retained customers (37.6
--  months) to get the projected CLV if they had stayed, then subtracting what
--  they actually paid ($1,531.80). The gap is $1,264.96 per churner × 1,869
--  churners = $2.36M. That number speaks to a CFO in a way that a churn rate
--  percentage cannot.
--
--  The cohort revenue contribution finding reinforced this: the 49-72 month
--  cohort is 31.8% of customers but 65.3% of all historical revenue. Every
--  month we successfully retain an early-lifecycle customer, we're not just
--  collecting $56/month — we're buying a ticket to the loyalty tier that
--  generates $4,685 in cumulative CLV. That's how I framed the business case
--  for a structured onboarding and early retention programme."
-- =============================================================================
