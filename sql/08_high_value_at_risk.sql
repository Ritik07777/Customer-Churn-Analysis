-- =============================================================================
-- Script       : 08_high_value_at_risk.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0 (ONLY_FULL_GROUP_BY mode)
-- Schema       : telecom_churn
-- Depends on   : 01_database_setup.sql (customer_churn table must exist)
-- Next script  : 09_cohort_clv_analysis.sql
-- =============================================================================
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  EXECUTIVE SUMMARY                                                      │
-- │                                                                         │
-- │  This script answers the question every CFO asks after seeing the       │
-- │  churn rate: "Are we losing our best customers?"                        │
-- │  The answer is yes — and disproportionately so.                         │
-- │                                                                         │
-- │  High-value customers (MonthlyCharges > $65, roughly the dataset         │
-- │  median of $70.35) represent 55.4% of the base but generate 85.2%       │
-- │  of all churned MRR. Among the high-value segment, month-to-month       │
-- │  customers churn at 51.75% — worse than the overall M2M rate because    │
-- │  high-value customers disproportionately select fibre optic, which       │
-- │  carries its own elevated churn risk.                                   │
-- │                                                                         │
-- │  The crisis segment: High-value + Month-to-month + tenure ≤ 12 months   │
-- │  → 975 customers, 67.69% churn rate, $54,376.80/month in churned MRR.  │
-- │  This single cohort produces $652,521 in annualised revenue loss.       │
-- │                                                                         │
-- │  This script produces three operational outputs:                        │
-- │  1. Tiered risk classification of ALL active high-value customers        │
-- │     (the retention team's priority call list)                           │
-- │  2. Financial modelling of retention programme ROI by tier              │
-- │  3. The 20 highest individual revenue accounts at risk                  │
-- │                                                                         │
-- │  KEY DECISIONS THIS ANALYSIS SUPPORTS:                                  │
-- │  • Focus 70%+ of retention budget on high-value M2M customers           │
-- │  • Trigger an outreach intervention for any high-value customer at       │
-- │    tenure = 30 days before their first renewal date                     │
-- │  • Prioritise top-quartile accounts (> $89.85/month) for white-glove    │
-- │    retention (assigned account manager, not automated email)            │
-- │  • Define "high-value at risk" as a standing dashboard KPI              │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- CUSTOMER VALUE TIER DEFINITIONS (used throughout this script):
--   PREMIUM  : MonthlyCharges >= $89.85  (top quartile, P75+)
--   HIGH     : MonthlyCharges >= $65.00 and < $89.85
--   STANDARD : MonthlyCharges <  $65.00
--
-- Rationale: $89.85 = 75th percentile of MonthlyCharges.
--            $65.00 = approximate dataset mean; meaningful above-average signal.
--            These thresholds should be reviewed annually against actual billing.
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- SECTION 1 : HIGH-VALUE SEGMENT DEFINITION AND OVERVIEW
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 1.1 : CUSTOMER VALUE TIER DISTRIBUTION
-- ---------------------------------------------------------------------------
-- Business question: How is the customer base distributed across value tiers,
--   and what proportion of MRR and churn risk sits in each tier?
--
-- Expected output:
--   value_tier | customers | pct_base | churn_rate | seg_mrr    | churned_mrr | pct_churned_mrr
--   PREMIUM    | 1,771     | 25.1%    | 32.75%     | $188,752   | $57,683     | 41.5%
--   HIGH       | 2,128     | 30.2%    | 36.21%     | $156,448   | $60,812     | 43.7%
--   STANDARD   | 3,144     | 44.7%    |  9.61%     | $110,917   | $20,636     | 14.8%
--
-- Business insight:
--   Standard-value customers (< $65/month) represent 44.7% of the base
--   but only 14.8% of churned MRR. Premium and High tiers together produce
--   85.2% of all churned MRR. Retention investment concentrated on these two
--   tiers is the most efficient allocation of programme budget.
-- ---------------------------------------------------------------------------

WITH base_totals AS (
    SELECT
        COUNT(*)                                                          AS total_customers,
        SUM(MonthlyCharges)                                               AS total_mrr,
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)       AS total_churned_mrr
    FROM customer_churn
)
SELECT
    CASE
        WHEN c.MonthlyCharges >= 89.85 THEN 'PREMIUM  (>= $89.85/mo)'
        WHEN c.MonthlyCharges >= 65.00 THEN 'HIGH     ($65-$89.85/mo)'
        ELSE                                'STANDARD (< $65/mo)'
    END                                                                   AS value_tier,
    COUNT(*)                                                              AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers, 1)                        AS pct_of_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(c.MonthlyCharges), 2)                                       AS segment_mrr,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / b.total_mrr, 1)                 AS pct_of_total_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / b.total_churned_mrr, 1
    )                                                                     AS pct_of_total_churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
