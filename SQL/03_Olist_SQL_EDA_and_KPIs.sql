/*==============================================================================
 FILE 3 of 4 - SQL EDA AND KPI CALCULATIONS               Database: olist_ECommerce
 Uses only the cleaned views from file 02. Read-only (SELECT). Run 02 first.
 STATUS: written; NOT executed by the author. "EXPECTED" = value from the same logic in Python
         on the CSV files; compare with your SSMS result. Relationships shown are ASSOCIATIONS, not proof of cause.

 KPI DEFINITIONS (grain | inclusion | limitation)
 Item sales        = SUM(price) from order items; freight NOT included          | item | status not canceled/unavailable | list price only, no discounts
 Freight           = SUM(freight_value)                                          | item | same as item sales             | 383 items have freight 0
 Order value (item)= item sales + freight per order                              | order | same                           | not the same as payment total
 Payment total     = SUM(payment_value) per order; includes freight and vouchers | order | ALL orders that have payments | includes canceled/unavailable orders
 Orders (valid)    = orders not canceled/unavailable that have at least one item | order
 Avg item order value = item sales / valid orders                                | order
 Unique customers  = DISTINCT customer_unique_id (customer_id is new every order)| person
 Repeat rate       = people with 2+ orders / all unique customers                | person | denominator = all people
 Late delivery %   = delivered timestamp > estimated timestamp / valid deliveries| order | valid_delivery = delivered, date present, not before purchase or carrier pickup
 Review score      = AVG(review_score) per order (reviews averaged first)        | order | only orders with a review (coverage below 100%)
 Canceled/unavailable orders are EXCLUDED from sales KPIs and INCLUDED in payment total and status counts.
==============================================================================*/
USE olist_ECommerce;
GO
/*================ A. SALES AND ORDER PERFORMANCE ===========================*/
-- A1 Orders by status. EXPECTED: delivered 96478, shipped 1107, canceled 625, unavailable 609, invoiced 314, processing 301, created 5, approved 2
SELECT order_status, COUNT(*) AS orders, 100.0*COUNT(*)/SUM(COUNT(*)) OVER () AS pct FROM dbo.vw_analytics_orders GROUP BY order_status ORDER BY orders DESC;
-- A2 Monthly orders, item sales, freight, average item order value (valid sales orders).
--    Read Jan 2017 - Aug 2018: the first and last months of the dataset are incomplete. EXPECTED peak: 2017-11 = 7421 orders, item sales 1003862.14
SELECT purchase_month, COUNT(*) AS orders, SUM(item_sales) AS item_sales, SUM(freight) AS freight, AVG(item_sales) AS avg_item_order_value
FROM dbo.vw_analytics_orders WHERE is_sales_order = 1 GROUP BY purchase_month ORDER BY purchase_month;
-- A3 Different money measures side by side (they are NOT interchangeable).
--    EXPECTED: item_sales 13494400.74 | freight 2241126.29 | item+freight 15735527.03 | payments (same orders) 15738221.95 | payments (all orders) 16008872.12
SELECT SUM(CASE WHEN is_sales_order=1 THEN item_sales END) AS item_sales_valid_orders, SUM(CASE WHEN is_sales_order=1 THEN freight END) AS freight_valid_orders,
       SUM(CASE WHEN is_sales_order=1 THEN item_sales + freight END) AS item_plus_freight_valid_orders,
       SUM(CASE WHEN is_sales_order=1 THEN payment_total END) AS payments_valid_orders, SUM(payment_total) AS payments_all_orders
FROM dbo.vw_analytics_orders;
-- A4 Payment method share by payment ROW (value of each payment part).
SELECT payment_type, COUNT(*) AS payment_rows, SUM(payment_value) AS payment_value,
       100.0*SUM(payment_value)/SUM(SUM(payment_value)) OVER () AS pct_value, AVG(CAST(payment_installments AS FLOAT)) AS avg_installments
