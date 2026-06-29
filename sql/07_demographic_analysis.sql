-- =============================================================================
-- Script       : 07_demographic_analysis.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0 (ONLY_FULL_GROUP_BY mode)
-- Schema       : telecom_churn
-- Depends on   : 01_database_setup.sql (customer_churn table must exist)
-- Next script  : 08_high_value_at_risk.sql
-- =============================================================================
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  EXECUTIVE SUMMARY                                                      │
-- │                                                                         │
-- │  Demographics do not drive churn equally. Gender is essentially         │
-- │  irrelevant (26.92% female vs 26.16% male — a statistically noise-      │
-- │  level difference). But three demographic factors create meaningful      │
-- │  risk stratification:                                                   │
-- │                                                                         │
-- │  SENIOR CITIZENS churn at 41.68% — 1.76× the non-senior rate of        │
-- │  23.61%. This gap widens dramatically in month-to-month contracts:      │
-- │  senior + M2M = 54.65% churn rate, the highest single-variable          │
-- │  demographic risk profile in the dataset.                               │
-- │                                                                         │
-- │  CUSTOMERS WITHOUT A PARTNER churn at 32.96% vs 19.66% for those       │
-- │  with a partner — a 13-point gap that likely reflects household          │
-- │  economics and decision-making inertia. A household with two people      │
-- │  sharing a service has a higher perceived switching cost.               │
-- │                                                                         │
-- │  CUSTOMERS WITHOUT DEPENDENTS churn at 31.28% vs 15.45% for those      │
-- │  with dependents — the largest proportional gap across all four          │
-- │  demographic factors. Families are the most stable customer segment.    │
-- │                                                                         │
-- │  The highest-risk demographic profile confirmed: Senior citizen,         │
-- │  no partner, no dependents, month-to-month contract — 58.15% churn     │
-- │  rate, 454 customers, $20,475.90/month in churned MRR.                 │
-- │                                                                         │
-- │  KEY DECISIONS THIS ANALYSIS SUPPORTS:                                  │
-- │  • Prioritise senior citizen outreach as a dedicated retention track    │
-- │  • Include household/family context in retention offer design            │
-- │  • Do not over-invest in gender-based segmentation for churn purposes   │
-- │  • Use demographic profile as a risk multiplier in the churn score      │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- ONLY_FULL_GROUP_BY COMPLIANCE NOTES:
--   All SELECT columns are either in the GROUP BY clause or inside a valid
--   aggregate function (SUM, AVG, COUNT, MIN, MAX, ROUND).
--   No bare column references appear outside aggregates or GROUP BY lists.
--   Window functions (COUNT(*) OVER()) are fully compatible with MySQL 8.0
--   ONLY_FULL_GROUP_BY when used as true window functions, not nested inside
--   group aggregates. Where grand totals are needed, pre-aggregated CTEs
--   with CROSS JOIN are used instead of SUM(SUM()) OVER() patterns.
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- SECTION 1 : SINGLE-FACTOR DEMOGRAPHIC CHURN ANALYSIS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 1.1 : GENDER CHURN ANALYSIS
-- ---------------------------------------------------------------------------
-- Business question: Does gender predict churn risk in our customer base?
--
-- Expected output:
--   gender | customers | churn_rate_pct | avg_monthly | avg_tenure | churned_mrr
--   Female | 3,488     | 26.92%         | $65.20      | 32.24 mo   | $70,248.55
--   Male   | 3,555     | 26.16%         | $64.33      | 32.50 mo   | $68,882.30
--
-- Business insight:
--   Gender has virtually no predictive power for churn (0.76pp gap).
--   This is a critical finding in itself — it rules out gender as a
--   segmentation variable for retention campaigns, preventing wasted spend
--   on gender-targeted interventions that the data does not support.
--   Allocate zero incremental retention budget to gender-based targeting.
-- ---------------------------------------------------------------------------