CROSS JOIN base_totals b
GROUP BY
    CASE
        WHEN c.MonthlyCharges >= 89.85 THEN 'PREMIUM  (>= $89.85/mo)'
        WHEN c.MonthlyCharges >= 65.00 THEN 'HIGH     ($65-$89.85/mo)'
        ELSE                                'STANDARD (< $65/mo)'
    END,
    b.total_customers, b.total_mrr, b.total_churned_mrr
ORDER BY AVG(c.MonthlyCharges) DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.2 : HIGH-VALUE CHURN BY CONTRACT TYPE
-- ---------------------------------------------------------------------------
-- Business question: Among high-value customers (>= $65/month), which contract
--   type produces the most revenue risk — and how does the contract effect
--   interact with high billing amounts?
--
-- Expected output:
--   Contract       | hv_customers | churn_rate | churned_mrr | annual_at_risk
--   Month-to-month | 2,292        | 51.75%     | $102,176.60 | $1,226,119
--   One year       |   775        | 16.77%     | $12,529.90  | $150,359
--   Two year       |   832        |  4.57%     | $3,788.50   | $45,462
--
-- Business insight:
--   High-value month-to-month customers churn at 51.75% — 9 points worse than
--   the overall M2M rate of 42.71%. This is the highest-value, highest-risk
--   intersection in the entire dataset. 2,292 customers, half of whom churn,
--   generating over $1.2M in annual revenue loss. Contrast with two-year
--   high-value customers (4.57%) — proof that contract commitment works even
--   harder for premium customers than for the base.
-- ---------------------------------------------------------------------------

WITH hv_totals AS (
    SELECT
        COUNT(*)                                                          AS hv_total,
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)       AS hv_churned_mrr
    FROM customer_churn
    WHERE MonthlyCharges >= 65.00
)
SELECT
    c.Contract,
    COUNT(*)                                                              AS hv_customers,
    ROUND(COUNT(*) * 100.0 / h.hv_total, 1)                               AS pct_of_hv_base,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(c.MonthlyCharges), 2)                                       AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / h.hv_churned_mrr, 1
    )                                                                     AS pct_of_hv_churned_mrr
FROM customer_churn c
CROSS JOIN hv_totals h
WHERE c.MonthlyCharges >= 65.00
GROUP BY c.Contract, h.hv_total, h.hv_churned_mrr
ORDER BY churn_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- QUERY 1.3 : HIGH-VALUE CHURN BY TENURE BAND
-- ---------------------------------------------------------------------------
-- Business question: For high-value customers specifically, how does churn
--   risk change across the customer lifecycle?
--
-- Expected output:
--   tenure_band   | hv_customers | churn_rate | avg_monthly | annual_at_risk
--   0-12 months   | 1,000        | 66.40%     | $81.30      | $827,265
--   13-24 months  |   524        | 43.32%     | $85.70      | $276,980
--   25-48 months  |   896        | 30.80%     | $89.12      | $329,554
--   49-72 months  | 1,479        | 12.64%     | $93.83      | $235,590
--
-- Business insight:
--   High-value customers in their first year churn at 66.40% — two-thirds of
--   new premium customers leave within 12 months. This is an acquisition and
--   onboarding failure at the top of the revenue funnel. The average monthly
--   charge for this cohort ($81.30) means each early churner represents ~$975
--   in lost annual MRR before they're even counted as a retained customer.
-- ---------------------------------------------------------------------------

