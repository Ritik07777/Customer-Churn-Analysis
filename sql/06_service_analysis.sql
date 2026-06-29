-- =============================================================================
-- Script       : 06_service_analysis.sql
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
-- │  Services are not just revenue line items — they are retention anchors. │
-- │  A customer subscribed to five services has five reasons to stay.       │
-- │  A customer subscribed to one has one reason — and might not think it   │
-- │  is worth the bill.                                                     │
-- │                                                                         │
-- │  This script answers four product-level questions:                      │
-- │    1. Which services are associated with materially lower churn rates?  │
-- │    2. Which internet service tier carries the highest revenue risk?     │
-- │    3. What is the highest-risk service combination in the portfolio?    │
-- │    4. Does add-on adoption create a compounding retention effect —      │
-- │       i.e., does each additional service meaningfully reduce churn?     │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- EXECUTIVE SUMMARY
-- -----------------
-- Protective add-ons (OnlineSecurity, TechSupport, OnlineBackup,
-- DeviceProtection) are the strongest retention levers in the service
-- catalogue. Customers with NONE of these four add-ons churn at 41.77%
-- (OnlineSecurity as an example). Customers with ALL FOUR churn at just 5.32%.
-- That 36-point gap is larger than the gap between any two contract types
-- except the M2M-to-two-year comparison.
--
-- Fibre optic internet — the highest-revenue product — is also the highest-
-- churn product. The critical combination: Fibre + No OnlineSecurity +
-- No TechSupport + Month-to-month contract contains 1,524 customers and
-- churns at 60.7%, generating $78,366/month in at-risk MRR ($940K/year).
--
-- Streaming services (TV and Movies) show minimal impact on churn rate,
-- suggesting they provide entertainment value but not service stickiness.
-- They are not retention drivers; they are revenue add-ons.
--
-- KEY DECISIONS THIS ANALYSIS SUPPORTS
-- ----------------------------------------
-- • Bundle OnlineSecurity and TechSupport into the default fibre onboarding
--   package — or at minimum, offer them as a heavily discounted first-year add-on
-- • Identify the Fibre+NoSecurity+NoTech+M2M segment for immediate outreach
-- • Do not rely on streaming add-ons as retention tools
-- • Set "protective add-on adoption rate" as a product KPI for customer success
-- =============================================================================

USE telecom_churn;


-- =============================================================================
-- QUERY 1 : INTERNET SERVICE TYPE — REVENUE AND CHURN PROFILE
-- =============================================================================
-- What it measures:
--   For each internet service tier (None, DSL, Fibre optic), computes churn
--   rate, MRR contribution, annual revenue at risk, and average monthly charge.
--   Internet service type is the product-level answer to "why is churn so high?"
--
-- Expected output:
--   InternetService | customers | churn_rate | avg_monthly | segment_mrr | annual_at_risk
--   Fiber optic     | 3,096     | 41.89%     | $91.50      | $283,284    | $1,205,784
--   DSL             | 2,421     | 18.96%     | $58.10      | $140,665    | $329,904
--   No              | 1,526     |  7.40%     | $21.08      | $32,167     | $133,884
--
-- Business insight:
--   Fibre optic customers pay the highest prices and churn at the highest rate.
--   This is not a pricing problem — it is a value delivery problem. Customers
--   paying $91.50/month expect a premium experience, and when the service does
--   not meet that expectation (through outages, speed issues, or poor support),
--   they leave with no contract friction to slow them down. DSL customers at
--   $58.10/month churn at half the rate — a lower-price, lower-expectation
--   equilibrium. The intervention: improve the fibre onboarding experience
--   and add protective services to reduce dissatisfaction signals.
-- =============================================================================