WITH base_totals AS (
    SELECT
        COUNT(*)            AS total_customers,
        SUM(Churn_Binary)   AS total_churned,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    c.gender,
    COUNT(*)                                                              AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                        AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_realised,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
CROSS JOIN base_totals b
GROUP BY c.gender, b.total_customers, b.total_churned, b.total_mrr
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.2 : SENIOR CITIZEN CHURN ANALYSIS
-- ---------------------------------------------------------------------------
-- Business question: Are senior citizens a high-risk churn segment, and if
--   so, what is the revenue and retention impact of their elevated churn rate?
--
-- Expected output:
--   SeniorCitizen | customers | pct_base | churn_rate | avg_monthly | churned_mrr | annual_at_risk
--   Yes           | 1,142     | 16.2%    | 41.68%     | $79.82      | $38,419.60  | $460,867
--   No            | 5,901     | 83.8%    | 23.61%     | $61.85      | $100,711.25 | $1,208,535
--
-- Business insight:
--   Senior citizens churn at 41.68% — 1.76× the non-senior rate. They also
--   pay 29% more per month on average ($79.82 vs $61.85), meaning each senior
--   churner destroys more revenue than an average churner. The combination of
--   higher price sensitivity, lower digital self-service adoption, and greater
--   reliance on support makes seniors both more likely to churn and more costly
--   to lose. A dedicated senior retention programme (e.g. assigned account
--   manager, proactive support check-ins at months 1 and 6) is justified by
--   the revenue concentration in this segment.
-- ---------------------------------------------------------------------------

WITH base_totals AS (
    SELECT
        COUNT(*)            AS total_customers,
        SUM(Churn_Binary)   AS total_churned,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    c.SeniorCitizen,
    COUNT(*)                                                              AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                        AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_realised,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk,
    -- Revenue at risk as share of total churned revenue
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / b.total_mrr, 1
    )                                                                     AS pct_of_total_mrr_lost
FROM customer_churn c
CROSS JOIN base_totals b
GROUP BY c.SeniorCitizen, b.total_customers, b.total_churned, b.total_mrr
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.3 : PARTNER STATUS CHURN ANALYSIS
-- ---------------------------------------------------------------------------
-- Business question: Does having a partner reduce churn, and should we
--   design retention offers that acknowledge household decision-making?
--
-- Expected output:
--   Partner | customers | churn_rate | avg_monthly | avg_tenure | churned_mrr
--   No      | 3,641     | 32.96%     | $61.95      | 23.36 mo   | $85,741.15
--   Yes     | 3,402     | 19.66%     | $67.78      | 42.02 mo   | $53,389.70
--
-- Business insight:
--   Customers without a partner churn at 32.96% — 13.3 points higher than
--   those with a partner. They also have significantly lower average tenure
--   (23.36 vs 42.02 months), suggesting that single-person households either
--   acquire the service with less intent to commit or switch more freely.
--   Retention offers that frame value in household terms ("share with family",
--   "add a line") may not resonate with this segment — price and service
--   reliability are likely stronger motivators for solo subscribers.
-- ---------------------------------------------------------------------------

WITH base_totals AS (
    SELECT
        COUNT(*)            AS total_customers,
        SUM(Churn_Binary)   AS total_churned,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    c.Partner,
    COUNT(*)                                                              AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                        AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_realised,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
CROSS JOIN base_totals b
GROUP BY c.Partner, b.total_customers, b.total_churned, b.total_mrr
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.4 : DEPENDENTS CHURN ANALYSIS
-- ---------------------------------------------------------------------------
-- Business question: Are customers with dependents (children, elderly family
--   members) meaningfully more loyal, and how does this affect retention strategy?
--
-- Expected output:
--   Dependents | customers | churn_rate | avg_monthly | avg_tenure | churned_mrr
--   No         | 4,933     | 31.28%     | $67.00      | 29.81 mo   | $115,376.50
--   Yes        | 2,110     | 15.45%     | $59.52      | 38.37 mo   | $23,754.35
--
-- Business insight:
--   Customers with dependents churn at half the rate of those without (15.45%
--   vs 31.28%). This is the largest single-variable protective demographic
--   effect in the dataset. Families are extraordinarily stable customers —
--   service disruption carries higher household cost, and switching friction
--   is multiplied by the number of dependent users.
--   However, they pay $7.48/month less on average, suggesting they may be on
--   lower-tier plans. A cross-sell programme for family-tier customers (multi-
--   device plans, parental controls, streaming bundles) could raise ARPU while
--   reinforcing the existing loyalty advantage.
-- ---------------------------------------------------------------------------

WITH base_totals AS (
    SELECT
        COUNT(*)            AS total_customers,
        SUM(Churn_Binary)   AS total_churned,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    c.Dependents,
    COUNT(*)                                                              AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                        AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_realised,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
CROSS JOIN base_totals b
GROUP BY c.Dependents, b.total_customers, b.total_churned, b.total_mrr
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- SECTION 2 : TWO-FACTOR DEMOGRAPHIC COMBINATIONS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 2.1 : SENIOR CITIZEN × PARTNER STATUS
-- ---------------------------------------------------------------------------
-- Business question: Does having a partner buffer the churn risk of senior
--   citizens, and which of the four sub-segments is most urgent to target?
--
-- Expected output:
--   SeniorCitizen | Partner | customers | churn_rate | avg_monthly
--   Yes           | No      |   569     | 48.86%     | $76.84
--   Yes           | Yes     |   573     | 34.55%     | $82.78
--   No            | No      | 3,072     | 30.01%     | $59.19
--   No            | Yes     | 2,829     | 16.65%     | $64.74
--
-- Business insight:
--   Senior citizens without a partner are the highest-risk demographic
--   sub-segment at 48.86%. Having a partner reduces the senior churn rate
--   by 14 points — but even senior citizens WITH a partner churn at 34.55%,
--   still well above the overall average. This confirms that senior status
--   is an independent risk multiplier that no other demographic factor
--   fully offsets. A dedicated senior retention programme is warranted
--   regardless of household composition.
-- ---------------------------------------------------------------------------

SELECT
    c.SeniorCitizen,
    c.Partner,
    COUNT(*)                                                              AS total_customers,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
GROUP BY c.SeniorCitizen, c.Partner
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 2.2 : PARTNER × DEPENDENTS — HOUSEHOLD STABILITY MATRIX
-- ---------------------------------------------------------------------------
-- Business question: Which household composition produces the most stable
--   customer, and which produces the highest churn risk?
--
-- Expected output:
--   Partner | Dependents | customers | churn_rate | avg_monthly | avg_tenure
--   No      | No         | 3,280     | 34.24%     | $62.98      | [shortest]
--   Yes     | No         | 1,653     | 25.41%     | $74.98      |
--   No      | Yes        |   361     | 21.33%     | $52.51      |
--   Yes     | Yes        | 1,749     | 14.24%     | $60.97      | [longest]
--
-- Business insight:
--   The most stable customer profile is Partner=Yes, Dependents=Yes —
--   a household with both a partner and children, churning at just 14.24%.
--   The most at-risk household: no partner, no dependents (34.24%) — a solo
--   subscriber with no household inertia. This has direct implications for
--   acquisition strategy: family plan positioning and multi-person household
--   acquisition creates structurally more durable customers.
-- ---------------------------------------------------------------------------

SELECT
    c.Partner,
    c.Dependents,
    COUNT(*)                                                              AS total_customers,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(AVG(c.TotalCharges), 2)                                         AS avg_clv_realised,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
GROUP BY c.Partner, c.Dependents
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 2.3 : SENIOR CITIZEN × CONTRACT TYPE
-- ---------------------------------------------------------------------------
-- Business question: Does contract commitment neutralise senior citizen
--   churn risk, or does the demographic risk persist regardless of contract?
--
-- Expected output (key rows):
--   SeniorCitizen | Contract       | customers | churn_rate
--   Yes           | Month-to-month |   807     | 54.65%
--   No            | Month-to-month | 3,068     | 39.57%
--   Yes           | One year       |   190     | 15.26%
--   No            | One year       | 1,283     | 10.68%
--   Yes           | Two year       |   145     |  4.14%
--   No            | Two year       | 1,550     |  2.71%
--
-- Business insight:
--   Senior citizens on two-year contracts churn at 4.14% — only marginally
--   higher than non-seniors (2.71%). Contract commitment effectively neutralises
--   the senior citizen risk differential. This is the most actionable finding
--   in the demographic analysis: the retention team should prioritise offering
--   senior citizens a discounted annual or two-year contract, because the data
--   proves this single lever closes the gap between the highest-risk and
--   lowest-risk demographic profiles.
-- ---------------------------------------------------------------------------

SELECT
    c.SeniorCitizen,
    c.Contract,
    COUNT(*)                                                              AS total_customers,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
GROUP BY c.SeniorCitizen, c.Contract
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- SECTION 3 : HIGHEST-RISK DEMOGRAPHIC PROFILES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 3.1 : FOUR-FACTOR DEMOGRAPHIC RISK PROFILE MATRIX
-- ---------------------------------------------------------------------------
-- Business question: Which specific combination of demographic attributes
--   creates the highest compound churn risk — and how much MRR is exposed?
--
-- Dimensions: SeniorCitizen × Partner × Dependents × Contract
-- Minimum segment size enforced: 50 customers (HAVING clause)
--   Rationale: segments below 50 have insufficient sample size for reliable
--   rate estimates; removing them prevents noisy cells from misleading
--   the retention team.
--
-- Expected output (top 5 rows):
--   Senior | Partner | Dependents | Contract       | customers | churn_rate | churned_mrr
--   Yes    | No      | No         | Month-to-month |   454     | 58.15%     | $20,475.90
--   Yes    | Yes     | No         | Month-to-month |   304     | 52.30%     | $13,191.30
--   No     | No      | No         | Month-to-month | 1,834     | 42.69%     | $53,780.00
--   No     | Yes     | No         | Month-to-month |   494     | 38.46%     | $15,085.70
--   No     | No      | Yes        | Month-to-month |   200     | 33.00%     | $4,252.55
--
-- Business insight:
--   The single most destructive demographic profile is: Senior citizen,
--   no partner, no dependents, month-to-month contract — 58.15% churn rate,
--   454 customers, $20,476/month in at-risk MRR. These 454 customers generate
--   $245,710 in annual revenue risk from one demographic profile combination.
--   A targeted retention campaign for this cohort alone (proactive call, senior
--   support, contract upgrade offer) is a clear business case.
-- ---------------------------------------------------------------------------

WITH base_churned AS (
    SELECT SUM(MonthlyCharges) AS total_churned_mrr
    FROM customer_churn
    WHERE Churn = 'Yes'
)
SELECT
    c.SeniorCitizen,
    c.Partner,
    c.Dependents,
    c.Contract,
    COUNT(*)                                                              AS total_customers,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                        AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / b.total_churned_mrr, 1
    )                                                                     AS pct_of_total_churned_mrr
FROM customer_churn c
CROSS JOIN base_churned b
GROUP BY
    c.SeniorCitizen,
    c.Partner,
    c.Dependents,
    c.Contract,
    b.total_churned_mrr
HAVING COUNT(*) >= 50
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 3.2 : DEMOGRAPHIC REVENUE IMPACT SUMMARY — DASHBOARD FEED
-- ---------------------------------------------------------------------------
-- Business question: Across all four demographic factors, which contributes
--   the most churned MRR and should therefore receive the most retention budget?
--
-- This query produces a single-table summary that can feed a Power BI
-- stacked bar or matrix visual on the executive dashboard. It unpivots the
-- four demographic dimensions into rows using UNION ALL for MySQL compatibility.
--
-- Business insight:
--   This summary table allows the retention manager to answer: "If I have
--   $100K for retention campaigns, how should I allocate it across demographic
--   segments?" The answer: senior citizens and customers without dependents
--   produce the most churned MRR per capita and should receive disproportionate
--   outreach investment.
-- ---------------------------------------------------------------------------

SELECT
    'SeniorCitizen = Yes'  AS demographic_segment,
    COUNT(*)               AS customers,
    SUM(Churn_Binary)      AS churned,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                   AS avg_monthly_charge,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2)  AS churned_mrr,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)*12, 2) AS annual_at_risk
