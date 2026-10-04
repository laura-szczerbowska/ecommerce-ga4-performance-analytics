# GA4 Product Performance & Conversion Analysis: Assortment Matrix & Recommendation Engine (Python | SQL | Power BI)

<br>

An end-to-end e-commerce analytical module integrating data processing in **Python (Pandas)**, data modeling in **SQL (PostgreSQL)**, and an interactive executive decision dashboard deployed in **Power BI**. Built on real-world commercial e-commerce data, this project directly addresses inefficient advertising budget allocation and assortment conversion bottlenecks within Google Analytics 4.

> **Data Provenance & Anonymization:**  
> This project was developed using production data from an active e-commerce store. To protect commercial confidentiality, the dataset has undergone full **anonymization**: brand names, product titles, campaign identifiers, and baseline metrics were transformed while preserving original relational integrity, correlations, conversion dynamics, and behavioral patterns.


<br>



https://github.com/user-attachments/assets/3328b689-e308-4a94-9a51-89d90d489d5c



<br>



## 1. Business Problem

E-commerce businesses investing across diverse acquisition channels (Google Ads Search, PMax, Ceneo/Referral, Organic Search) frequently misallocate budgets due to a lack of granular analysis at the intersection of **Product - Campaign - Micro-conversion**:

- **Budget Waste on Low-Intent Traffic:** Paid campaigns drive substantial traffic to products that generate impressions and views but fail to convert (low CR, high acquisition cost).
- **Undervalued High-Converting Assortment:** High-demand products with strong purchase intent are frequently starved of ad spend due to limited visibility in aggregated GA4 standard reporting.
- **Lack of Funnel Drop-off Diagnostics:** Standard reporting rarely distinguishes where users drop off: whether at the PDP and value proposition stage (Views $\to$ Cart Add) or during checkout friction (Cart Add $\to$ Purchase).

**Project Objective:** Build an automated end-to-end pipeline that segments products into an actionable performance matrix (*Traffic vs. Conversion Matrix*), visualizes micro-conversion funnels per SKU, and provides automated, operational marketing recommendations.


<br>


## 2. Architecture & Data Flow


```text
Raw GA4 CSV Exports (Campaigns + Categories)
       │
       ▼
1. Python Script (Pandas) - etl_pipeline.py
   ├── UTF-8-sig encoding support and corrupt row filtering
   ├── Quality audit: data types, missing values (isna), duplicates, and distribution stats
   └── Schema normalization into unified analytical columns
       │
       ▼
2. SQL Modeling & Business Logic Layer - View: products_analysis
   ├── LEFT JOIN with category pre-aggregation (eliminating Cartesian products)
   ├── Traffic classification: Paid Marketing vs. Free source
   ├── Statistical noise threshold: HAVING SUM(items_viewed) >= 10
   ├── Custom analytical metric: Volume Efficiency Score + Cart Intent flag
   └── Window Functions: DENSE_RANK() globally, by category, and by campaign
       │
       ▼
3. Power BI Decision Dashboard
   ├── Page 1: Executive KPIs + Assortment Performance Matrix (Views vs. CR vs. Revenue)
   ├── Report-Page Tooltip: Dynamic Micro-funnel (Views → Cart adds → Purchases)
   └── Page 2: Product Detail Card, Revenue Trend Analysis, and Strategic Recommendation Engine
```


<br>


## 3. Technical Implementation


### 1) Python - Data Engineering, Profiling & Sanitization (`etl_pipeline.py`)

- **Robust Ingestion:** Implemented `utf-8-sig` encoding handling (BOM neutralisation) along with `on_bad_lines="skip"` for parsing resilience.
- **Automated Data Profiling:** Audits head samples (`head(3)`), dataset dimensions (`shape`), schema datatypes (`dtypes`), null-rate checks (`isna().sum()`), and duplicate logging (`duplicated().sum()`).
- **Schema Normalization:** Standardizes raw localized GA4 header strings into unified analytical field names (`product_name`, `campaign_name`, `category_name`, `items_viewed`, `items_added_to_cart`, `items_purchased`, `item_revenue`).
- **SQL-Ready Output:** Exports validated datasets as clean, standardized CSV files (`encoding="utf-8-sig"`, `index=False`) structured for relational database staging.


<br>


-----
<details>
<summary><b>Expand Source Code: Python ETL (ga4_data_pipeline.py)</b></summary>