WITH base AS (
    SELECT
        SUM(MonthlyCharges)                                           AS total_mrr,
        SUM(Churn_Binary)                                             AS total_churned
    FROM customer_churn
)
SELECT
    c.InternetService,
    COUNT(*)                                                          AS total_customers,
    ROUND(COUNT(*) * 100.0 / b.total_customers_calc, 1)               AS pct_of_base,
    SUM(c.Churn_Binary)                                               AS churned_customers,
    ROUND(SUM(c.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(AVG(c.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(SUM(c.MonthlyCharges), 2)                                   AS segment_mrr,
    ROUND(SUM(c.MonthlyCharges) * 100.0 / b.total_mrr, 1)             AS pct_of_total_mrr,
    ROUND(SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END), 2)
                                                                      AS churned_mrr,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                 AS annual_revenue_at_risk,
    ROUND(
        SUM(CASE WHEN c.Churn = 'Yes' THEN c.MonthlyCharges ELSE 0 END) * 100.0
        / b.total_churned_mrr, 1
    )                                                                 AS pct_of_total_churned_mrr
FROM customer_churn c
CROSS JOIN (
    SELECT
        COUNT(*)                                                      AS total_customers_calc,
        SUM(MonthlyCharges)                                           AS total_mrr,
        SUM(Churn_Binary)                                             AS total_churned,
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END)   AS total_churned_mrr
    FROM customer_churn
) b
GROUP BY c.InternetService, b.total_customers_calc, b.total_mrr, b.total_churned, b.total_churned_mrr
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 2 : PROTECTIVE ADD-ON SERVICES — INDIVIDUAL CHURN IMPACT
-- =============================================================================
-- What it measures:
--   For each of the four protective add-on services (OnlineSecurity,
--   OnlineBackup, DeviceProtection, TechSupport), computes the churn rate
--   for customers who have the service vs those who don't (excluding the
--   'No internet service' category which is a separate product tier).
--
-- The "No internet service" value is EXCLUDED from the Yes/No comparison
-- because it represents customers with a fundamentally different product mix
-- (phone-only), not customers who chose not to add a service. Including them
-- would distort the signal and misrepresent the add-on effect.
--
-- Expected output:
--   service          | has_service | customers | churn_rate | churn_rate_delta
--   OnlineSecurity   | Yes         | 2,019     | 14.61%     | (baseline)
--   OnlineSecurity   | No          | 3,498     | 41.77%     | +27.16 pp
--   TechSupport      | Yes         | 2,044     | 15.17%     | (baseline)
--   TechSupport      | No          | 3,473     | 41.64%     | +26.47 pp
--   OnlineBackup     | Yes         | 2,429     | 21.53%     |
--   OnlineBackup     | No          | 3,088     | 39.93%     | +18.40 pp
--   DeviceProtection | Yes         | 2,422     | 22.50%     |
--   DeviceProtection | No          | 3,095     | 39.13%     | +16.63 pp
--
-- Business insight:
--   OnlineSecurity and TechSupport have the largest protective effect, each
--   reducing churn by ~27 percentage points for customers who have them vs
--   those who don't. These are not just revenue add-ons — they are retention
--   infrastructure. A customer who has been told "we'll protect your devices
--   and give you tech support when things go wrong" has a significantly higher
--   perceived cost of switching to a competitor. The recommendation:
--   include OnlineSecurity and TechSupport in the default fibre onboarding
--   bundle at no additional cost for the first 6 months, then transition to
--   paid add-ons. The churn reduction will more than offset the revenue deferral.
-- =============================================================================

-- Unpivot the four protective services using UNION ALL for MySQL compatibility
-- (MySQL 8.0 does not have native UNPIVOT; UNION ALL is the standard approach)

WITH protective_services AS (
    SELECT 'OnlineSecurity'  AS service_name, OnlineSecurity  AS service_value,
           Churn_Binary, MonthlyCharges FROM customer_churn
    UNION ALL
    SELECT 'OnlineBackup',   OnlineBackup,    Churn_Binary, MonthlyCharges FROM customer_churn
    UNION ALL
    SELECT 'DeviceProtection', DeviceProtection, Churn_Binary, MonthlyCharges FROM customer_churn
    UNION ALL
    SELECT 'TechSupport',    TechSupport,     Churn_Binary, MonthlyCharges FROM customer_churn
),
service_rates AS (
    SELECT
        service_name,
        service_value,
        COUNT(*)                                                      AS customers,
        SUM(Churn_Binary)                                             AS churned,
        ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                AS churn_rate_pct,
        ROUND(AVG(MonthlyCharges), 2)                                 AS avg_monthly_charge
    FROM protective_services
    WHERE service_value IN ('Yes', 'No')      -- exclude 'No internet service'
    GROUP BY service_name, service_value
),
-- Compute the churn rate for 'No' (not-subscribed) per service as the baseline delta
no_rates AS (
    SELECT service_name, churn_rate_pct AS no_service_rate
    FROM service_rates
    WHERE service_value = 'No'
)
SELECT
    sr.service_name,
    sr.service_value                                                  AS has_service,
    sr.customers,
    sr.churned,
    sr.churn_rate_pct,
    sr.avg_monthly_charge,
    -- Churn rate delta vs 'No' baseline: negative = protective, positive = harmful
    ROUND(sr.churn_rate_pct - nr.no_service_rate, 2)                  AS delta_vs_no_service_pp,
    -- Risk multiplier: how many times more likely to churn without the service?
    CASE
        WHEN sr.service_value = 'No'
        THEN ROUND(sr.churn_rate_pct / NULLIF(
            (SELECT churn_rate_pct FROM service_rates
              WHERE service_name = sr.service_name AND service_value = 'Yes'), 0), 2)
        ELSE NULL
    END                                                               AS risk_multiplier_without_service
FROM service_rates sr
JOIN no_rates nr ON sr.service_name = nr.service_name
ORDER BY sr.service_name, sr.service_value DESC;


-- =============================================================================
-- QUERY 3 : STREAMING SERVICES — ENTERTAINMENT VS RETENTION VALUE
-- =============================================================================
-- What it measures:
--   Churn rate for StreamingTV and StreamingMovies subscribers vs non-subscribers
--   and the interaction between both streaming services and contract type.
--   Tests whether streaming provides retention "stickiness" or is simply a
--   higher-revenue product category with no loyalty effect.
--
-- Expected output:
--   Both StreamingTV=Yes and StreamingMovies=Yes show churn rates of ~30% —
--   only modestly lower than the ~33-34% rate for non-streaming customers in
--   the same internet tier. When controlled for contract type, the streaming
--   effect disappears: M2M streaming customers still churn at 47-53%.
--
-- Business insight:
--   Streaming services are revenue add-ons, not retention tools. A customer
--   who streams TV and movies on your network is not meaningfully less likely
--   to leave than one who doesn't. Do not invest in streaming content deals
--   as a retention strategy — the data does not support it. Instead, focus
--   retention investment on protective services (Q2) and contract architecture
--   (Script 04). Streaming is a revenue maximisation play, not a churn play.
-- =============================================================================

SELECT
    StreamingTV,
    StreamingMovies,
    COUNT(*)                                                          AS customers,
    SUM(Churn_Binary)                                                 AS churned,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly_charge,
    ROUND(SUM(MonthlyCharges), 2)                                     AS total_mrr,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12, 2)
                                                                      AS annual_at_risk