FROM customer_churn WHERE SeniorCitizen = 'Yes'

UNION ALL

SELECT
    'Partner = No',
    COUNT(*), SUM(Churn_Binary),
    ROUND(SUM(Churn_Binary)*100.0/COUNT(*),2),
    ROUND(AVG(MonthlyCharges),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12,2)
FROM customer_churn WHERE Partner = 'No'

UNION ALL

SELECT
    'Dependents = No',
    COUNT(*), SUM(Churn_Binary),
    ROUND(SUM(Churn_Binary)*100.0/COUNT(*),2),
    ROUND(AVG(MonthlyCharges),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12,2)
FROM customer_churn WHERE Dependents = 'No'

UNION ALL

SELECT
    'Gender = Female',
    COUNT(*), SUM(Churn_Binary),
    ROUND(SUM(Churn_Binary)*100.0/COUNT(*),2),
    ROUND(AVG(MonthlyCharges),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12,2)
FROM customer_churn WHERE gender = 'Female'

UNION ALL

SELECT
    'Gender = Male',
    COUNT(*), SUM(Churn_Binary),
    ROUND(SUM(Churn_Binary)*100.0/COUNT(*),2),
    ROUND(AVG(MonthlyCharges),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END),2),
    ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12,2)
FROM customer_churn WHERE gender = 'Male'

ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- POWER BI RECOMMENDATIONS — SCRIPT 07
-- =============================================================================
-- Q1.1 → KPI side-by-side cards: Male churn rate vs Female churn rate.
--         Near-identical values communicate "gender is not a factor" to
--         executives without requiring additional explanation.
--
-- Q1.2 → Donut chart: SeniorCitizen Yes/No split with churn rate label.
--         Overlay a KPI card: "Senior citizens churn at 1.76× the base rate."
--
-- Q1.3 → Horizontal bar chart: Partner = Yes (green), No (red), bars show
--         churn rate. Add avg_tenure_months as a secondary data label.
--
-- Q1.4 → Same as Q1.3 for Dependents. The 15.45% vs 31.28% gap is visually
--         dramatic on a simple bar chart.
--
-- Q2.1 → 2×2 matrix table: rows = SeniorCitizen, columns = Partner,
--         cell value = churn_rate_pct with heat map conditional formatting.
--
-- Q3.1 → Filterable table: Columns = four demographic dimensions + churn_rate +
--         churned_mrr + annual_at_risk. Sort descending. Top row is the
--         retention team's first call list.
--
-- Q3.2 → Stacked bar chart: demographic_segment on X-axis,
--         annual_at_risk on Y-axis. Confirms senior + no-dependents dominate.
-- =============================================================================


-- =============================================================================
-- INTERVIEW TALKING POINTS — SCRIPT 07
-- =============================================================================
-- "The most important finding in my demographic analysis was actually a
--  negative finding: gender has essentially zero predictive power for churn
--  in this dataset. That's a valuable business insight — it tells the marketing
--  team not to waste budget on gender-targeted retention campaigns. Good
--  analysis tells you where NOT to look as much as where to look.
--
--  The positive finding was the Dependents effect: customers with children or
--  dependents churn at 15.45% vs 31.28% for those without. That's a structural
--  loyalty advantage that comes from switching friction and household inertia.
--  The strategic implication is that family plan acquisition creates durable
--  customers — and that's a board-level product strategy insight, not just a
--  retention observation.
--
--  And the most actionable finding: senior citizens on two-year contracts churn
--  at 4.14% — almost identical to non-seniors. So the senior citizen problem
--  is not unsolvable. It's a contract conversion problem disguised as a
--  demographic problem."
-- =============================================================================