SELECT
    c.tenure_band,
    COUNT(*)                                                              AS hv_customers,
    SUM(c.Churn_Binary)                                                   AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                      AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                       AS avg_monthly_charge,
    ROUND(AVG(c.tenure), 1)                                               AS avg_tenure_months,
    ROUND(SUM(c.MonthlyCharges), 2)                                       AS segment_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                          AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_at_risk
FROM customer_churn c
WHERE c.MonthlyCharges >= 65.00
GROUP BY c.tenure_band
ORDER BY
    CASE c.tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- =============================================================================
-- SECTION 2 : PRIORITY RETENTION SEGMENTS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 2.1 : TRIPLE-RISK SEGMENT — HIGH VALUE × M2M × EARLY TENURE
-- ---------------------------------------------------------------------------
-- Business question: What is the combined revenue exposure of customers who
--   simultaneously exhibit all three major risk factors?
--
-- Triple-risk definition:
--   • MonthlyCharges >= $65.00 (high-value customer)
--   • Contract = 'Month-to-month' (no commitment structure)
--   • tenure <= 12 months (in the peak churn danger window)
--
-- Expected output:
--   risk_combination                          | customers | churn_rate | monthly_mrr_at_risk | annual_at_risk
--   HV + Month-to-month + tenure 0-12 months | 975       | 67.69%     | $54,376.80          | $652,521
--
-- Business insight:
--   975 customers, 67.69% churn rate, $652,521 annual revenue risk.
--   This is the #1 priority retention segment in the entire dataset — a
--   group where 2 in 3 customers are expected to leave, and each one
--   takes ~$81/month in revenue with them.
--   An outreach intervention reaching this segment before month 3 (when churn
--   is highest) and offering a 3-month service credit to lock in an annual
--   contract could recover $130–$200K annually at a programme cost of ~$50K.
-- ---------------------------------------------------------------------------

SELECT
    'HV + Month-to-month + Tenure 0-12mo'                                 AS risk_combination,
    COUNT(*)                                                              AS customers,
    SUM(Churn_Binary)                                                     AS already_churned,
    COUNT(*) - SUM(Churn_Binary)                                          AS still_active,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                        AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                         AS avg_monthly_charge,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2) AS churned_mrr,
    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                     AS annual_revenue_lost,
    -- Active (not yet churned) MRR at forward risk
    ROUND(SUM(CASE WHEN Churn = 'No' THEN MonthlyCharges ELSE 0 END), 2)  AS active_mrr_still_at_risk
FROM customer_churn
WHERE MonthlyCharges >= 65.00
  AND Contract       =  'Month-to-month'
  AND tenure         <= 12;


-- ---------------------------------------------------------------------------
-- QUERY 2.2 : MULTI-FACTOR RETENTION PRIORITY SEGMENT MATRIX
-- ---------------------------------------------------------------------------
-- Business question: Across all combinations of value tier, contract type,
--   and tenure band, which segments should retention receive funding for?
--
-- This query produces the complete risk prioritisation matrix that the
-- retention manager uses to allocate team time and campaign budget.
-- Segments with fewer than 30 customers are excluded (HAVING clause)
-- to ensure statistical reliability of the churn rate estimates.
--
-- Retention priority logic:
--   PRIORITY 1 → churn_rate >= 50% AND avg_monthly >= $65
--   PRIORITY 2 → churn_rate >= 35% AND avg_monthly >= $65
--   PRIORITY 3 → churn_rate >= 20% AND avg_monthly >= $65
--   MONITOR    → all others above threshold
-- ---------------------------------------------------------------------------