```python
import pandas as pd

# Terminal display configuration
pd.set_option('display.max_columns', None)
pd.set_option('display.width', 1000)

file_campaign = "products_campaign.csv"
file_category = "products_category.csv"

# Schema mapping GA4 raw export
camp_mapping = {
    'Nazwa': 'product_name',
    'Sesja – kampania': 'campaign_name',
    'Wyświetlone produkty': 'items_viewed',
    'Produkty dodane do koszyka': 'items_added_to_cart',
    'Kupione produkty': 'items_purchased',
    'Przychody z produktu': 'item_revenue'
}

cat_mapping = {
    "Nazwa": "product_name",
    "Kategoria produktu": "category_name",
    "Wyświetlone produkty": "items_viewed",
    "Produkty dodane do koszyka": "items_added_to_cart",
    "Kupione produkty": "items_purchased",
    "Przychody z produktu": "item_revenue",
}

# Loads raw CSV file, performs data integrity checks and logs quality metrics.
def load_and_audit(file_path):
    df = pd.read_csv(file_path, encoding="utf-8-sig", on_bad_lines="skip", sep=",")
    print(f"{df.head(3)}")
    print(f"Dimensions: {df.shape}")
    print(f"Data types: {df.dtypes}")
    print(f"Missing values:{df.isna().sum()}")
    print(f"Duplicate rows count: {df.duplicated().sum()}")
    return df

# Sanitizes records, maps column names, and exports ready-to-load CSV for SQL.
def clean_and_export(df, mapping, output_path):
    df_clean = df.rename(columns=mapping)
    df_clean.to_csv(output_path, index=False, encoding="utf-8-sig")
    print(f"Successfully exported:{output_path}")
    return df_clean

if __name__ == "__main__":
    df_camp_raw = load_and_audit(file_campaign)
    df_cat_raw = load_and_audit(file_category)

    df_camp = clean_and_export(df_camp_raw, camp_mapping, "campaign.csv")
    df_cat = clean_and_export(df_cat_raw, cat_mapping, "category.csv")

```


<br>


### 2) SQL - Modeling & Business Logic

- **Relational Deduplication:** Pre-aggregates the category dimension via `SELECT DISTINCT` inside a CTE, preventing fan-out rows and revenue inflation during `LEFT JOIN` operations.
- **Traffic Channel Categorization:** Groups diverse campaign structures into actionable business tiers: `Paid Marketing` (Google Ads Search, PMax, Ceneo) vs. `Free source` (Organic, Direct).
- **Statistical Significance Threshold:** Enforces `HAVING SUM(items_viewed) >= 10` to eliminate analytical noise (e.g., 1 impression resulting in 1 purchase creating a misleading 100% conversion rate).
- **Advanced Metrics & Window Functions:**
  * **Volume Efficiency Score:** Prioritizes products generating real transaction volume with a high conversion rate:


<br>


$$\text{Volume Efficiency Score} = \text{Total Purchased} \times \left( \frac{\text{Total Purchased}}{\text{Total Viewed}} \right)$$


<br>


  * **`cart_intent` Flag:** Binary indicator identifying whether a product initiated purchase intent (`total_cart_adds > 0`).
  * **Sales Ranking:** Computes relative revenue rank using `DENSE_RANK() OVER (...)` partitioned by campaign, category, and catalog-wide.

    
```sql
-----CREATE OR REPLACE VIEW products_analysis AS

/* join two tables */
WITH base_joined AS (
    SELECT 
        p.product_name,
        p.campaign_name,
        cat.category_name,
        p.items_viewed,
        p.items_added_to_cart,
        p.items_purchased,
        p.item_revenue
    FROM ga4_products p
    LEFT JOIN (
        SELECT DISTINCT 
            product_name, 
            category_name 
        FROM ga4_category
    ) cat 
        ON p.product_name = cat.product_name
),

aggregated_products AS (
    SELECT 
        product_name,
        category_name,
        COALESCE(NULLIF(campaign_name, '(not set)'), 'unidentified source') AS campaign_name,
        
        /* compare paid marketing vs free traffic */
        CASE 
            WHEN campaign_name IN (
                'Milwaukee-Ogród-Shopping', 
                'Milwaukee – Narzedzia4you – Search Website traffic-Search-3',
                'PMax | Distar | Sprzedaż | Polska', 
                'ceneo / referral'
            ) THEN 'Paid Marketing'
            ELSE 'Free source'
        END AS traffic_channel_type,
        
        SUM(items_viewed) AS total_viewed,
        SUM(items_added_to_cart) AS total_cart_adds,
        SUM(items_purchased) AS total_purchased,
        SUM(item_revenue) AS total_revenue
        
    FROM base_joined
    GROUP BY product_name, category_name, campaign_name, traffic_channel_type
    /* filter out low-traffic items (<10 views) to eliminate statistical noise in conversion rate calculation */
    HAVING SUM(items_viewed) >= 10
)

SELECT 
    product_name,
    category_name,
    campaign_name,
    traffic_channel_type,
    total_viewed,
    total_cart_adds,
    total_purchased,
    total_revenue,

    /* Check if anyone added the item to cart */
    CASE 
        WHEN total_cart_adds > 0 THEN 1
        ELSE 0
    END AS cart_intent,

    /* find top products based on sales and conversion, ignoring price */
    ROUND(total_purchased * (total_purchased * 1.0 / NULLIF(total_viewed, 0)), 3) AS volume_efficiency_score,

    /* rank products by revenue: inside the campaign and overall in the store */
    DENSE_RANK() OVER (PARTITION BY campaign_name ORDER BY total_revenue DESC) AS product_rank_in_campaign,
    DENSE_RANK() OVER (PARTITION BY category_name ORDER BY total_revenue DESC) AS product_rank_in_category,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS global_revenue_rank

FROM aggregated_products
ORDER BY global_revenue_rank ASC;
```


