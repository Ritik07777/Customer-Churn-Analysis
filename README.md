# 📊 Telecom Customer Churn Analysis & Retention Dashboard

> **An end-to-end Data Analytics project leveraging MySQL, Python, and Power BI to identify customer churn drivers, quantify business impact, and provide actionable retention strategies for a telecom company.**

---

## 📌 Project Overview

Customer churn is one of the most significant challenges faced by subscription-based businesses. Acquiring a new customer is considerably more expensive than retaining an existing one, making customer retention a critical business objective.

This project presents a complete end-to-end analytics workflow using the IBM Telco Customer Churn dataset. The objective was to analyze customer behavior, identify the primary factors contributing to churn, and translate analytical findings into business recommendations through an interactive Power BI dashboard.

The project combines SQL for business analysis, Python for data cleaning and exploratory analysis, and Power BI for interactive visualization, demonstrating a practical analytics workflow commonly used in real-world business environments.

---

## 🎯 Business Problem

The telecom company is experiencing customer attrition across multiple service segments but lacks clear visibility into:

* Which customers are most likely to churn.
* Which business factors contribute most to customer loss.
* How churn impacts revenue and customer retention.
* Which customer segments should be prioritized for retention campaigns.

The objective of this project is to transform raw customer data into meaningful business insights that support data-driven decision-making and improve customer retention strategies.

---

## 🎯 Project Objectives

* Analyze customer demographics, services, contracts, and billing information.
* Perform structured SQL analysis to uncover business trends and churn patterns.
* Clean and prepare data using Python for accurate analysis.
* Conduct Exploratory Data Analysis (EDA) to identify key churn drivers.
* Build an interactive Power BI dashboard for executive-level decision making.
* Deliver actionable business recommendations based on analytical findings.

---

# 🛠️ Technology Stack

| Category                 | Technologies                       |
| ------------------------ | ---------------------------------- |
| **Database**             | MySQL                              |
| **Programming Language** | Python                             |
| **Python Libraries**     | Pandas, NumPy, Matplotlib, Seaborn |
| **Data Visualization**   | Power BI                           |
| **Version Control**      | Git & GitHub                       |
| **Dataset**              | IBM Telco Customer Churn Dataset   |

---

# 📂 Project Structure

```text
Customer-Churn-Analysis/
│
├── data/
│   ├── raw/
│   └── processed/
│
├── notebooks/
│   ├── 01_Data_Cleaning.ipynb
│   ├── 02_Exploratory_Data_Analysis.ipynb
│   └── 03_Churn_Prediction.ipynb
│
├── sql/
│   ├── 01_database_setup.sql
│   ├── 02_churn_overview.sql
│   ├── ...
│   └── 09_cohort_clv_analysis.sql
│
├── powerbi/
│   └── Telecom_Customer_Churn_Analysis.pbix
│
├── screenshots/
│   ├── Python/
│   ├── SQL/
│   └── PowerBI/
│
├── reports/
│   └── analysis_summary.md
│
├── presentation/
│
├── visualizations_archive/
│
├── README.md
├── requirements.txt
└── LICENSE
```

---

# 🔄 Project Workflow

```text
IBM Telco Customer Churn Dataset
                │
                ▼
        MySQL Business Analysis
                │
                ▼
     Python Data Cleaning & Preprocessing
                │
                ▼
      Exploratory Data Analysis (EDA)
                │
                ▼
      Business Insights & KPI Extraction
                │
                ▼
     Interactive Power BI Dashboard
                │
                ▼
     Actionable Retention Recommendations
```

---

# ✨ Project Highlights

* Performed end-to-end customer churn analysis using SQL, Python, and Power BI.
* Cleaned and transformed raw customer data for reliable business analysis.
* Identified high-risk customer segments through exploratory data analysis.
* Designed a three-page interactive Power BI dashboard for executive reporting.
* Developed business-focused KPIs to monitor churn rate, customer retention, revenue impact, and customer segmentation.
* Converted analytical findings into actionable business recommendations aimed at improving customer retention.


---

# 📊 Interactive Dashboard

The final Power BI dashboard was designed to provide business stakeholders with an interactive view of customer churn patterns, financial impact, and customer segmentation.

### Executive Overview

Provides a high-level summary of customer churn, revenue impact, retention metrics, and contract-wise churn performance for executive decision-making.

> *![Executive Overview](screenshots/PowerBI/Executive_Overview.png)

![Churn Driver Analysis](screenshots/PowerBI/Churn_Driver_Analysis.png)

![At Risk Customer Analysis](screenshots/PowerBI/At_Risk_Customer_Analysis.png)*

---

### Churn Driver Analysis

Analyzes the major factors influencing customer churn, including contract type, payment method, internet service, tenure, online security, and technical support.

> *(Dashboard screenshot will be displayed here.)*

---

### At-Risk Customer Analysis

Identifies high-risk customer segments through interactive filtering, customer-level analysis, revenue distribution, and service segmentation to support targeted retention strategies.

> *(Dashboard screenshot will be displayed here.)*

---

# 💡 Key Business Insights

* Month-to-month contract customers exhibit significantly higher churn than customers with long-term contracts.
* Customers using Electronic Check as their payment method demonstrate a comparatively higher churn rate.
* Fiber Optic customers generate substantial revenue while also experiencing elevated churn, making them a critical retention segment.
* Customers with shorter tenure are considerably more likely to leave, highlighting the importance of early customer engagement.
* Value-added services such as Online Security and Tech Support are associated with improved customer retention.

---

# 📈 Business Recommendations

Based on the analysis, the following strategic recommendations are proposed:

* Encourage customers to transition from month-to-month contracts to annual or long-term contracts through targeted promotional offers.
* Introduce onboarding and engagement programs for new customers during the initial months of their subscription.
* Bundle Online Security and Tech Support services with Fiber Optic plans to improve customer retention.
* Develop personalized retention campaigns for customers identified as high-risk segments.
* Monitor churn-related KPIs regularly through the interactive Power BI dashboard to support proactive business decision-making.

---

# 🚀 Future Improvements

Potential enhancements for future versions of this project include:

* Develop a machine learning model to predict customer churn probability.
* Deploy the dashboard to Power BI Service for cloud-based reporting.
* Automate data refresh using scheduled ETL pipelines.
* Integrate customer lifetime value (CLV) analysis for more targeted retention strategies.
* Expand the dashboard with predictive analytics and advanced segmentation.

---

# 🙏 Acknowledgements

* IBM Telco Customer Churn Dataset
* Microsoft Power BI
* Python Open Source Community
* MySQL

---

## 👨‍💻 Author

**Ritik**

Aspiring Data Analyst passionate about transforming raw data into actionable business insights using SQL, Python, and Power BI.

If you found this project useful, consider giving the repository a ⭐.