WITH segment_data AS (
    SELECT
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 'PREMIUM'
            WHEN MonthlyCharges >= 65.00 THEN 'HIGH'
            ELSE                              'STANDARD'
        END                                                               AS value_tier,
        Contract,
        tenure_band,
        COUNT(*)                                                          AS customers,
        SUM(Churn_Binary)                                                 AS churned,
        ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
        ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly,
        ROUND(SUM(MonthlyCharges), 2)                                     AS seg_mrr,
        ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges ELSE 0 END)*12, 2)
                                                                          AS annual_at_risk
    FROM customer_churn
    GROUP BY
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 'PREMIUM'
            WHEN MonthlyCharges >= 65.00 THEN 'HIGH'
            ELSE                              'STANDARD'
        END,
        Contract,
        tenure_band
    HAVING COUNT(*) >= 30
)
SELECT
    value_tier,
    Contract,
    tenure_band,
    customers,
    churned,
    churn_rate_pct,
    avg_monthly,
    seg_mrr,
    annual_at_risk,
    CASE
        WHEN churn_rate_pct >= 50 AND avg_monthly >= 65 THEN '1 — CRITICAL'
        WHEN churn_rate_pct >= 35 AND avg_monthly >= 65 THEN '2 — HIGH'
        WHEN churn_rate_pct >= 20 AND avg_monthly >= 65 THEN '3 — MODERATE'
        ELSE                                                  '4 — MONITOR'
    END                                                                   AS retention_priority
FROM segment_data
ORDER BY
    CASE
        WHEN churn_rate_pct >= 50 AND avg_monthly >= 65 THEN 1
        WHEN churn_rate_pct >= 35 AND avg_monthly >= 65 THEN 2
        WHEN churn_rate_pct >= 20 AND avg_monthly >= 65 THEN 3
        ELSE 4
    END,
    annual_at_risk DESC;


-- =============================================================================
-- SECTION 3 : ACTIVE CUSTOMER TARGETING OUTPUTS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 3.1 : ACTIVE HIGH-VALUE AT-RISK CUSTOMERS — RETENTION CALL LIST
-- ---------------------------------------------------------------------------
-- Business question: Which specific active (not yet churned) customers are
--   the highest priority for an immediate retention intervention?
--
-- This query produces a ranked list of active customers who match the
-- high-risk profile: high value + month-to-month contract + early tenure.
-- Each row is a customer the retention team can contact today.
--
-- Risk score calculation:
--   A composite risk score (0–100) is computed from four weighted factors:
--     • MonthlyCharges weight  : higher charge = higher revenue at stake
--     • Contract weight        : M2M = highest risk
--     • Tenure weight          : shorter = higher risk
--     • Senior citizen weight  : yes = elevated demographic risk
--   The score is normalised to 0–100 for dashboard display.
--
-- Output: Sorted by risk_score DESC then MonthlyCharges DESC.
--   Top rows = customers who are most likely to leave AND most expensive to lose.
--   This is the exact list handed to the retention team at the start of each week.
-- ---------------------------------------------------------------------------

SELECT
    customerID,
    gender,
    SeniorCitizen,
    Partner,
    Dependents,
    tenure,
    tenure_band,
    Contract,
    InternetService,
    MonthlyCharges,
    TotalCharges,
    PaymentMethod,
    PaperlessBilling,
    -- Composite at-risk score (higher = more urgent to contact)
    ROUND(
        -- Contract risk component (max 35 points)
        (CASE Contract
            WHEN 'Month-to-month' THEN 35
            WHEN 'One year'       THEN 15
            WHEN 'Two year'       THEN 5
        END)
        -- Tenure risk component (max 30 points — higher for shorter tenure)
        + GREATEST(30 - tenure, 0)
        -- Revenue magnitude component (max 25 points)
        + LEAST(ROUND(MonthlyCharges / 5, 0), 25)
        -- Senior citizen risk component (max 10 points)
        + CASE SeniorCitizen WHEN 'Yes' THEN 10 ELSE 0 END
    , 0)                                                                  AS risk_score,
    -- Human-readable risk tier
    CASE
        WHEN Contract = 'Month-to-month' AND tenure <= 12
             AND MonthlyCharges >= 65    THEN 'CRITICAL — Contact within 48 hours'
        WHEN Contract = 'Month-to-month' AND tenure <= 24
             AND MonthlyCharges >= 65    THEN 'HIGH     — Contact this week'
        WHEN Contract = 'Month-to-month' AND MonthlyCharges >= 65
                                         THEN 'MODERATE — Include in next campaign'
        ELSE                                  'STANDARD — Automated nurture'
    END                                                                   AS outreach_priority,
    -- Estimated annual revenue at stake for this customer
    ROUND(MonthlyCharges * 12, 2)                                         AS annual_value
