-- =============================================================================
-- Script       : 01_database_setup.sql
-- Project      : Telecom Customer Churn Analysis
-- Author       : [Your Name]
-- Created      : 2024
-- Database     : MySQL 8.0
-- Description  : Creates the database, raw staging table, and cleaned
--                analytical table. Imports the IBM Telco Customer Churn
--                dataset, applies all documented cleaning transformations,
--                and runs validation assertions to gate downstream analysis.
-- Data Source  : IBM Telco Customer Churn Dataset (7,043 rows, 21 columns)
-- Depends on   : WA_Fn-UseC_-Telco-Customer-Churn.csv
-- Next script  : 02_churn_overview.sql
-- =============================================================================
-- MYSQL NOTES (changes from PostgreSQL original):
--   [M1] CREATE SCHEMA → CREATE DATABASE; USE churn replaces schema prefix
--   [M2] COPY command → LOAD DATA INFILE
--   [M3] ::TYPE cast syntax → CAST(expr AS TYPE) with MySQL type names
--        NUMERIC(10,2) → DECIMAL(10,2) | INTEGER → SIGNED
--   [M4] CREATE INDEX IF NOT EXISTS → conditional DROP + CREATE (safe for 8.0)
--   [M5] SUM(COUNT(*)) OVER() window on raw aggregate not needed in Section 3 —
--        total computed via subquery in the one validation query that used it
-- =============================================================================


-- =============================================================================
-- SECTION 1 : DATABASE AND RAW STAGING TABLE
-- =============================================================================
-- We load the CSV into a raw staging table first. Every column is VARCHAR.
-- This is intentional: it protects against silent type coercion failures
-- (TotalCharges has 11 blank-string records that would cause a hard import
-- error if the column were declared DECIMAL at load time).
-- The cleaned analytical table is created in Section 4 after validation.
-- =============================================================================

-- [M1] MySQL uses databases, not schemas. All subsequent statements run
-- inside this database — no schema prefix required on table names.
CREATE DATABASE IF NOT EXISTS churn
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE telecom_churn;

-- Drop and recreate raw staging table (idempotent for re-runs)
DROP TABLE IF EXISTS raw_customer_data;