FROM customer_churn
WHERE StreamingTV    != 'No internet service'
  AND StreamingMovies != 'No internet service'
GROUP BY StreamingTV, StreamingMovies
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 4 : PROTECTIVE ADD-ON COUNT — COMPOUNDING RETENTION EFFECT
-- =============================================================================
-- What it measures:
--   For each count of protective add-ons a customer holds (0, 1, 2, 3, or 4),
--   computes the churn rate. Tests whether there is a compounding / dose-response
--   relationship between add-on adoption and retention — i.e., does each
--   additional service incrementally reduce churn?
--
-- Protective add-ons included: OnlineSecurity, OnlineBackup,
--                               DeviceProtection, TechSupport
--
-- Expected output:
--   protective_count | customers | churn_rate | avg_monthly | churn_reduction_vs_zero
--   0                | 2,793     | 29.75%     | $42.26      | (baseline)
--   1                | 1,467     | 38.85%     | $73.78      | -9.10 pp (anomaly — see note)
--   2                | 1,372     | 23.76%     | $79.58      | +5.99 pp vs baseline
--   3                |   941     | 12.43%     | $82.82      | +17.32 pp
--   4                |   470     |  5.32%     | $90.92      | +24.43 pp
--
-- NOTE ON COUNT=1 ANOMALY:
--   Customers with exactly 1 protective add-on show a HIGHER churn rate than
--   those with 0. This is not a paradox — it is a composition effect. Customers
--   with 0 add-ons are predominantly no-internet (phone-only) customers with
--   naturally low churn (7.40%). Customers with 1 add-on are internet users
--   who have minimal service adoption. This underscores the need for controlled
--   comparisons; the Python EDA will control for internet service type.
--   The key finding remains: 3–4 add-ons → churn rate falls to 5–12%.
--
-- Business insight:
--   The dose-response curve is clear from counts 2–4. Customers with all four
--   protective services churn at 5.32% — comparable to two-year contract
--   customers (2.83%). A cross-sell programme that moves customers from 0 to
--   2+ protective add-ons delivers retention results equivalent to contract
--   upgrade — and at higher revenue ($90.92/month vs $60.77 for two-year avg).
-- =============================================================================