FROM customer_churn
WHERE Churn           = 'No'            -- active customers only
  AND MonthlyCharges  >= 65.00          -- high-value threshold
  AND Contract        = 'Month-to-month'
ORDER BY
    ROUND(
        (CASE Contract
            WHEN 'Month-to-month' THEN 35
            WHEN 'One year'       THEN 15
            WHEN 'Two year'       THEN 5
        END)
        + GREATEST(30 - tenure, 0)
        + LEAST(ROUND(MonthlyCharges / 5, 0), 25)
        + CASE SeniorCitizen WHEN 'Yes' THEN 10 ELSE 0 END
    , 0) DESC,
    MonthlyCharges DESC
LIMIT 50;


-- ---------------------------------------------------------------------------
-- QUERY 3.2 : ACTIVE HIGH-VALUE CUSTOMER SUMMARY BY OUTREACH PRIORITY
-- ---------------------------------------------------------------------------
-- Business question: How many active high-value customers sit in each
--   outreach priority tier, and what is the total MRR we can protect?
--
-- This is the executive KPI summary version of Query 3.1 — a three-row
-- table that goes directly onto the Power BI Page 3 (At-Risk Intelligence)
-- as KPI cards or a summary table.
-- ---------------------------------------------------------------------------

SELECT
    CASE
        WHEN Contract = 'Month-to-month' AND tenure <= 12
             AND MonthlyCharges >= 65    THEN '1 — CRITICAL  (contact 48h)'
        WHEN Contract = 'Month-to-month' AND tenure <= 24
             AND MonthlyCharges >= 65    THEN '2 — HIGH      (contact this week)'
        WHEN Contract = 'Month-to-month' AND MonthlyCharges >= 65
                                         THEN '3 — MODERATE  (next campaign)'
        ELSE                                  '4 — STANDARD  (automated nurture)'
    END                                                                   AS outreach_priority,
    COUNT(*)                                                              AS active_customers,
    ROUND(AVG(MonthlyCharges), 2)                                         AS avg_monthly_charge,
    ROUND(SUM(MonthlyCharges), 2)                                         AS total_mrr_at_risk,
    ROUND(SUM(MonthlyCharges) * 12, 2)                                    AS annual_mrr_at_risk,
    ROUND(AVG(tenure), 1)                                                 AS avg_tenure_months,
    -- Estimated churners using observed churn rate for the tier
    ROUND(COUNT(*) * CASE
        WHEN Contract = 'Month-to-month' AND tenure <= 12
             AND MonthlyCharges >= 65    THEN 0.6740
        WHEN Contract = 'Month-to-month' AND tenure <= 24
             AND MonthlyCharges >= 65    THEN 0.4332
        WHEN Contract = 'Month-to-month' AND MonthlyCharges >= 65
                                         THEN 0.3080
        ELSE                                  0.0900
    END, 0)                                                               AS estimated_churners,
    -- MRR recoverable if 25% of estimated churners are saved
    ROUND(
        AVG(MonthlyCharges) * COUNT(*) * CASE
            WHEN Contract = 'Month-to-month' AND tenure <= 12
                 AND MonthlyCharges >= 65    THEN 0.6740
            WHEN Contract = 'Month-to-month' AND tenure <= 24
                 AND MonthlyCharges >= 65    THEN 0.4332
            WHEN Contract = 'Month-to-month' AND MonthlyCharges >= 65
                                             THEN 0.3080
            ELSE                                  0.0900
        END * 0.25, 2
    )                                                                     AS mrr_recoverable_at_25pct_save