<br>


## 4. Power BI Dashboard & Visual Layer

> **Data Modeling:** Built a dedicated DAX calendar table (`calendar`) with dynamic date ranges (1:N relationship with fact tables) to support Time Intelligence calculations and timeline continuity. Implemented a dedicated product dimension table (`Dim_Product`) to eliminate Many-to-Many (M:N) relationships and maintain a clean star schema.


<br>


### 1) Page 1: Executive Overview & Product Performance Matrix


<br>


<img width="1377" height="773" alt="image" src="https://github.com/user-attachments/assets/54581925-dc93-4893-b3ca-82ea202db40b" />

<p>&nbsp;</p>

- **Executive KPI Cards:** Store-wide high-level metrics at a glance: overall Conversion Rate (`CR = 4%`), Average Order Value (`AOV = 416.21 PLN`), Total Revenue (`Revenue = 129.86k PLN`), and Completed Purchases (`Purchase = 312`).
  
- **Product Performance Matrix (*Traffic vs. CR*):**
  * **X-Axis:** `views` (Traffic / Impression Volume)
  * **Y-Axis:** `CR` (Conversion Rate)
  * **Bubble Size:** `total_revenue` (Monetary Revenue)
  * **Dynamic Reference Lines** segment the catalog into 4 operational quadrants (filtered via the `Choose matrix segment` slicer):
    * **High Yield (High Traffic, High CR):** Core revenue drivers; require inventory prioritization and stable marketing budget support.
    * **High Potential (Low Traffic, High CR):** High-converting products lacking exposure; prime candidates for immediate ad spend scaling (e.g., dedicated PMax campaigns).
    * **Requires Optimization (High Traffic, Low CR):** Budget drains; require landing page / CRO audits, price benchmarking against competitors, or narrower keyword targeting.
    * **Underperforming (Low Traffic, Low CR):** Inefficient catalog items; candidate for ad phase-out, clearance discounting, or product bundling.
      
- **Market Breakdown Charts:** Bar charts categorizing revenue distribution across acquisition channels (Referral and Search dominance) and key categories (Garden Tools, Power Tools).


<br>


### 2) Dedicated Tooltip: Product Micro-Funnel (*Report Page Tooltip*)


<br>


<img width="532" height="365" alt="image" src="https://github.com/user-attachments/assets/e702026c-1a52-4be8-aef1-280c1e640462" />

<p>&nbsp;</p>

Hovering over any matrix bubble reveals a customized visual tooltip showing the **complete product micro-funnel**:


<br>


$$\text{Views } (222) \longrightarrow \text{Cart adds } (176) \longrightarrow \text{Purchase } (71)$$


<br>


The tooltip immediately presents SKU-level revenue, CR, and AOV, pinpointing whether user friction occurs during the PDP review stage or checkout execution.


<br>


### 3) Page 2: Product Card, Trend Analysis & Strategic Recommendation Engine


<br>


<p align="center">
  <img width="1375" height="772" alt="image" src="https://github.com/user-attachments/assets/b74dd08c-a63c-46e4-bf5a-2177281961d0" />
</p>

<p>&nbsp;</p>

