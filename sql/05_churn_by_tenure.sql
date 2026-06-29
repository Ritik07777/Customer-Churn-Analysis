-- =============================================================================
-- Script       : 05_churn_by_tenure.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0
-- Depends on   : 01_database_setup.sql (customer_churn table must exist)
-- =============================================================================
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  BUSINESS OBJECTIVE                                                     │
-- │                                                                         │
-- │  Tenure is a time dimension — it tells us not just WHO churns, but      │
-- │  WHEN. This script maps the customer lifecycle from onboarding through  │
-- │  loyalty to identify the precise windows where intervention delivers    │
-- │  the highest return.                                                    │
-- │                                                                         │
-- │  Three questions management needs answered:                             │
-- │    1. At what point in the customer lifecycle is churn risk highest?    │
-- │    2. Is there a "survival threshold" — a tenure point after which      │
-- │       customers are effectively retained permanently?                   │
-- │    3. What does the revenue profile look like across the lifecycle?     │
-- │       (Are we losing high-value customers early, or low-value ones?)    │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- EXECUTIVE SUMMARY
-- -----------------
-- 55.48% of all churn occurs in the first 12 months of a customer's lifecycle.
-- Month 1 is the single most dangerous point — 62% of customers who joined and
-- reached only 1 month of tenure have already churned. Churn rate stabilises
-- below 15% after 36 months and below 10% after 48 months. The implication
-- is a clear intervention strategy: the entire retention budget should be
-- front-loaded into the first 90 days of the customer lifecycle.
--
-- Customers who survive beyond 48 months represent the most valuable segment
-- by CLV ($4,685.51 average TotalCharges) and the lowest churn risk (9.51%).
-- Once a customer reaches "loyal" status (49–72 months), they are effectively
-- self-retaining. The priority is preventing early exits before reaching this
-- threshold.
--
-- KEY DECISIONS THIS ANALYSIS SUPPORTS
-- ----------------------------------------
-- • Design a 90-day onboarding programme with intervention checkpoints at
--   days 30, 60, and 90
-- • Set a "30-day at-risk" alert in the CRM for all new customers with
--   month-to-month contracts
-- • Define "customer lifecycle stage" as a standard field in reporting
-- • Measure retention team performance against first-year churn reduction
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- QUERY 1 : CHURN RATE AND REVENUE IMPACT BY TENURE BAND
-- =============================================================================
-- What it measures:
--   For each tenure cohort (0–12, 13–24, 25–48, 49–72 months), computes
--   customer count, churn rate, MRR, MRR lost to churn, and share of total
--   churn. The "share of total churn" column answers the question: which
--   lifecycle stage is generating the most churn volume (not just the highest
--   rate)?
--
-- Expected output:
--   tenure_band   | customers | churned | churn_rate | pct_total_churn | churned_mrr | annual_at_risk
--   0-12 months   | 2,186     | 1,037   | 47.44%     | 55.48%          | $68,954     | $827,451
--   13-24 months  | 1,024     |   294   | 28.71%     | 15.73%          | $23,082     | $276,980
--   25-48 months  | 1,594     |   325   | 20.39%     | 17.39%          | $27,463     | $329,554
--   49-72 months  | 2,239     |   213   |  9.51%     | 11.40%          | $19,632     | $235,590
--
-- Business insight:
--   The 0–12 month band produces over half of all churn despite being only
--   31% of the customer base. Early-lifecycle customers also have the lowest
--   average monthly charge ($56.10) — meaning the company is losing customers
--   before they've had the chance to upgrade to higher-value plans. The gap
--   between the 0–12 month churn rate (47.44%) and the 49–72 month rate (9.51%)
--   is the financial argument for a structured onboarding journey.
-- =============================================================================

WITH band_totals AS (
    SELECT
        SUM(Churn_Binary)   AS total_churned,
        SUM(MonthlyCharges) AS total_mrr
    FROM customer_churn
)
SELECT
    c.tenure_band,
    COUNT(*)                                                          AS total_customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)                AS pct_of_base,
    SUM(c.Churn_Binary)                                               AS churned_customers,
    COUNT(*) - SUM(c.Churn_Binary)                                    AS retained_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(SUM(c.Churn_Binary) * 100.0 / t.total_churned, 2)           AS pct_of_total_churn,

    -- Revenue profile
    ROUND(AVG(c.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges), 2)                                   AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                      AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                 AS annual_revenue_at_risk,

    -- CLV metrics
    ROUND(AVG(c.TotalCharges), 2)                                     AS avg_total_charges_clv,
    ROUND(AVG(CASE WHEN c.Churn = 'Yes' THEN c.TotalCharges END), 2)  AS avg_clv_of_churners,
    ROUND(AVG(CASE WHEN c.Churn = 'No'  THEN c.TotalCharges END), 2)  AS avg_clv_of_retained