FROM customer_churn
WHERE Churn = 'No'
  AND MonthlyCharges >= 65.00
GROUP BY
    CASE
        WHEN Contract = 'Month-to-month' AND tenure <= 12
             AND MonthlyCharges >= 65    THEN '1 — CRITICAL  (contact 48h)'
        WHEN Contract = 'Month-to-month' AND tenure <= 24
             AND MonthlyCharges >= 65    THEN '2 — HIGH      (contact this week)'
        WHEN Contract = 'Month-to-month' AND MonthlyCharges >= 65
                                         THEN '3 — MODERATE  (next campaign)'
        ELSE                                  '4 — STANDARD  (automated nurture)'
    END
ORDER BY outreach_priority;


-- ---------------------------------------------------------------------------
-- QUERY 3.3 : TOP 20 HIGHEST-REVENUE INDIVIDUAL ACCOUNTS AT RISK
-- ---------------------------------------------------------------------------
-- Business question: Which individual customers represent the greatest single-
--   account revenue risk if they churn in the next billing period?
--
-- This is the VIP list — the 20 customers where a personal call from a senior
-- account manager is justified by the revenue at stake. Every customer on
-- this list has not yet churned (Churn = 'No') and is on a month-to-month
-- contract, making them immediately actionable.
-- ---------------------------------------------------------------------------

SELECT
    customerID,
    tenure,
    tenure_band,
    SeniorCitizen,
    Partner,
    Contract,
    InternetService,
    MonthlyCharges,
    TotalCharges                                                          AS lifetime_revenue_so_far,
    ROUND(MonthlyCharges * 12, 2)                                         AS annual_value,
    PaymentMethod,
    -- Days at risk signal: lower tenure = more urgent
    CASE
        WHEN tenure <= 6   THEN 'NEW — highest churn probability'
        WHEN tenure <= 12  THEN 'EARLY — elevated churn risk'
        WHEN tenure <= 24  THEN 'DEVELOPING — moderate risk'
        ELSE                    'MATURING — lower risk but high value'
    END                                                                   AS lifecycle_stage
FROM customer_churn
WHERE Churn      = 'No'
  AND Contract   = 'Month-to-month'
ORDER BY MonthlyCharges DESC
LIMIT 20;


-- =============================================================================
-- SECTION 4 : RETENTION OPPORTUNITY FINANCIAL MODEL
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 4.1 : RETENTION PROGRAMME ROI BY VALUE TIER
-- ---------------------------------------------------------------------------
-- Business question: If we ran a retention programme targeting each value tier
--   with different intervention intensities, what is the expected financial return?
--
-- Programme cost assumptions (replace with actual costs before CFO presentation):
--   PREMIUM  : $150/customer (white-glove: account manager call + offer)
--   HIGH     : $75/customer  (outreach call + contract incentive)
--   STANDARD : $25/customer  (automated email campaign + price offer)
--
-- Recovery rate assumptions: 25% of at-risk customers successfully retained.
--   Conservative — industry benchmarks suggest 20–35% for personalised outreach.
-- ---------------------------------------------------------------------------