- **Interactive Navigation:** Smooth navigation to detailed views via **"View product trend"** alongside a centralized reset action via **"Clear all slicers"**.
- **Revenue Trend Over Time:** Line chart displaying sales dynamics, demand seasonality, and revenue velocity around promotional peaks.
- **Strategic Recommendations Matrix:** A rule-based engine mapping product performance and campaign channels to clear operational actions:
  * **For Referral Traffic with High CR (43%):** *Maintain ad spend and feature as anchors to boost underperforming campaigns*.
  * **For Search Campaigns with Low CR (2%):** *Drive conversion through promotional offers, streamlined checkout, fast delivery, cross-selling, and targeted SEO/keywords*.
  * **For Niche Sources (High CR, Low Volume):** *Increase marketing and advertising budget, improve SEO, and explore brand partnerships*.


<br>


## 5. Key Business Takeaways

1. **Referral Channel Efficiency:** Referral sources generated the highest conversion rate and highest AOV at a significantly lower unit acquisition cost than generic Google Ads Search campaigns.
2. **Checkout Bottlenecks:** Micro-funnel tooltip diagnostics revealed that specific products generated high add-to-cart volumes (strong buyer intent) followed by sharp abandonment prior to payment, indicating an immediate need to re-evaluate free shipping thresholds and checkout friction.
3. **Budget Reallocation:** Isolating products in the *Requires Optimization* quadrant allowed the business to exclude non-converting keywords and redirect spend toward high-margin items in the *High Potential* quadrant.


<br>


## 6. Tech Stack

- **Database & SQL:** PostgreSQL (CTEs, Window Functions, conditional aggregation, views)
- **Visualization & BI:** Microsoft Power BI Desktop (DAX, Star Schema, Report-Page Tooltips, Drill-through, Page Interactions)
- **Data Engineering:** Python (Pandas, ETL, data quality auditing)
- **Data Source:** E-commerce event exports from Google Analytics 4 (GA4)


<br>


## 7. Repository Structure

```text
ecommerce-ga4-analytics/
├── data/
│   ├── raw/
│   │   ├── products_campaign.csv        # Raw GA4 export (campaign dimension)
│   │   └── products_category.csv        # Raw GA4 export (category dimension)
│   └── processed/
│       ├── campaign.csv                 # Cleaned campaign dataset
│       └── category.csv                 # Cleaned category dataset
├── sql/
│   └── 01_products_analysis.sql         # View creation and business logic script
├── powerbi/
│   └── ecommerce_performance_dashboard.pbix   # Power BI production report
├── scripts/
│   └── ga4_data_pipeline.py             # Python data cleansing & ETL script
└── README.md
└── README.pl.md
```


<br>


## 8. Getting Started

1) Clone the repository:

```bash
git clone [https://github.com/your-username/ecommerce-ga4-analytics.git](https://github.com/your-username/ecommerce-ga4-analytics.git)
cd ecommerce-ga4-analytics
```


2) Run the data cleaning pipeline:
```
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install pandas
python scripts/ga4_data_pipeline.py
```


3)Initialize database views:
* Import campaign.csv and category.csv into your database as tables ga4_products and ga4_category.
* Execute the script sql/01_products_analysis.sql.

4)Open the dashboard:
* Open powerbi/ecommerce_performance_dashboard.pbix in Power BI Desktop.
* Refresh data connections pointing to your PostgreSQL instance or processed local files.


<br>


## 9. Future Roadmap

- **End-to-End Pipeline Automation:** Transition from manual CSV ingestion to scheduled automated orchestration using the GA4 BigQuery Export.
- **Cost Data Integration (ROAS):** Ingest ad spend from Google Ads and Meta Ads APIs to calculate true multi-channel Return on Ad Spend (ROAS).
- **Predictive Analytics:** Implement RFM customer segmentation and churn/cart abandonment probability models based on user behavioral events.
- **Inventory Integration:** Join real-time ERP inventory levels with conversion velocity to pause ad spend automatically when stock levels fall below critical thresholds.


<br>


## 10. Key Takeaways

This project bridges web analytics, data engineering, and business intelligence, transforming raw event data into automated operational decisions:

- **Waste Reduction:** Flags products in the *Requires Optimization* quadrant (high traffic, low CR) for immediate keyword trimming and budget preservation.
- **Revenue Scaling:** Uncovers hidden gems in the *High Potential* quadrant (low traffic, high CR) to scale paid ad budgets effectively.
- **Micro-Funnel Diagnostics:** Distinguishes top-of-funnel PDP messaging issues from bottom-of-funnel checkout drop-offs via visual SKU-level tooltips.
- **Comprehensive Analytics Portfolio:** Showcases