FROM dbo.vw_clean_order_payments GROUP BY payment_type ORDER BY payment_value DESC;
-- A5 Payment method share by the order's MAIN payment type. EXPECTED: credit_card 78.3%, boleto 17.9%, voucher 2.4%, debit_card 1.4%
SELECT main_payment_type, COUNT(*) AS orders, SUM(payment_total) AS payment_total, 100.0*SUM(payment_total)/SUM(SUM(payment_total)) OVER () AS pct_value
FROM dbo.vw_analytics_orders WHERE main_payment_type IS NOT NULL GROUP BY main_payment_type ORDER BY payment_total DESC;
-- A6 Freight burden by top-10 sales categories (freight as % of item sales). Association only.
SELECT TOP 10 category, SUM(price) AS item_sales, SUM(freight_value) AS freight, 100.0*SUM(freight_value)/NULLIF(SUM(price),0) AS freight_pct_of_item_sales
FROM dbo.vw_analytics_order_items WHERE order_status NOT IN ('canceled','unavailable') GROUP BY category ORDER BY item_sales DESC;
GO
/*================ B. CUSTOMER ANALYSIS =====================================*/
-- B1 Customer records vs real people. EXPECTED: 99441 vs 96096
SELECT COUNT(DISTINCT customer_id) AS customer_records, COUNT(DISTINCT customer_unique_id) AS unique_customers FROM dbo.vw_analytics_orders;
-- B2 Orders per customer. EXPECTED: 1 order 93099 | 2 orders 2745 | 3 orders 203 | 4 orders 30 | 5 orders 8 | 6 orders 6 ...
SELECT n_orders, COUNT(*) AS customers FROM dbo.vw_analytics_customers GROUP BY n_orders ORDER BY n_orders;
-- B3 Repeat-customer rate (denominator = ALL unique customers). EXPECTED: 3.12%
SELECT 100.0*SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END)/COUNT(*) AS repeat_rate_pct, SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers, COUNT(*) AS customers
FROM dbo.vw_analytics_customers;
-- B4 New vs returning customers per month (a returning customer first bought in an earlier month).
WITH f AS (SELECT customer_unique_id, MIN(purchase_month) AS first_month FROM dbo.vw_analytics_orders GROUP BY customer_unique_id)
SELECT o.purchase_month, COUNT(DISTINCT o.customer_unique_id) AS customers,
       COUNT(DISTINCT CASE WHEN o.purchase_month > f.first_month THEN o.customer_unique_id END) AS returning_customers
FROM dbo.vw_analytics_orders o JOIN f ON f.customer_unique_id = o.customer_unique_id GROUP BY o.purchase_month ORDER BY o.purchase_month;
GO
/*================ C. PRODUCT, CATEGORY AND SELLER ANALYSIS ==================*/
-- C1 Top 10 categories by item sales (canceled/unavailable orders excluded). EXPECTED: top 5 = 39.8% of item sales, top 10 = 62.4%; 74 categories
SELECT TOP 10 category, SUM(price) AS item_sales, COUNT(*) AS items_sold, AVG(price) AS avg_price,
       100.0*SUM(price)/SUM(SUM(price)) OVER () AS pct_of_total_item_sales
FROM dbo.vw_analytics_order_items WHERE order_status NOT IN ('canceled','unavailable') GROUP BY category ORDER BY item_sales DESC;
-- C2 Monthly item sales of the top 5 categories (category trends).
WITH top5 AS (SELECT TOP 5 category FROM dbo.vw_analytics_order_items WHERE order_status NOT IN ('canceled','unavailable') GROUP BY category ORDER BY SUM(price) DESC)
SELECT i.purchase_month, i.category, SUM(i.price) AS item_sales FROM dbo.vw_analytics_order_items i JOIN top5 t ON t.category = i.category
WHERE i.order_status NOT IN ('canceled','unavailable') GROUP BY i.purchase_month, i.category ORDER BY i.purchase_month, i.category;
-- C3 Top 10 sellers by item sales. EXPECTED: active sellers 3053; top 10 sellers = 13.2% of item sales
SELECT TOP 10 seller_id, SUM(price) AS item_sales, COUNT(*) AS items, COUNT(DISTINCT order_id) AS orders, AVG(price) AS avg_price
FROM dbo.vw_analytics_order_items WHERE order_status NOT IN ('canceled','unavailable') GROUP BY seller_id ORDER BY item_sales DESC;
-- C4 Items per order and orders with items from several sellers. EXPECTED: 1278 orders with 2+ sellers
SELECT n_items, COUNT(*) AS orders FROM dbo.vw_analytics_orders WHERE has_items = 1 GROUP BY n_items ORDER BY n_items;
SELECT COUNT(*) AS orders_with_2plus_sellers FROM dbo.vw_analytics_orders WHERE n_sellers > 1;
GO
/*================ D. DELIVERY ANALYSIS ======================================*/
-- D1 Delivery summary (valid deliveries). EXPECTED: 96447 orders | avg delivery 12.56 days | avg estimated 23.74 | late 8.11% | avg delay of late orders 9.55 days
SELECT COUNT(*) AS valid_delivered_orders, AVG(delivery_days) AS avg_delivery_days, AVG(estimated_days) AS avg_estimated_days,
       100.0*AVG(CAST(is_late AS FLOAT)) AS late_pct, AVG(CASE WHEN is_late = 1 THEN delay_days END) AS avg_delay_days_when_late