WITH tier_economics AS (
    SELECT
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 'PREMIUM'
            WHEN MonthlyCharges >= 65.00 THEN 'HIGH'
            ELSE                              'STANDARD'
        END                                                               AS value_tier,
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 150
            WHEN MonthlyCharges >= 65.00 THEN 75
            ELSE                              25
        END                                                               AS cost_per_contact,
        COUNT(*)                                                          AS total_churned,
        SUM(MonthlyCharges)                                               AS total_churned_mrr,
        AVG(MonthlyCharges)                                               AS avg_monthly
    FROM customer_churn
    WHERE Churn = 'Yes'
    GROUP BY
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 'PREMIUM'
            WHEN MonthlyCharges >= 65.00 THEN 'HIGH'
            ELSE                              'STANDARD'
        END,
        CASE
            WHEN MonthlyCharges >= 89.85 THEN 150
            WHEN MonthlyCharges >= 65.00 THEN 75
            ELSE                              25
        END
)
SELECT
    value_tier,
    total_churned                                                         AS churned_customers,
    ROUND(total_churned_mrr, 2)                                           AS churned_mrr,
    ROUND(total_churned_mrr * 12, 2)                                      AS annual_revenue_lost,
    cost_per_contact,
    -- Programme cost (contact all churned customers)
    ROUND(total_churned * cost_per_contact, 2)                            AS programme_cost,
    -- Revenue recovered at 25% save rate over 12 months
    ROUND(total_churned * 0.25 * avg_monthly * 12, 2)                     AS revenue_recovered_12mo,
    -- Net benefit
    ROUND((total_churned * 0.25 * avg_monthly * 12) - (total_churned * cost_per_contact), 2)
                                                                          AS net_annual_benefit,
    -- ROI ratio
    ROUND(
        (total_churned * 0.25 * avg_monthly * 12)
        / NULLIF(total_churned * cost_per_contact, 0), 2
    )                                                                     AS roi_ratio
FROM tier_economics
ORDER BY roi_ratio DESC;


-- =============================================================================
-- POWER BI RECOMMENDATIONS — SCRIPT 08
-- =============================================================================
-- Q1.1 → Donut or treemap: value_tier as segment, annual_at_risk as size.
--         The visual immediately shows Premium+High dominating the risk picture.
--
-- Q1.2 → Grouped bar: Contract on X-axis, bars per value_tier (three bars per
--         contract type), bar height = churn_rate_pct. The PREMIUM+M2M bar
--         towering over all others is the key visual message.
--
-- Q2.2 → 4-row KPI table on Page 3 of the dashboard. Four priority tiers,
--         colour-coded: red = CRITICAL, orange = HIGH, yellow = MODERATE,
--         grey = STANDARD. Include mrr_recoverable_at_25pct_save as a column.
--
-- Q3.1 → Filterable and sortable table on Page 3. Columns: customerID, tenure,
--         Contract, MonthlyCharges, risk_score, outreach_priority, annual_value.
--         Add a "Flag for Outreach" calculated column that the retention team
--         can mark after contact. This is the operational output of the project.
--
-- Q3.3 → Simple ranked table with colour gradient on MonthlyCharges.
--         Label the top 5 customers as "VIP accounts."
--
-- Q4.1 → Waterfall or stacked bar: value_tier on X-axis, bars show
--         programme_cost (negative) and revenue_recovered_12mo (positive),
--         net_annual_benefit as the delta label. ROI ratio as a data label.
-- =============================================================================


-- =============================================================================
-- INTERVIEW TALKING POINTS — SCRIPT 08
-- =============================================================================
-- "Script 08 is the part of my project that converts the analysis into action.
--  Every other script tells us why churn is happening and where. This one tells
--  the retention team who to call on Monday morning.
--
--  The composite risk score in Query 3.1 is something I'm particularly proud of.
--  It's not just 'these customers have high bills' — it weights four independent
--  risk factors: contract type, tenure, monthly charge level, and senior citizen
--  status. A customer scoring 85+ on that scale is someone who checks every
--  box: high value, no commitment, new to us, and in a demographic that churns
--  faster than average.
--
--  The triple-risk segment finding ($652K annual risk from 975 customers) was
--  the number that got the most attention in my mock executive presentation.
--  The retention manager's immediate response was 'how quickly can we build
--  that call list?' — which is exactly the outcome a data analyst should drive."
-- =============================================================================