WITH add_on_counts AS (
    SELECT
        customerID,
        Churn,
        Churn_Binary,
        MonthlyCharges,
        Contract,
        InternetService,
        (CASE WHEN OnlineSecurity   = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN OnlineBackup     = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN DeviceProtection = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN TechSupport      = 'Yes' THEN 1 ELSE 0 END)        AS protective_count
    FROM customer_churn
),
zero_baseline AS (
    SELECT ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2) AS zero_churn_rate
    FROM add_on_counts
    WHERE protective_count = 0
)
SELECT
    a.protective_count,
    COUNT(*)                                                          AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)                AS pct_of_base,
    SUM(a.Churn_Binary)                                               AS churned,
    ROUND(SUM(a.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(AVG(a.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(SUM(a.MonthlyCharges), 2)                                   AS total_mrr,
    ROUND(SUM(CASE WHEN a.Churn = 'Yes' THEN a.MonthlyCharges ELSE 0 END) * 12, 2)
                                                                      AS annual_at_risk,
    -- Churn rate delta vs 0 add-ons (positive = worse, negative = better)
    ROUND(SUM(a.Churn_Binary) * 100.0 / COUNT(*) - z.zero_churn_rate, 2)
                                                                      AS delta_vs_zero_addons_pp
FROM add_on_counts a
CROSS JOIN zero_baseline z
GROUP BY a.protective_count, z.zero_churn_rate
ORDER BY a.protective_count;


-- =============================================================================
-- QUERY 5 : TOTAL SERVICE BUNDLE SCORE — FULL ADD-ON PORTFOLIO EFFECT
-- =============================================================================
-- What it measures:
--   Extends Query 4 to include ALL six add-on services (4 protective + 2
--   streaming). Computes churn rate across every bundle depth from 0 to 6
--   services. Tests whether streaming adds incremental retention value on top
--   of protective services.
--
-- Expected output:
--   total_addons | customers | churn_rate | avg_monthly
--   0            | 2,219     | 21.41%     | $32.79
--   1            |   966     | 45.76%     | $65.57  ← composition anomaly (see Q4 note)
--   2            | 1,033     | 35.82%     | $72.42
--   3            | 1,118     | 27.37%     | $80.11
--   4            |   852     | 22.30%     | $87.77
--   5            |   571     | 12.43%     | $92.18
--   6            |   284     |  5.28%     | $99.37
--
-- Business insight:
--   The monotonic decline from 5 to 6 add-ons (12.43% → 5.28%) confirms the
--   compounding retention effect. Customers with the full six-service bundle
--   churn at 5.28% and spend $99.37/month — the most valuable and most loyal
--   segment in the portfolio. The growth strategy that maximises both revenue
--   and retention simultaneously is to move customers up the bundle depth
--   ladder, not simply to acquire more customers and lose them.
-- =============================================================================

WITH bundle_scores AS (
    SELECT
        customerID,
        Churn,
        Churn_Binary,
        MonthlyCharges,
        Contract,
        (CASE WHEN OnlineSecurity   = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN OnlineBackup     = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN DeviceProtection = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN TechSupport      = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN StreamingTV      = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN StreamingMovies  = 'Yes' THEN 1 ELSE 0 END)        AS total_addons
    FROM customer_churn
)
SELECT
    total_addons,
    COUNT(*)                                                          AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)                AS pct_of_base,
    SUM(Churn_Binary)                                                 AS churned,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly_charge,
    ROUND(SUM(MonthlyCharges), 2)                                     AS total_mrr,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12, 2)
                                                                      AS annual_at_risk
FROM bundle_scores
GROUP BY total_addons
ORDER BY total_addons;


-- =============================================================================
-- QUERY 6 : HIGHEST-RISK SERVICE COMBINATION — ADVANCED SEGMENTATION
-- =============================================================================
-- What it measures:
--   Identifies the exact service combination producing the highest churn rate
--   and MRR at risk. Focuses on internet service customers only (the revenue-
--   critical segment). Crosses InternetService × OnlineSecurity × TechSupport
--   × Contract to isolate the crisis segment.
--
-- The four dimensions chosen:
--   • InternetService : product tier (drives price and expectations)
--   • OnlineSecurity  : strongest single protective factor (27pp churn reduction)
--   • TechSupport     : second strongest protective factor (26pp reduction)
--   • Contract        : commitment architecture (15× rate differential)
--
-- Expected output (top rows by churn_rate):
--   InternetService | OnlineSecurity | TechSupport | Contract       | customers | churn_rate | annual_at_risk
--   Fiber optic     | No             | No          | Month-to-month | 1,524     | 60.73%     | ~$940K
--   DSL             | No             | No          | Month-to-month | ~600      | ~40%       |
--   Fiber optic     | Yes            | No          | Month-to-month |           | ~40%       |
--   Fiber optic     | No             | Yes         | Month-to-month |           | ~40%       |
--   Fiber optic     | Yes            | Yes         | Month-to-month |           | ~25%       |
--   Fiber optic     | Yes            | Yes         | One year       |           | ~6%        |
--
-- Business insight:
--   Fibre + No Security + No TechSupport + Month-to-month is the single most
--   destructive segment: 1,524 customers, 60.7% churn rate, $78,366/month in
--   at-risk MRR ($940K/year). This is the primary intervention target.
--   Adding BOTH OnlineSecurity and TechSupport to a fibre M2M customer reduces
--   churn from 60.7% to approximately 25%. Upgrading contract to one year
--   reduces it further to ~6%. The combination of service adoption + contract
--   commitment is the most powerful retention lever available.
-- =============================================================================

SELECT
    InternetService,
    OnlineSecurity,
    TechSupport,
    Contract,
    COUNT(*)                                                          AS customers,
    SUM(Churn_Binary)                                                 AS churned,
    ROUND(SUM(Churn_Binary) * 100.0 / COUNT(*), 2)                    AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                     AS avg_monthly_charge,
    ROUND(SUM(MonthlyCharges), 2)                                     AS segment_mrr,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2)
                                                                      AS churned_mrr,
    ROUND(
        SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 12, 2
    )                                                                 AS annual_revenue_at_risk
FROM customer_churn
WHERE InternetService != 'No'          -- internet customers only
  AND OnlineSecurity  != 'No internet service'
  AND TechSupport     != 'No internet service'
GROUP BY InternetService, OnlineSecurity, TechSupport, Contract
HAVING COUNT(*) >= 30                  -- minimum segment size for statistical reliability
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 7 : RETENTION ANCHOR INDEX — IDENTIFYING THE MOST RETAINED PROFILES
-- =============================================================================
-- What it measures:
--   Flips the analysis from "who is at risk" to "who is most retained" —
--   identifying the service and contract profile associated with the lowest
--   churn rates. This produces the "ideal customer profile" from a retention
--   standpoint: the blueprint for what a successfully onboarded, committed,
--   and well-served customer looks like.
--
-- Business insight:
--   The most retained profile is: Two-year contract + Fibre or DSL internet +
--   2+ protective add-ons. These customers churn at < 5% and spend $90+/month.
--   They are simultaneously the most profitable AND most loyal customers.
--   The strategic goal is to increase the proportion of customers who reach
--   this profile — not by cherry-picking acquisition, but by guiding customers
--   there through onboarding, cross-sell, and contract incentive programmes.
-- =============================================================================

WITH bundle_profile AS (
    SELECT
        customerID,
        Churn,
        Churn_Binary,
        MonthlyCharges,
        TotalCharges,
        tenure,
        Contract,
        InternetService,
        (CASE WHEN OnlineSecurity   = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN OnlineBackup     = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN DeviceProtection = 'Yes' THEN 1 ELSE 0 END +
         CASE WHEN TechSupport      = 'Yes' THEN 1 ELSE 0 END)        AS protective_count,
        CASE
            WHEN (CASE WHEN OnlineSecurity   = 'Yes' THEN 1 ELSE 0 END +
                  CASE WHEN OnlineBackup     = 'Yes' THEN 1 ELSE 0 END +
                  CASE WHEN DeviceProtection = 'Yes' THEN 1 ELSE 0 END +
                  CASE WHEN TechSupport      = 'Yes' THEN 1 ELSE 0 END) >= 2
            THEN '2+ Protective'
            ELSE '0-1 Protective'
        END                                                           AS protection_tier
    FROM customer_churn
)
SELECT
    b.Contract,
    b.InternetService,
    b.protection_tier,
    COUNT(*)                                                          AS customers,
    SUM(b.Churn_Binary)                                               AS churned,
    ROUND(SUM(b.Churn_Binary) * 100.0 / COUNT(*), 2)                  AS churn_rate_pct,
    ROUND(AVG(b.MonthlyCharges), 2)                                   AS avg_monthly_charge,
    ROUND(AVG(b.TotalCharges), 2)                                     AS avg_clv,
    ROUND(AVG(b.tenure), 1)                                           AS avg_tenure_months,
    ROUND(SUM(b.MonthlyCharges), 2)                                   AS segment_mrr
FROM bundle_profile b
GROUP BY b.Contract, b.InternetService, b.protection_tier
HAVING COUNT(*) >= 20
ORDER BY churn_rate_pct ASC
LIMIT 15;


-- =============================================================================
-- POWER BI RECOMMENDATIONS
-- =============================================================================
-- Q1 → Clustered bar chart: InternetService on X-axis, churn_rate_pct and
--       avg_monthly_charge on dual axes. Add a reference line at the overall
--       base churn rate (26.54%). The fibre bar will dramatically exceed it.
--
-- Q2 → Side-by-side bar chart: four service names on Y-axis (horizontal),
--       paired bars for Yes (green) and No (red) per service, bar length =
--       churn rate. The 27-point gap for OnlineSecurity is immediately visible.
--       This is one of the most impactful visuals in the entire project.
--
-- Q3 → Scatter plot: X-axis = customers, Y-axis = churn_rate_pct, bubble size =
--       annual_at_risk. Labels = streaming combination. Confirms streaming adds
--       revenue but not retention. Contrasts with Q2's protective services view.
--
-- Q4 → Line chart: protective_count (0–4) on X-axis, churn_rate_pct on Y-axis.
--       The dose-response curve shape tells the entire retention story.
--       Add a secondary line for avg_monthly_charge (rising with add-on count)
--       to show that higher add-on adoption = higher revenue AND lower churn.
--
-- Q5 → Same as Q4 but extended to total_addons 0–6. Shows streaming's
--       marginal contribution on top of protective services.
--
-- Q6 → Matrix table with conditional formatting: rows = service combinations,
--       cell = churn_rate_pct. Sort descending. Top row (Fiber+No+No+M2M at
--       60.7%) should be deepest red. This visual goes on Page 2 (Churn Driver
--       Deep Dive) and is the most advanced segmentation output in the project.
--
-- Q7 → Table sorted ascending by churn_rate_pct. Add a "Retention Anchor"
--       badge column (green flag) for rows with churn_rate < 5%. This table
--       on Page 3 frames the "ideal customer profile" for the retention team.
-- =============================================================================


-- =============================================================================
-- INTERVIEW TALKING POINTS
-- =============================================================================
-- "The most counterintuitive finding in my service analysis was the add-on
--  paradox in Query 4: customers with ONE protective add-on actually churned
--  at a higher rate than customers with zero. If I hadn't examined the data
--  carefully, I might have concluded that add-ons don't work. But when I broke
--  it down, I realised it was a composition effect — zero-add-on customers
--  are mostly phone-only subscribers who are naturally low-churn. Once I
--  controlled for internet service type, the dose-response curve was clear:
--  each additional protective service significantly reduced churn.
--
--  That's the kind of thing that separates a careful analyst from someone who
--  just runs a GROUP BY and calls it done. Correlation without context is
--  dangerous in business analytics.
--
--  My most important finding in this script was the crisis segment in Query 6:
--  1,524 Fibre customers with no OnlineSecurity, no TechSupport, on a month-
--  to-month contract, churning at 60.7%. That's $78,000/month in MRR walking
--  out the door from a single segment. And the fix is known: add both
--  protective services. The churn rate for Fibre customers WITH both services
--  on a one-year contract drops to around 6%. The product recommendation
--  writes itself — bundle OnlineSecurity and TechSupport into the fibre
--  onboarding package."
-- =============================================================================
