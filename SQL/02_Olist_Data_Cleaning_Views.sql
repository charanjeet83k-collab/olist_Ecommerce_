/*==============================================================================
 FILE 2 of 4 - DATA CLEANING VIEWS                     Database: olist_ECommerce
 The 9 source tables are NEVER changed: no UPDATE / DELETE / DROP TABLE is used.
 Cleaning = VIEWS. Raw values stay available (columns ending _raw or kept as-is);
 every problem becomes a FLAG column (flag_...) so nothing is silently discarded.
 Safe to re-run: CREATE OR ALTER VIEW (SQL Server 2016 SP1 or later).
 STATUS: written; NOT executed by the author. Run 01 first, then this file, then 03 and 04.
 Each CREATE VIEW must be the first statement of its batch - keep the GO lines.

 ISSUE REGISTER  (detect = query in file 01 | result = Python cross-check | rule | view | validate = file 04)
 ---------------------------------------------------------------------------------------------------------------
 I1  NULL/blank category          01:2.3,4.8,7.6 | 610 products | keep, label 'Unknown'             | vw_clean_products       | 04:V4
 I2  Category w/o English name    01:4.8         | 13 products (2 categories) | keep Portuguese name, flag | vw_clean_products | 04:V4
 I3  Weight = 0 / NULL            01:5.6,2.3     | 4 zero, 2 NULL | raw kept, weight_g = NULL when 0, flag | vw_clean_products | 04:V4
 I4  customer_id vs unique id     01:3.3         | 96,096 people / 99,441 records | count people by unique id | vw_analytics_customers | 04:V9
 I5  Dates wrong order            01:6.3,6.7     | carrier<purchase 161; delivered<carrier 23; approved>carrier 1,358 | flag, keep row | vw_clean_orders | 04:V5
 I6  Status vs date mismatch      01:6.4         | delivered w/o date 8; not delivered with date 6 | flag; excluded from delivery KPIs | vw_clean_orders | 04:V5
 I7  Far-future shipping date     01:5.4         | 4 rows after 2018 | flag, keep value | vw_clean_order_items | 04:V5
 I8  Orders without items         01:4.4,8.8     | 775 (all have payments) | has_items=0, excluded from sales KPIs | vw_analytics_orders | 04:V3
 I9  Order without payment        01:4.6         | 1 | has_payment=0 | vw_analytics_orders | 04:V3
 I10 Repeated review_id / many reviews per order 01:3.6,3.7 | 814 extra rows; 547 orders | flags; average per order | vw_clean_order_reviews, vw_agg_order_reviews | 04:V2,V6
 I11 Orders without review        01:4.7         | 768 | has_review=0 (not an error) | vw_analytics_orders | 04:V3
 I12 Review before purchase       01:6.6         | 74 | flag, keep | vw_clean_order_reviews | 04:V5
 I13 Blank review text            01:2.10        | 2 titles, 27 messages space-only | blank -> NULL in clean column, raw kept | vw_clean_order_reviews | 04:V4
 I14 Zero payment / not_defined / 0 instalments 01:5.3,8.5 | 9 / 3 / 2 | flags; kept | vw_clean_order_payments | 04:V4
 I15 Zero freight                 01:5.2         | 383 | flag (may be free shipping) | vw_clean_order_items | 04:V4
 I16 Item vs payment totals differ 01:8.1        | 249 orders by >1 BRL | measures kept separate; reconcile | vw_analytics_orders | 04:V8
 I17 Geolocation duplicates / many rows per ZIP / outside Brazil 01:3.9,3.10,9.1 | 261,836 / 17,972 ZIPs / 42 rows | one row per ZIP, outside points excluded from the ZIP view | vw_clean_geolocation_zip | 04:V2
 I18 City text issues             01:7.3,7.4,7.5 | seller 20 odd; geolocation 8,556 ZIPs with several spellings | trim/lower; flag | vw_clean_sellers, vw_clean_geolocation_points | 04:V4
 I19 ZIP without geolocation      01:4.10        | 278 customer rows; 7 seller rows | LEFT JOIN keeps them (no coordinates) | vw_clean_geolocation_zip | 04:V3
==============================================================================*/
USE olist_ECommerce

/*---- 1. CUSTOMERS---*/
CREATE OR ALTER VIEW vw_clean_customers AS
SELECT c.customer_id, c.customer_unique_id, c.customer_zip_code_prefix AS zip_prefix,
       c.customer_city AS customer_city_raw,
       LOWER(LTRIM(RTRIM(c.customer_city))) AS customer_city,
       UPPER(LTRIM(RTRIM(c.customer_state))) AS customer_state,
       CASE WHEN c.customer_city IS NULL OR LTRIM(RTRIM(c.customer_city)) = '' THEN 1 ELSE 0 END AS flag_blank_city