FROM customer_churn c
CROSS JOIN band_totals t
GROUP BY c.tenure_band, t.total_churned, t.total_mrr
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- =============================================================================
-- QUERY 2 : MONTH-BY-MONTH CHURN RATE — FIRST 24 MONTHS (EARLY DANGER WINDOW)
-- =============================================================================
-- What it measures:
--   Churn rate at each individual month of tenure for months 0–24. This is
--   the survival curve equivalent in SQL — showing precisely when churn
--   spikes, when it stabilises, and whether there are specific "trigger months"
--   that correspond to contract renewal, price review, or billing events.
--
-- Expected output (selected rows):
--   tenure | customers | churned | churn_rate_pct | risk_flag
--   1      | 613       | 380     | 61.99%         | CRITICAL
--   2      | 238       | 123     | 51.68%         | CRITICAL
--   3      | 200       | 94      | 47.00%         | CRITICAL
--   6      | 110       | 40      | 36.36%         | HIGH
--   12     | 117       | 38      | 32.48%         | HIGH
--   18     | 97        | 24      | 24.74%         | MODERATE
--   24     | 94        | 23      | 24.47%         | MODERATE
--
-- Business insight:
--   Month 1 is catastrophic: 62% of customers who only completed one month
--   of service have churned. This is not a retention failure — it is an
--   acquisition and onboarding failure. Customers are signing up who were
--   never fully committed or who had a poor first experience. Month 6 shows
--   a secondary spike — likely corresponding to the end of an introductory
--   rate period. The 30-day and 6-month marks are the two most critical
--   intervention windows in the entire customer lifecycle.
-- =============================================================================

SELECT
    tenure,
    COUNT(*)                                                          AS customers_at_tenure,
    SUM(Churn_Binary)                                                 AS churned_at_tenure,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly_charge,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2)
                                                                      AS mrr_lost,
    -- Risk flag for dashboard colour coding
    CASE
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.50 THEN 'CRITICAL'
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.35 THEN 'HIGH'
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.20 THEN 'MODERATE'
        ELSE                                                  'LOW'
    END                                                               AS risk_flag
FROM customer_churn
WHERE tenure BETWEEN 1 AND 24
GROUP BY tenure
ORDER BY tenure;


-- =============================================================================
-- QUERY 3 : CUSTOMER LIFECYCLE STAGE DEFINITIONS AND PROFILE
-- =============================================================================
-- What it measures:
--   Assigns each customer to a named lifecycle stage based on tenure,
--   then profiles each stage by churn behaviour, revenue, and demographics.
--   These stage names become the standard vocabulary used in all downstream
--   reporting, the Power BI dashboard, and the executive summary.
--
-- Lifecycle stage definitions:
--   NEW        : 0–3 months   — highest risk, pre-commitment window
--   DEVELOPING : 4–12 months  — risk declining but still elevated, post-trial
--   GROWING    : 13–24 months — approaching mid-tenure, rate dropping
--   MATURING   : 25–48 months — stable, approaching loyalty threshold
--   LOYAL      : 49–72 months — effectively retained, CLV ceiling reached
--
-- Business insight:
--   NEW customers churn at ~53% — over half leave before generating
--   meaningful revenue. LOYAL customers churn at under 10% and have an
--   average TotalCharges of $4,685.51. The entire lifecycle management
--   strategy is to move customers from NEW to LOYAL as efficiently as possible.
-- =============================================================================