FROM dbo.vw_analytics_orders WHERE valid_delivery = 1;
-- D2 Missing or inconsistent delivery information. EXPECTED: delivered no date 8 | not delivered but has date 6 | carrier<purchase 161 | delivered<carrier 23 | approved>carrier 1358
SELECT SUM(flag_delivered_status_no_date) AS delivered_status_no_date, SUM(flag_not_delivered_has_date) AS not_delivered_has_date,
       SUM(flag_carrier_before_purchase) AS carrier_before_purchase, SUM(flag_delivered_before_carrier) AS delivered_before_carrier,
       SUM(flag_approved_after_carrier) AS approved_after_carrier
FROM dbo.vw_analytics_orders;
-- D3 Delivery by customer state. EXPECTED: SP about 8.8 days (fastest); AM, AP, RR about 26-29 days but with few orders (145, 67, 41)
SELECT customer_state, COUNT(*) AS orders, AVG(delivery_days) AS avg_delivery_days, 100.0*AVG(CAST(is_late AS FLOAT)) AS late_pct
FROM dbo.vw_analytics_orders WHERE valid_delivery = 1 GROUP BY customer_state ORDER BY avg_delivery_days;
-- D4 Late % by purchase month.
SELECT purchase_month, COUNT(*) AS orders, AVG(delivery_days) AS avg_delivery_days, AVG(estimated_days) AS avg_estimated_days, 100.0*AVG(CAST(is_late AS FLOAT)) AS late_pct
FROM dbo.vw_analytics_orders WHERE valid_delivery = 1 GROUP BY purchase_month ORDER BY purchase_month;
-- D5 Sellers with the highest late share (at least 50 delivered items, to avoid tiny samples). Valid deliveries only.
SELECT TOP 10 seller_id, COUNT(*) AS delivered_items, 100.0*AVG(CAST(is_late AS FLOAT)) AS late_pct, AVG(review_score) AS avg_review_score
FROM dbo.vw_analytics_order_items WHERE valid_delivery = 1 GROUP BY seller_id HAVING COUNT(*) >= 50 ORDER BY late_pct DESC;
-- D6 Categories with the highest late share (at least 200 delivered items).
SELECT TOP 10 category, COUNT(*) AS delivered_items, 100.0*AVG(CAST(is_late AS FLOAT)) AS late_pct
FROM dbo.vw_analytics_order_items WHERE valid_delivery = 1 GROUP BY category HAVING COUNT(*) >= 200 ORDER BY late_pct DESC;
GO
/*================ E. REVIEW ANALYSIS ========================================*/
-- E1 Review summary (order level). EXPECTED: avg 4.09 | 4-5 stars 77.05% | 1-2 stars 14.64% | coverage 99.23% of orders
SELECT AVG(review_score) AS avg_review_score,
       100.0*AVG(CASE WHEN review_score >= 4 THEN 1.0 ELSE 0 END) AS pct_4_5,
       100.0*AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END) AS pct_1_2,
       (SELECT 100.0*SUM(has_review)/COUNT(*) FROM dbo.vw_analytics_orders) AS coverage_pct
FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL;
-- E2 Score distribution (order-level score rounded). EXPECTED: 1: 11316 | 2: 3167 | 3: 8137 | 4: 19098 | 5: 56955
SELECT CAST(ROUND(review_score, 0) AS INT) AS score, COUNT(*) AS orders FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL 
GROUP BY CAST(ROUND(review_score, 0) AS INT) ORDER BY score;
-- E3 Average score by delivery delay (valid deliveries with a review). An ASSOCIATION, not proof of cause.
--    EXPECTED: on time or early 4.29 (88140) | 1-3 days late 3.77 (2636) | 4-7 late 2.32 (1773) | over 7 late 1.73 (3252)
SELECT CASE WHEN delay_days <= 0 THEN '1 on time or early' WHEN delay_days <= 3 THEN '2 1-3 days late' WHEN delay_days <= 7 THEN 
'3 4-7 days late' ELSE '4 over 7 days late' END AS delay_bucket,
       COUNT(*) AS orders, AVG(review_score) AS avg_score