FROM Customer as c


/*---- 2. SELLERS: */
CREATE OR ALTER VIEW vw_clean_sellers AS
SELECT s.seller_id, s.seller_zip_code_prefix AS zip_prefix, s.seller_city AS seller_city_raw,
       LOWER(LTRIM(RTRIM(s.seller_city))) AS seller_city, UPPER(LTRIM(RTRIM(s.seller_state))) AS seller_state,
       CASE WHEN s.seller_city LIKE '%[0-9/@,]%' THEN 1 ELSE 0 END AS flag_city_has_symbols
FROM sellers as s

/*---- 3. PRODUCTS: grain = one row per product. category = English name; if no translation keep Portuguese; if NULL/blank -> 'Unknown' (I1,I2). */
CREATE OR ALTER VIEW vw_clean_products AS
SELECT p.product_id, p.product_category_name AS category_pt,
       COALESCE(t.product_category_name_english, NULLIF(LTRIM(RTRIM(p.product_category_name)), ''), 'Unknown') AS category,
       CASE WHEN NULLIF(LTRIM(RTRIM(p.product_category_name)), '') IS NULL THEN 1 ELSE 0 END AS flag_category_missing,
       CASE WHEN NULLIF(LTRIM(RTRIM(p.product_category_name)), '') IS NOT NULL AND t.product_category_name IS NULL THEN 1 ELSE 0 END AS 
       flag_category_untranslated,
       p.product_weight_g AS weight_g_raw, NULLIF(p.product_weight_g, 0) AS weight_g,
       CASE WHEN p.product_weight_g = 0 THEN 1 ELSE 0 END AS flag_weight_zero,
       p.product_length_cm, p.product_height_cm, p.product_width_cm, p.product_photos_qty
FROM products as p
LEFT JOIN product_category_name_translation as t ON t.product_category_name = p.product_category_name

/*---- 4. ORDERS: grain = one row per order. Dates converted with TRY_CONVERT; date/status problems flagged (I5,I6). */
CREATE OR ALTER VIEW dbo.vw_clean_orders AS
WITH d AS (
  SELECT o.order_id, o.customer_id, o.order_status,
         TRY_CONVERT(DATETIME2, o.order_purchase_timestamp)AS purchase_ts,
         TRY_CONVERT(DATETIME2, o.order_approved_at)AS approved_ts,
         TRY_CONVERT(DATETIME2, o.order_delivered_carrier_date) AS carrier_ts,
         TRY_CONVERT(DATETIME2, o.order_delivered_customer_date)AS delivered_ts,
         TRY_CONVERT(DATETIME2, o.order_estimated_delivery_date)AS estimated_ts
  FROM orders as o)
SELECT d.*,
       CASE WHEN d.carrier_ts   < d.purchase_ts THEN 1 ELSE 0 END AS flag_carrier_before_purchase,
       CASE WHEN d.delivered_ts < d.carrier_ts  THEN 1 ELSE 0 END AS flag_delivered_before_carrier,
       CASE WHEN d.approved_ts  > d.carrier_ts  THEN 1 ELSE 0 END AS flag_approved_after_carrier,
       CASE WHEN d.estimated_ts < d.purchase_ts THEN 1 ELSE 0 END AS flag_estimated_before_purchase,
       CASE WHEN d.order_status = 'delivered'  AND d.delivered_ts IS NULL THEN 1 ELSE 0 END AS flag_delivered_status_no_date,
       CASE WHEN d.order_status <> 'delivered' AND d.delivered_ts IS NOT NULL THEN 1 ELSE 0 END AS flag_not_delivered_has_date,
       CASE WHEN d.order_status = 'delivered' AND d.delivered_ts IS NOT NULL AND d.delivered_ts >= d.purchase_ts
                 AND (d.carrier_ts IS NULL OR d.delivered_ts >= d.carrier_ts) THEN 1 ELSE 0 END AS valid_delivery  
FROM d

/*---- 5. ORDER ITEMS: grain = one row per item line. Adds clean category, seller state and flags (I7,I15). */
CREATE OR ALTER VIEW dbo.vw_clean_order_items AS
SELECT i.order_id, i.order_item_id, i.product_id, i.seller_id, i.price, i.freight_value,
       TRY_CONVERT(DATETIME2, i.shipping_limit_date)AS shipping_limit_ts,
       p.category, p.weight_g, s.seller_state, s.zip_prefix AS seller_zip_prefix,
       CASE WHEN i.price <= 0 THEN 1 ELSE 0 END AS flag_price_not_positive,
       CASE WHEN i.freight_value = 0 THEN 1 ELSE 0 END AS flag_freight_zero,
       CASE WHEN YEAR(TRY_CONVERT(DATETIME2, i.shipping_limit_date)) > 2018 THEN 1 ELSE 0 END AS flag_shipping_limit_after_2018