CREATE TABLE raw_customer_data (
    customerID        VARCHAR(20),
    gender            VARCHAR(10),
    SeniorCitizen     VARCHAR(5),       -- imported as string; 0/1 values
    Partner           VARCHAR(5),
    Dependents        VARCHAR(5),
    tenure            VARCHAR(5),       -- imported as string; range 0–72
    PhoneService      VARCHAR(25),
    MultipleLines     VARCHAR(25),
    InternetService   VARCHAR(20),
    OnlineSecurity    VARCHAR(25),
    OnlineBackup      VARCHAR(25),
    DeviceProtection  VARCHAR(25),
    TechSupport       VARCHAR(25),
    StreamingTV       VARCHAR(25),
    StreamingMovies   VARCHAR(25),
    Contract          VARCHAR(20),
    PaperlessBilling  VARCHAR(5),
    PaymentMethod     VARCHAR(40),
    MonthlyCharges    VARCHAR(15),      -- imported as string; range 18.25–118.75
    TotalCharges      VARCHAR(15),      -- 11 rows contain blank string ' '
    Churn             VARCHAR(5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- SECTION 2 : DATA IMPORT
-- =============================================================================
-- [M2] MySQL uses LOAD DATA INFILE instead of PostgreSQL's COPY command.
--
-- PREREQUISITES:
--   1. Place the CSV at the path shown below (or update the path).
--   2. MySQL server must have FILE privilege enabled for your user:
--      GRANT FILE ON *.* TO 'your_user'@'localhost';
--   3. The server variable secure_file_priv must permit the file path.
--      Check with: SHOW VARIABLES LIKE 'secure_file_priv';
--      If non-empty, move the CSV to that directory.
--
-- ALTERNATIVE (if LOAD DATA INFILE is restricted):
--   Use MySQL Workbench → Table Data Import Wizard on raw_customer_data,
--   selecting "all columns as VARCHAR". Then proceed from Section 3.
-- =============================================================================

LOAD DATA INFILE '/path/to/WA_Fn-UseC_-Telco-Customer-Churn.csv'
INTO TABLE raw_customer_data
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customerID, gender, SeniorCitizen, Partner, Dependents, tenure,
 PhoneService, MultipleLines, InternetService, OnlineSecurity,
 OnlineBackup, DeviceProtection, TechSupport, StreamingTV,
 StreamingMovies, Contract, PaperlessBilling, PaymentMethod,
 MonthlyCharges, TotalCharges, Churn);


-- =============================================================================
-- SECTION 3 : RAW DATA VALIDATION
-- =============================================================================
-- Run these checks before creating the cleaned table. Any assertion that
-- returns a FAIL status indicates a data quality issue requiring investigation.
-- Document all findings in data/data_dictionary.md.
-- =============================================================================

-- 3a. Row count check — must equal 7,043
SELECT
    COUNT(*)                                                      AS total_rows,
    CASE WHEN COUNT(*) = 7043 THEN 'PASS' ELSE 'FAIL' END        AS row_count_check
FROM raw_customer_data;

-- 3b. Primary key integrity — customerID must be unique and non-null
SELECT
    COUNT(*)                                                      AS total_rows,
    COUNT(DISTINCT customerID)                                    AS distinct_customers,
    COUNT(*) - COUNT(DISTINCT customerID)                         AS duplicate_ids,
    SUM(CASE WHEN customerID IS NULL THEN 1 ELSE 0 END)           AS null_ids,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT customerID)
         AND SUM(CASE WHEN customerID IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END                                                           AS pk_integrity_check
FROM raw_customer_data;

-- 3c. Identify TotalCharges blank strings (known issue: 11 rows, all tenure=0)
-- Expected: exactly 11 rows with blank TotalCharges, all having tenure='0'
SELECT
    customerID,
    tenure,
    MonthlyCharges,
    TotalCharges,
    Churn,
    'Blank TotalCharges — tenure=0 new customer'                  AS data_note
FROM raw_customer_data
WHERE TRIM(TotalCharges) = ''
ORDER BY customerID;

-- 3d. SeniorCitizen encoding check — must only contain '0' or '1'
SELECT
    SeniorCitizen,
    COUNT(*)                                                      AS record_count
FROM raw_customer_data
GROUP BY SeniorCitizen
ORDER BY SeniorCitizen;

-- 3e. Churn label distribution — validate expected class proportions
-- [M5] SUM(COUNT(*)) OVER() replaced with a cross-joined total subquery
--      because MySQL 8 does not allow nested aggregates inside window functions.
SELECT
    r.Churn,
    COUNT(*)                                                      AS customer_count,
    ROUND(COUNT(*) * 100.0 / t.total, 2)                         AS pct_of_total
FROM raw_customer_data r
CROSS JOIN (SELECT COUNT(*) AS total FROM raw_customer_data) t
GROUP BY r.Churn, t.total
ORDER BY r.Churn;
-- Expected: No = 5,174 (73.46%)  |  Yes = 1,869 (26.54%)

-- 3f. Validate categorical columns have only expected values
SELECT InternetService, COUNT(*) AS n
FROM raw_customer_data
GROUP BY InternetService;
-- Expected: 'DSL' | 'Fiber optic' | 'No'

SELECT Contract, COUNT(*) AS n
FROM raw_customer_data
GROUP BY Contract;
-- Expected: 'Month-to-month' | 'One year' | 'Two year'

SELECT PaymentMethod, COUNT(*) AS n
FROM raw_customer_data
GROUP BY PaymentMethod;
-- Expected: 'Electronic check' | 'Mailed check' |
--           'Bank transfer (automatic)' | 'Credit card (automatic)'

-- 3g. Numeric range sanity checks
-- [M3] ::INT and ::NUMERIC replaced with CAST(... AS SIGNED) / CAST(... AS DECIMAL)
SELECT
    MIN(CAST(tenure         AS SIGNED))                           AS tenure_min,       -- Expected: 0
    MAX(CAST(tenure         AS SIGNED))                           AS tenure_max,       -- Expected: 72
    MIN(CAST(MonthlyCharges AS DECIMAL(10,2)))                    AS monthly_min,      -- Expected: 18.25
    MAX(CAST(MonthlyCharges AS DECIMAL(10,2)))                    AS monthly_max,      -- Expected: 118.75
    MIN(CASE WHEN TRIM(TotalCharges) = '' THEN NULL
             ELSE CAST(TotalCharges AS DECIMAL(10,2)) END)        AS total_min,        -- Expected: 18.80
    MAX(CAST(TotalCharges   AS DECIMAL(10,2)))                    AS total_max         -- Expected: 8684.80
FROM raw_customer_data
WHERE TRIM(TotalCharges) != '';


-- =============================================================================
-- SECTION 4 : CLEANED ANALYTICAL TABLE
-- =============================================================================
-- Applies six documented cleaning transformations:
--   T1 : Cast tenure to SIGNED INTEGER
--   T2 : Cast MonthlyCharges to DECIMAL(10,2)
--   T3 : Cast TotalCharges to DECIMAL(10,2); blank strings → 0.00
--         (tenure=0 customers have no completed billing period; $0 is logically
--          correct, not an imputation assumption)
--   T4 : Normalise SeniorCitizen from '0'/'1' to 'No'/'Yes' (aligns with all
--         other binary flag columns; preserves original in raw table)
--   T5 : Create Churn_Binary TINYINT(1) column: 'Yes'→1, 'No'→0
--         (required for SUM/AVG-based churn rate calculations in all
--          downstream SQL scripts; avoids repeated CASE WHEN expressions)
--   T6 : Create tenure_band derived column using standard cohort boundaries
--         (0–12 = early lifecycle risk window; 13–24 = retention inflection;
--          25–48 = maturing; 49–72 = loyal/established)
--
-- [M3] All ::TYPE casts replaced with CAST(expr AS TYPE) using MySQL type names.
--      NUMERIC(10,2) → DECIMAL(10,2)
--      ::INTEGER     → CAST(... AS SIGNED)
-- =============================================================================

DROP TABLE IF EXISTS customer_churn;

CREATE TABLE customer_churn AS
SELECT
    -- Identity
    customerID,

    -- Demographics
    gender,
    CASE SeniorCitizen
        WHEN '1' THEN 'Yes'
        WHEN '0' THEN 'No'
        ELSE SeniorCitizen
    END                                                           AS SeniorCitizen,   -- T4
    Partner,
    Dependents,

    -- Account tenure — typed correctly [M3]
    CAST(tenure AS SIGNED)                                        AS tenure,          -- T1

    -- TotalCharges — blank strings → 0.00 [M3]
    CASE
        WHEN TRIM(TotalCharges) = ''
        THEN CAST(0.00 AS DECIMAL(10,2))
        ELSE CAST(TotalCharges AS DECIMAL(10,2))
    END                                                           AS TotalCharges,    -- T3

    -- Derived tenure cohort for segmentation and survival analysis [T6]
    CASE
        WHEN CAST(tenure AS SIGNED) BETWEEN 0  AND 12 THEN '0-12 months'
        WHEN CAST(tenure AS SIGNED) BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN CAST(tenure AS SIGNED) BETWEEN 25 AND 48 THEN '25-48 months'
        WHEN CAST(tenure AS SIGNED) BETWEEN 49 AND 72 THEN '49-72 months'
        ELSE 'Unknown'
    END                                                           AS tenure_band,     -- T6

    -- Services
    PhoneService,
    MultipleLines,
    InternetService,
    OnlineSecurity,
    OnlineBackup,
    DeviceProtection,
    TechSupport,
    StreamingTV,
    StreamingMovies,

    -- Contract and billing terms
    Contract,
    PaperlessBilling,
    PaymentMethod,

    -- MonthlyCharges — typed correctly [M3]
    CAST(MonthlyCharges AS DECIMAL(10,2))                         AS MonthlyCharges,  -- T2

    -- Target variable — both forms retained for flexibility
    Churn,
    CASE Churn
        WHEN 'Yes' THEN 1
        WHEN 'No'  THEN 0
        ELSE NULL
    END                                                           AS Churn_Binary     -- T5

FROM raw_customer_data;


-- =============================================================================
-- SECTION 5 : POST-CLEAN VALIDATION ASSERTIONS
-- =============================================================================
-- All five assertions must return PASS before any downstream script is run.
-- =============================================================================

-- Assertion A : Row count preserved
SELECT
    COUNT(*)                                                      AS rows_after_clean,
    CASE WHEN COUNT(*) = 7043 THEN 'PASS' ELSE 'FAIL' END        AS assertion_a_row_count
FROM customer_churn;

-- Assertion B : TotalCharges has zero nulls (blanks → 0.00)
SELECT
    SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END)         AS null_total_charges,
    CASE
        WHEN SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END                                                           AS assertion_b_nulls