FROM dbo.vw_analytics_orders WHERE valid_delivery = 1 AND review_score IS NOT NULL
GROUP BY CASE WHEN delay_days <= 0 THEN '1 on time or early' WHEN delay_days <= 3 THEN '2 1-3 days late' WHEN
delay_days <= 7 THEN '3 4-7 days late' ELSE '4 over 7 days late' END ORDER BY delay_bucket;
-- E4 Late vs not late: average score and share of 1-2 star orders.
SELECT is_late, COUNT(*) AS orders, AVG(review_score) AS avg_score, 100.0*AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END) AS pct_1_2
FROM dbo.vw_analytics_orders WHERE valid_delivery = 1 AND review_score IS NOT NULL GROUP BY is_late;
GO
/*================ F. GEOGRAPHIC ANALYSIS ====================================*/
-- F1 Orders and item sales by customer state. EXPECTED: SP 41.9% of valid orders; SP+RJ+MG 66.5%
SELECT customer_state, COUNT(*) AS orders, SUM(item_sales) AS item_sales, 100.0*COUNT(*)/SUM(COUNT(*)) OVER () AS pct_orders
FROM dbo.vw_analytics_orders WHERE is_sales_order = 1 GROUP BY customer_state ORDER BY orders DESC;
-- F2 Top 10 customer cities by valid orders.
SELECT TOP 10 customer_city, customer_state, COUNT(*) AS orders FROM dbo.vw_analytics_orders WHERE is_sales_order = 1 GROUP BY 
customer_city, customer_state ORDER BY orders DESC;
-- F3 ZIP and coordinate validity. EXPECTED: customer rows without a ZIP match 278; seller rows 7; points outside Brazil 42; ZIP rows in the ZIP view 19010
SELECT (SELECT COUNT(*) FROM dbo.vw_clean_customers c WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_clean_geolocation_zip z WHERE 
z.zip_prefix = c.zip_prefix)) AS customer_rows_without_valid_zip,
       (SELECT COUNT(*) FROM dbo.vw_clean_sellers s WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_clean_geolocation_zip z WHERE z.zip_prefix = s.zip_prefix)) 
       AS seller_rows_without_valid_zip,
       (SELECT SUM(flag_outside_brazil) FROM dbo.vw_clean_geolocation_points) AS points_outside_brazil,
       (SELECT COUNT(*) FROM dbo.vw_clean_geolocation_zip) AS zip_rows_in_view;
GO
/*================ G. HEADLINE KPI SHEET (one row) ============================*/
WITH sales AS (SELECT * FROM dbo.vw_analytics_orders WHERE is_sales_order = 1),
     sl AS (SELECT seller_id, SUM(price) AS s FROM dbo.vw_analytics_order_items WHERE order_status NOT IN ('canceled','unavailable') GROUP BY seller_id),
     slr AS (SELECT s, ROW_NUMBER() OVER (ORDER BY s DESC) AS rn FROM sl)
SELECT (SELECT COUNT(*) FROM sales)                              AS orders_valid,              -- 98199
       (SELECT SUM(item_sales) FROM sales)                       AS item_sales_brl,            -- 13494400.74
       (SELECT SUM(freight) FROM sales)                          AS freight_brl,               -- 2241126.29
       (SELECT AVG(item_sales) FROM sales)                       AS avg_item_order_value,      -- 137.42
       (SELECT SUM(payment_total) FROM dbo.vw_analytics_orders)  AS payment_total_brl,         -- 16008872.12
       (SELECT COUNT(*) FROM dbo.vw_analytics_customers)         AS unique_customers,          -- 96096
       (SELECT 100.0*SUM(CASE WHEN n_orders>1 THEN 1 ELSE 0 END)/COUNT(*) FROM dbo.vw_analytics_customers) AS repeat_rate_pct,  -- 3.12
       (SELECT COUNT(*) FROM sl)                                 AS active_sellers,            -- 3053
       (SELECT 100.0*SUM(CASE WHEN rn<=10 THEN s END)/SUM(s) FROM slr) AS top10_seller_share_pct, -- 13.2
       (SELECT AVG(review_score) FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS avg_review_score,  -- 4.09
       (SELECT 100.0*AVG(CASE WHEN review_score>=4 THEN 1.0 ELSE 0 END) FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS pct_4_5,  -- 77.05
       (SELECT 100.0*AVG(CASE WHEN review_score<=2 THEN 1.0 ELSE 0 END) FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS pct_1_2,  -- 14.64
       (SELECT COUNT(*) FROM dbo.vw_analytics_orders WHERE valid_delivery=1) AS valid_delivered_orders,  -- 96447
       (SELECT AVG(delivery_days) FROM dbo.vw_analytics_orders WHERE valid_delivery=1) AS avg_delivery_days,  -- 12.56
       (SELECT 100.0*AVG(CAST(is_late AS FLOAT)) FROM dbo.vw_analytics_orders WHERE valid_delivery=1) AS late_pct,  -- 8.11
       (SELECT AVG(delay_days) FROM dbo.vw_analytics_orders WHERE is_late=1) AS avg_delay_days_late;  -- 9.55
GO
-- END OF FILE 3. Next: 04_Olist_Post_Cleaning_Validation.sql