FROM order_items i
LEFT JOIN vw_clean_products p ON p.product_id = i.product_id
LEFT JOIN vw_clean_sellers  s ON s.seller_id  = i.seller_id

/*---- 6. PAYMENTS: grain = one row per payment part (order_id + payment_sequential). Flags only (I14). */
CREATE OR ALTER VIEW dbo.vw_clean_order_payments AS
SELECT p.order_id, p.payment_sequential, p.payment_type, p.payment_installments, p.payment_value,
       CASE WHEN p.payment_value = 0 THEN 1 ELSE 0 END AS flag_value_zero,
       CASE WHEN p.payment_value < 0 THEN 1 ELSE 0 END AS flag_value_negative,
       CASE WHEN p.payment_type = 'not_defined' THEN 1 ELSE 0 END AS flag_type_not_defined,
       CASE WHEN p.payment_installments < 1 THEN 1 ELSE 0 END AS flag_installments_below_1
FROM order_payments as p

/*---- 7. REVIEWS: grain = one row per review record. review_id is NOT unique, so flags show repeats (I10,I12,I13). */
CREATE OR ALTER VIEW vw_clean_order_reviews AS
SELECT r.review_id, r.order_id, r.review_score,
       r.review_comment_title AS review_comment_title_raw, NULLIF(LTRIM(RTRIM(r.review_comment_title)), '') AS review_comment_title,
       r.review_comment_message AS review_comment_message_raw, NULLIF(LTRIM(RTRIM(r.review_comment_message)), '') AS review_comment_message,
       TRY_CONVERT(DATETIME2, r.review_creation_date) AS created_ts, TRY_CONVERT(DATETIME2, r.review_answer_timestamp) AS answered_ts,
       CASE WHEN r.review_score NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END AS flag_score_invalid,
       CASE WHEN COUNT(*) OVER (PARTITION BY r.review_id) > 1 THEN 1 ELSE 0 END AS flag_review_id_repeated,
       CASE WHEN COUNT(*) OVER (PARTITION BY r.order_id)  > 1 THEN 1 ELSE 0 END AS flag_order_has_several_reviews,
       CASE WHEN TRY_CONVERT(DATETIME2, r.review_creation_date) < o.purchase_ts THEN 1 ELSE 0 END AS flag_created_before_purchase
FROM order_reviews r
LEFT JOIN vw_clean_orders o ON o.order_id = r.order_id

/*---- 8. GEOLOCATION POINTS: grain = one row per source point (duplicates kept). Flags points outside a Brazil box (I17,I18). */
CREATE OR ALTER VIEW vw_clean_geolocation_points AS
SELECT g.geolocation_zip_code_prefix AS zip_prefix, g.geolocation_lat AS lat, g.geolocation_lng AS lng,
       LOWER(LTRIM(RTRIM(g.geolocation_city))) AS city, UPPER(LTRIM(RTRIM(g.geolocation_state))) AS state,
       CASE WHEN g.geolocation_lat BETWEEN -34 AND 5.3 AND g.geolocation_lng BETWEEN -74 AND -34 THEN 0 ELSE 1 END AS flag_outside_brazil
FROM geolocation_ as g

/*---- 9. GEOLOCATION BY ZIP: grain = ONE row per ZIP prefix (average coordinates of valid points). Safe to join to customers/sellers. */
CREATE OR ALTER VIEW vw_clean_geolocation_zip AS
SELECT zip_prefix, AVG(lat) AS lat, AVG(lng) AS lng, COUNT(*) AS n_points, COUNT(DISTINCT city) AS n_city_spellings
FROM dbo.vw_clean_geolocation_points WHERE flag_outside_brazil = 0
GROUP BY zip_prefix

/*---- 10-12. AGGREGATES TO ORDER GRAIN*/
CREATE OR ALTER VIEW vw_agg_order_items AS
SELECT order_id, SUM(price) AS item_sales, SUM(freight_value) AS freight, COUNT(*) AS n_items,
       COUNT(DISTINCT seller_id) AS n_sellers, SUM(weight_g) AS total_weight_g
FROM vw_clean_order_items GROUP BY order_id

CREATE OR ALTER VIEW vw_agg_order_payments AS
WITH agg AS (SELECT order_id, SUM(payment_value) AS payment_total, COUNT(*) AS n_payment_rows, MAX(payment_installments) AS max_installments
             FROM vw_clean_order_payments GROUP BY order_id),
     main AS (SELECT order_id, payment_type AS main_payment_type FROM
              (SELECT order_id, payment_type, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC, payment_sequential) AS rn
               FROM vw_clean_order_payments) x WHERE rn = 1)