FROM customer_churn;

-- Assertion C : Churn_Binary sum matches expected churned customer count
SELECT
    SUM(Churn_Binary)                                             AS churned_customers,
    CASE WHEN SUM(Churn_Binary) = 1869 THEN 'PASS' ELSE 'FAIL' END
                                                                  AS assertion_c_churn_count
FROM customer_churn;

-- Assertion D : SeniorCitizen normalised — only 'Yes'/'No' values remain
SELECT
    SeniorCitizen,
    COUNT(*)                                                      AS n
FROM customer_churn
GROUP BY SeniorCitizen
ORDER BY SeniorCitizen;
-- Expected: 'No' = 5,901  |  'Yes' = 1,142

-- Assertion E : Tenure band coverage — no 'Unknown' values
SELECT
    tenure_band,
    COUNT(*)                                                      AS customer_count
FROM customer_churn
GROUP BY tenure_band
ORDER BY
    CASE tenure_band
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
        ELSE 5
    END;
-- Expected: 2,186 | 1,024 | 1,594 | 2,239 (total 7,043, no 'Unknown')


-- =============================================================================
-- SECTION 6 : INDEXING FOR QUERY PERFORMANCE
-- =============================================================================
-- [M4] MySQL 8.0 supports CREATE INDEX IF NOT EXISTS from 8.0.12+.
--      Using safe DROP + CREATE pattern for compatibility across all 8.0.x
--      patch versions. The DROP IGNORE silently skips if index doesn't exist.
-- =============================================================================