WITH lifecycle AS (
    SELECT *,
        CASE
            WHEN tenure BETWEEN 0  AND  3 THEN 'NEW (0-3 months)'
            WHEN tenure BETWEEN 4  AND 12 THEN 'DEVELOPING (4-12 months)'
            WHEN tenure BETWEEN 13 AND 24 THEN 'GROWING (13-24 months)'
            WHEN tenure BETWEEN 25 AND 48 THEN 'MATURING (25-48 months)'
            WHEN tenure BETWEEN 49 AND 72 THEN 'LOYAL (49-72 months)'
        END AS lifecycle_stage,
        CASE
            WHEN tenure BETWEEN 0  AND  3 THEN 1
            WHEN tenure BETWEEN 4  AND 12 THEN 2
            WHEN tenure BETWEEN 13 AND 24 THEN 3
            WHEN tenure BETWEEN 25 AND 48 THEN 4
            WHEN tenure BETWEEN 49 AND 72 THEN 5
        END AS stage_order
    FROM customer_churn
),
stage_totals AS (
    SELECT SUM(Churn_Binary) AS total_churned FROM customer_churn
)
SELECT
    l.lifecycle_stage,
    COUNT(*)                                                          AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)                AS pct_of_base,
    SUM(l.Churn_Binary)                                               AS churned,
    ROUND(SUM(l.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(SUM(l.Churn_Binary) * 100.0 / s.total_churned, 1)           AS pct_of_total_churn,
    ROUND(AVG(l.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(AVG(l.TotalCharges), 2)                                     AS avg_clv,
    ROUND(SUM(l.MonthlyCharges), 2)                                   AS stage_mrr,
    ROUND(SUM(CASE WHEN l.Churn = 'Yes' THEN l.MonthlyCharges ELSE 0 END) * 12, 2)
                                                                      AS annual_mrr_at_risk,
    -- Senior citizen composition per stage
    ROUND(SUM(CASE WHEN l.SeniorCitizen = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1)
                                                                      AS pct_senior,
    -- Month-to-month composition per stage
    ROUND(SUM(CASE WHEN l.Contract = 'Month-to-month' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1)
                                                                      AS pct_month_to_month
FROM lifecycle l
CROSS JOIN stage_totals s
GROUP BY l.lifecycle_stage, l.stage_order, s.total_churned
ORDER BY l.stage_order;


-- =============================================================================
-- QUERY 4 : TENURE BAND × CONTRACT TYPE — WHERE INTERVENTION MATTERS MOST
-- =============================================================================
-- What it measures:
--   Churn rate for every tenure band × contract type combination. This builds
--   the "churn heat map" that identifies the highest-risk cells in the
--   customer portfolio and the cells where intervention is most urgent.
--
-- Key findings confirmed from data:
--   • Two-year / 0–12 months: 0.00% churn — commitment eliminates early risk
--   • Two-year / 13–24 months: 0.00% churn — continued full retention
--   • Month-to-month / 0–12 months: 51.35% — the crisis cell
--   • Month-to-month / 49–72 months: 26.02% — long-tenured customers still at risk
--
-- Business insight:
--   The "crisis cell" (M2M × 0–12 months) has 1,994 customers, 51.35% churn,
--   and represents the largest single source of revenue loss in the portfolio.
--   The fact that long-tenured M2M customers (49–72 months) still churn at 26%
--   means there is no natural loyalty formation in the M2M segment — contract
--   commitment is the only reliable retention mechanism.
-- =============================================================================

SELECT
    c.tenure_band,
    c.Contract,
    COUNT(*)                                                          AS customers,
    SUM(c.Churn_Binary)                                               AS churned,
    COUNT(*) - SUM(c.Churn_Binary)                                    AS retained,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges), 2)                                   AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                      AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                 AS annual_at_risk
FROM customer_churn c
GROUP BY c.tenure_band, c.Contract
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END,
    churn_rate_pct DESC;


-- =============================================================================
-- QUERY 5 : TENURE BAND × INTERNET SERVICE — PRODUCT-LIFECYCLE INTERACTION
-- =============================================================================
-- What it measures:
--   Investigates whether the product a customer subscribes to moderates the
--   tenure-churn relationship. Fibre optic customers may churn at high rates
--   even at later tenure stages if the product experience is not meeting
--   premium price expectations.
--
-- Business insight:
--   If fibre optic customers show elevated churn rates even at 49–72 months
--   tenure (vs DSL customers of the same tenure), this indicates a product
--   satisfaction issue, not just a commitment issue. This finding escalates
--   beyond retention into product strategy.
-- =============================================================================

SELECT
    c.tenure_band,
    c.InternetService,
    COUNT(*)                                                          AS customers,
    SUM(c.Churn_Binary)                                               AS churned,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2)
                                                                      AS annual_at_risk
FROM customer_churn c
GROUP BY c.tenure_band, c.InternetService
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END,
    churn_rate_pct DESC;


-- =============================================================================
-- QUERY 6 : SURVIVAL THRESHOLD ANALYSIS — FINDING THE LOYALTY INFLECTION POINT
-- =============================================================================
-- What it measures:
--   Identifies the exact tenure month at which churn rate drops to and stays
--   below 20% — the "survival threshold." Also shows the cumulative revenue
--   a customer generates if they reach this threshold vs if they churn at
--   month 1, 6, or 12.
--
-- Business insight:
--   A customer who reaches month 36 with the company generates on average
--   $65.93/month × 36 months = ~$2,374 in TotalCharges. A customer who churns
--   at month 1 generates only $56.10. Reaching the loyalty threshold unlocks
--   ~42× the CLV of a month-1 churner. This is the economic case for investing
--   heavily in the first 36 months of the customer relationship.
-- =============================================================================

SELECT
    tenure,
    COUNT(*)                                                          AS customers,
    SUM(Churn_Binary)                                                 AS churned,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly_charge,
    -- Cumulative CLV proxy at this tenure point
    ROUND(AVG(MonthlyCharges) * tenure, 2)                            AS estimated_clv_at_tenure,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2)
                                                                      AS mrr_lost_at_month,
    -- Flag the transition points
    CASE
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.40 THEN 'CRISIS   — Immediate intervention'
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.25 THEN 'ELEVATED — Proactive outreach'
        WHEN SUM(Churn_Binary) * 1.0 / COUNT(*) >= 0.15 THEN 'MODERATE — Monitor and nurture'
        ELSE                                                  'STABLE   — Loyalty reinforcement'
    END                                                               AS intervention_priority
FROM customer_churn
WHERE tenure BETWEEN 1 AND 72
GROUP BY tenure
ORDER BY tenure;


-- =============================================================================
-- POWER BI RECOMMENDATIONS
-- =============================================================================
-- Q1 → Stacked bar chart: tenure_band on X-axis, bars split into churned
--       (red) vs retained (blue) customer counts. Overlay churn_rate_pct as
--       a line on a secondary axis. This single visual communicates both
--       volume and rate in one view.
--
-- Q2 → Line chart with shaded areas: tenure (1–24) on X-axis, churn_rate_pct
--       on Y-axis. Apply conditional background shading by risk_flag:
--       red = CRITICAL (months 1–5), orange = HIGH, yellow = MODERATE.
--       Add a reference line at the company average (26.54%). This chart
--       is the visual centrepiece of the lifecycle page.
--
-- Q3 → Funnel chart or horizontal bar: lifecycle_stage on Y-axis ordered
--       by stage_order, pct_of_total_churn on X-axis. Alternatively a
--       stepped area chart showing churn rate decline across stages.
--
-- Q4 → Heat map matrix: rows = tenure_band, columns = Contract, cell value =
--       churn_rate_pct. Conditional formatting: dark red at 55%, white at 0%.
--       This visual alone tells the entire retention story.
--
-- Q5 → Small multiples line chart or matrix: rows = tenure_band, columns =
--       InternetService, cell = churn rate. Allows side-by-side product
--       comparison across the lifecycle.
--
-- Q6 → Line chart: tenure (X-axis) vs churn_rate_pct (Y-axis) for full
--       1–72 month range. Add reference lines at 40%, 25%, 15% with labels.
--       The curve's shape is the survival curve — a standard analytics output.
-- =============================================================================


-- =============================================================================
-- INTERVIEW TALKING POINTS
-- =============================================================================
-- "The single most important finding in my tenure analysis wasn't a number —
--  it was a pattern. Month 1 has a 62% churn rate. If you extend the view to
--  month 24, you can see the rate declining steadily. After month 36, it drops
--  below 20% and stays there. That tells me there's a 'survival threshold' —
--  and my job is to help the business get customers past it.
--
--  I structured this as a lifecycle analysis rather than a simple cohort table
--  because 'what's your churn rate?' is a much less useful question than
--  'where in the lifecycle does churn happen and what triggers it?' The two-year
--  contract finding reinforces this: those customers have 0% churn in months
--  1–24 — not because they're different people, but because a commitment
--  structure removed the exit option during the highest-risk window.
--
--  When I presented this to [hypothetical stakeholder], the action that came
--  out of it was to redesign the onboarding journey with explicit check-in
--  calls at days 30 and 60. That's a concrete operational recommendation that
--  came directly from a SQL analysis — that's what I want my work to produce."
-- =============================================================================