SELECT a.order_id, a.payment_total, a.n_payment_rows, a.max_installments, m.main_payment_type
FROM agg a JOIN main m ON m.order_id = a.order_id

CREATE OR ALTER VIEW dbo.vw_agg_order_reviews AS
SELECT order_id, AVG(CAST(review_score AS FLOAT)) AS review_score, COUNT(*) AS n_reviews
FROM vw_clean_order_reviews GROUP BY order_id

/*---- 13. ANALYTICS ORDERS: grain = ONE row per order. The main table for reporting. KPI rules: see file 03. */
CREATE OR ALTER VIEW vw_analytics_orders AS
SELECT o.order_id, o.customer_id, c.customer_unique_id, c.customer_state, c.customer_city, c.zip_prefix AS customer_zip_prefix,
       o.order_status, o.purchase_ts, CONVERT(CHAR(7), o.purchase_ts, 120) AS purchase_month, YEAR(o.purchase_ts) AS purchase_year,
       o.delivered_ts, o.estimated_ts, o.valid_delivery,
       CASE WHEN o.valid_delivery = 1 THEN DATEDIFF(SECOND, o.purchase_ts, o.delivered_ts) / 86400.0 END AS delivery_days,
       DATEDIFF(SECOND, o.purchase_ts, o.estimated_ts) / 86400.0 AS estimated_days,
       CASE WHEN o.valid_delivery = 1 THEN DATEDIFF(SECOND, o.estimated_ts, o.delivered_ts) / 86400.0 END AS delay_days,
       CASE WHEN o.valid_delivery = 1 THEN CASE WHEN o.delivered_ts > o.estimated_ts THEN 1 ELSE 0 END END AS is_late,
       ia.item_sales, ia.freight, ia.n_items, ia.n_sellers, fi.category AS first_item_category, fi.seller_state AS first_seller_state,
       pa.payment_total, pa.n_payment_rows, pa.max_installments, pa.main_payment_type,
       rv.review_score, rv.n_reviews,
       CASE WHEN ia.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_items,
       CASE WHEN pa.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_payment,
       CASE WHEN rv.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_review,
       CASE WHEN o.order_status NOT IN ('canceled', 'unavailable') AND ia.order_id IS NOT NULL THEN 1 ELSE 0 END AS is_sales_order,
       o.flag_carrier_before_purchase, o.flag_delivered_before_carrier, o.flag_approved_after_carrier,
       o.flag_estimated_before_purchase, o.flag_delivered_status_no_date, o.flag_not_delivered_has_date
FROM vw_clean_orders o
JOIN vw_clean_customers c ON c.customer_id = o.customer_id
LEFT JOIN vw_agg_order_items ia ON ia.order_id = o.order_id
LEFT JOIN vw_agg_order_payments pa ON pa.order_id = o.order_id
LEFT JOIN vw_agg_order_reviews rv ON rv.order_id = o.order_id
OUTER APPLY (SELECT TOP 1 x.category, x.seller_state FROM vw_clean_order_items x WHERE x.order_id = o.order_id ORDER BY x.order_item_id) fi


/*---- 14. ANALYTICS ORDER ITEMS: grain = one row per item. Use for category/seller analysis. WARNING: order-level fields
       (review_score, delivery) repeat on each item of an order - never SUM payment_total or other order amounts from this view. */
CREATE OR ALTER VIEW vw_analytics_order_items AS
SELECT i.order_id, i.order_item_id, i.product_id, i.seller_id, i.price, i.freight_value, i.category, i.seller_state,
       o.order_status, o.purchase_month, o.customer_unique_id, o.customer_state, o.valid_delivery, o.is_late, o.delay_days,
       o.review_score, o.is_sales_order
FROM vw_clean_order_items i
JOIN vw_analytics_orders o ON o.order_id = i.order_id

/*---- 15. ANALYTICS CUSTOMERS: grain = one row per REAL person (customer_unique_id) (I4). */
CREATE OR ALTER VIEW vw_analytics_customers AS
SELECT o.customer_unique_id, COUNT(DISTINCT o.order_id) AS n_orders,
       MIN(o.purchase_ts) AS first_purchase_ts, MAX(o.purchase_ts) AS last_purchase_ts,
       SUM(CASE WHEN o.is_sales_order = 1 THEN 1 ELSE 0 END) AS n_sales_orders,
       SUM(CASE WHEN o.is_sales_order = 1 THEN o.item_sales ELSE 0 END) AS item_sales,
       (SELECT TOP 1 z.customer_state FROM vw_analytics_orders z WHERE z.customer_unique_id = o.customer_unique_id 
       ORDER BY z.purchase_ts DESC) AS latest_customer_state
FROM vw_analytics_orders o
GROUP BY o.customer_unique_id

-- END OF FILE 2. Next: 03_Olist_SQL_EDA_and_KPIs.sql