-- Helper: safe index creation macro pattern
-- MySQL does not support CREATE INDEX IF NOT EXISTS before 8.0.12,
-- so we use a single ALTER TABLE statement which is idempotent-safe
-- when combined with the DROP approach below.

-- Drop existing indexes first (safe — IF EXISTS supported in MySQL 8 for DROP)
DROP INDEX IF EXISTS idx_churn_binary    ON customer_churn;
DROP INDEX IF EXISTS idx_contract        ON customer_churn;
DROP INDEX IF EXISTS idx_internet_service ON customer_churn;
DROP INDEX IF EXISTS idx_tenure_band     ON customer_churn;
DROP INDEX IF EXISTS idx_payment_method  ON customer_churn;
DROP INDEX IF EXISTS idx_customer_id     ON customer_churn;

-- Recreate indexes
CREATE INDEX idx_churn_binary     ON customer_churn (Churn_Binary);
CREATE INDEX idx_contract         ON customer_churn (Contract);
CREATE INDEX idx_internet_service ON customer_churn (InternetService);
CREATE INDEX idx_tenure_band      ON customer_churn (tenure_band);
CREATE INDEX idx_payment_method   ON customer_churn (PaymentMethod);
CREATE INDEX idx_customer_id      ON customer_churn (customerID);


-- =============================================================================
-- SECTION 7 : DATA DICTIONARY INLINE REFERENCE
-- =============================================================================
-- Full documentation lives in data/data_dictionary.md.
-- Quick reference for analysts querying customer_churn (after USE churn).
--
-- Column               Type               Notes
-- ------------------   ----------------   ------------------------------------
-- customerID           VARCHAR(20)        Primary key. Format: XXXX-XXXXX
-- gender               VARCHAR(10)        'Male' | 'Female'
-- SeniorCitizen        VARCHAR(5)         'Yes' | 'No' [T4: normalised from 0/1]
-- Partner              VARCHAR(5)         'Yes' | 'No'
-- Dependents           VARCHAR(5)         'Yes' | 'No'
-- tenure               INT (SIGNED)       Months as customer. Range: 0–72
-- TotalCharges         DECIMAL(10,2)      Cumulative revenue. 11 tenure=0 rows = 0.00
-- tenure_band          VARCHAR(20)        Derived cohort [T6]
-- PhoneService         VARCHAR(25)        'Yes' | 'No'
-- MultipleLines        VARCHAR(25)        'Yes' | 'No' | 'No phone service'
-- InternetService      VARCHAR(20)        'DSL' | 'Fiber optic' | 'No'
-- OnlineSecurity       VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- OnlineBackup         VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- DeviceProtection     VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- TechSupport          VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- StreamingTV          VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- StreamingMovies      VARCHAR(25)        'Yes' | 'No' | 'No internet service'
-- Contract             VARCHAR(20)        'Month-to-month' | 'One year' | 'Two year'
-- PaperlessBilling     VARCHAR(5)         'Yes' | 'No'
-- PaymentMethod        VARCHAR(40)        'Electronic check' | 'Mailed check' |
--                                         'Bank transfer (automatic)' |
--                                         'Credit card (automatic)'
-- MonthlyCharges       DECIMAL(10,2)      Current monthly bill. Range: $18.25–$118.75
-- Churn                VARCHAR(5)         Target variable. 'Yes' | 'No'
-- Churn_Binary         TINYINT(1)         1 = churned, 0 = retained [T5]
-- =============================================================================
