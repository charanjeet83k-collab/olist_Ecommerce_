/*==============================================================================
 FILE 4 of 4 - POST-CLEANING VALIDATION                  Database: olist_ECommerce
 Run after files 01-03. Every check returns PASS or CHECK (CHECK = compare and investigate).
 expected = a number computed in SQL from the SOURCE table, or the Python cross-check value.
 Nothing is changed; read-only. STATUS: written; NOT executed by the author - no result is claimed.
 UNRESOLVED BY DESIGN (documented, not "fixed"): review_id is not a key (814 repeated rows, flagged);
   249 orders where item value + freight differs from payments by more than 1 BRL; 768 orders without a review;
   approval after carrier pickup (1,358) and review before purchase (74) are flagged, kept and need a business decision.
==============================================================================*/
USE olist_ECommerce;
GO
-- V1 ROW COUNTS BEFORE (source) AND AFTER (cleaned views). Views must not lose or add rows.
-- Expected = source table count computed in SQL (not typed).
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'orders -> vw_clean_orders' AS check_name, CAST((SELECT COUNT(*) FROM dbo.orders) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders -> vw_analytics_orders' AS check_name, CAST((SELECT COUNT(*) FROM dbo.orders) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'Customer -> vw_clean_customers' AS check_name, CAST((SELECT COUNT(*) FROM dbo.Customer) AS DECIMAL(18,4)) AS expected,
CAST((SELECT COUNT(*) FROM dbo.vw_clean_customers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'order_items -> vw_clean_order_items' AS check_name, CAST((SELECT COUNT(*) FROM dbo.order_items) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'order_items -> vw_analytics_order_items' AS check_name, CAST((SELECT COUNT(*) FROM dbo.order_items) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_analytics_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'order_payments -> vw_clean_order_payments' AS check_name, CAST((SELECT COUNT(*) FROM dbo.order_payments) AS DECIMAL(18,4)) AS expected,
CAST((SELECT COUNT(*) FROM dbo.vw_clean_order_payments) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'order_reviews -> vw_clean_order_reviews' AS check_name, CAST((SELECT COUNT(*) FROM dbo.order_reviews) AS DECIMAL(18,4)) AS expected,
CAST((SELECT COUNT(*) FROM dbo.vw_clean_order_reviews) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'products -> vw_clean_products' AS check_name, CAST((SELECT COUNT(*) FROM dbo.products) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_products) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'sellers -> vw_clean_sellers' AS check_name, CAST((SELECT COUNT(*) FROM dbo.sellers) AS DECIMAL(18,4)) AS expected,
CAST((SELECT COUNT(*) FROM dbo.vw_clean_sellers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'geolocation -> vw_clean_geolocation_points' AS check_name, CAST((SELECT COUNT(*) FROM dbo.geolocation_) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_geolocation_points) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'distinct ZIPs (source) -> ZIP view (EXPECTED 19015 minus ZIPs with no valid point; Python: 19010)' AS check_name, 
CAST((SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM dbo.geolocation_) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) 
FROM dbo.vw_clean_geolocation_zip) AS DECIMAL(18,4)) AS actual, CAST(5 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'distinct customer_unique_id -> vw_analytics_customers' AS check_name, CAST((SELECT COUNT(DISTINCT customer_unique_id)
FROM dbo.Customer) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_customers) AS DECIMAL(18,4)) AS actual, 
CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V2 KEY UNIQUENESS AT THE GRAIN OF EACH VIEW (expected 0 repeated rows)
-- review_id is NOT expected to be unique: its 814 repeated rows are documented, flagged and handled by averaging per order.
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'vw_analytics_orders.order_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)-COUNT(DISTINCT order_id) FROM dbo.vw_analytics_orders)
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_customers.customer_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)-COUNT(DISTINCT customer_id) FROM 
dbo.vw_clean_customers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_order_items (order_id, order_item_id) repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT CONCAT(order_id,'|',order_item_id)) FROM dbo.vw_clean_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_order_payments (order_id, payment_sequential) repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected,
CAST((SELECT COUNT(*)-COUNT(DISTINCT CONCAT(order_id,'|',payment_sequential)) FROM dbo.vw_clean_order_payments) AS DECIMAL(18,4)) AS actual, 
CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_products.product_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT product_id) FROM dbo.vw_clean_products) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_sellers.seller_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT seller_id) FROM dbo.vw_clean_sellers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_agg_order_items.order_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT order_id) FROM dbo.vw_agg_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_agg_order_payments.order_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT order_id) FROM dbo.vw_agg_order_payments) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_agg_order_reviews.order_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT order_id) FROM dbo.vw_agg_order_reviews) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_clean_geolocation_zip.zip_prefix repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT zip_prefix) FROM dbo.vw_clean_geolocation_zip) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'vw_analytics_customers.customer_unique_id repeats' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*)
-COUNT(DISTINCT customer_unique_id) FROM dbo.vw_analytics_customers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'UNRESOLVED BY DESIGN: review_id extra rows in vw_clean_order_reviews (documented 814)' AS check_name, CAST((814) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*)-COUNT(DISTINCT review_id) FROM dbo.vw_clean_order_reviews) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V3 RELATIONSHIPS AND ORPHANS (counts before joins are understood)
-- Orders without items/payment/review are NOT errors by themselves; they are counted and explained.
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'orders without customer' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.orders o
WHERE NOT EXISTS (SELECT 1 FROM dbo.Customer c WHERE c.customer_id=o.customer_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'items without order' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.order_items i
WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.order_id=i.order_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'items without product' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.order_items i
WHERE NOT EXISTS (SELECT 1 FROM dbo.products p WHERE p.product_id=i.product_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'items without seller' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.order_items i
WHERE NOT EXISTS (SELECT 1 FROM dbo.sellers s WHERE s.seller_id=i.seller_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments without order' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.order_payments p 
WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.order_id=p.order_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'reviews without order' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.order_reviews r 
WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.order_id=r.order_id)) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders without items (explained: 603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped)' AS check_name, CAST((775)
AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders WHERE has_items=0) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders without payment' AS check_name, CAST((1) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders 
WHERE has_payment=0) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders without review (not an error)' AS check_name, CAST((768) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders
WHERE has_review=0) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders with payment but no items' AS check_name, CAST((775) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders
WHERE has_items=0 AND has_payment=1) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'customer rows without ZIP match in geolocation ZIP view' AS check_name, CAST((278) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) 
FROM dbo.vw_clean_customers c WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_clean_geolocation_zip z WHERE z.zip_prefix=c.zip_prefix)) AS DECIMAL(18,4)) AS actual, 
CAST(5 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'seller rows without ZIP match' AS check_name, CAST((7) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_clean_sellers s 
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_clean_geolocation_zip z WHERE z.zip_prefix=s.zip_prefix)) AS DECIMAL(18,4)) AS actual, CAST(5 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V4 NULL, BLANK AND FLAG COUNTS IN THE CLEANED VIEWS
-- Expected values come from the audit (Python cross-check). Flags mark rows; no row was removed.
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'products with missing category (labelled Unknown)' AS check_name, CAST((610) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_category_missing)
FROM dbo.vw_clean_products) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'products labelled category = Unknown' AS check_name, CAST((610) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_products WHERE category='Unknown') AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'products with untranslated category' AS check_name, CAST((13) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT SUM(flag_category_untranslated) FROM dbo.vw_clean_products) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'products with weight 0' AS check_name, CAST((4) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_weight_zero) 
FROM dbo.vw_clean_products) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'products with weight_g NULL after cleaning (2 NULL + 4 zero)' AS check_name, CAST((6) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_products WHERE weight_g IS NULL) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'items with freight 0' AS check_name, CAST((383) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_freight_zero) 
FROM dbo.vw_clean_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'items with price <= 0' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_price_not_positive) 
FROM dbo.vw_clean_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments with value 0' AS check_name, CAST((9) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_value_zero) 
FROM dbo.vw_clean_order_payments) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments with type not_defined' AS check_name, CAST((3) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_type_not_defined) 
FROM dbo.vw_clean_order_payments) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments with instalments below 1' AS check_name, CAST((2) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_installments_below_1) 
FROM dbo.vw_clean_order_payments) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'review titles NULL after blank cleaning (87656 NULL + 2 space-only)' AS check_name, CAST((87658) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_order_reviews WHERE review_comment_title IS NULL) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'review messages NULL after blank cleaning (58247 NULL + 27 space-only)' AS check_name, CAST((58274) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_clean_order_reviews WHERE review_comment_message IS NULL) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'reviews with score outside 1-5' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_score_invalid) 
FROM dbo.vw_clean_order_reviews) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'sellers with symbols in city' AS check_name, CAST((20) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_city_has_symbols) 
FROM dbo.vw_clean_sellers) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'geolocation points outside Brazil' AS check_name, CAST((42) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_outside_brazil) 
FROM dbo.vw_clean_geolocation_points) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V5 INVALID DATE SEQUENCES AND STATUS/DATE MISMATCHES (flagged, rows kept)
-- 
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'carrier pickup before purchase' AS check_name, CAST((161) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_carrier_before_purchase) 
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'delivered before carrier pickup' AS check_name, CAST((23) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_delivered_before_carrier) 
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'approved after carrier pickup' AS check_name, CAST((1358) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_approved_after_carrier) 
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'estimated before purchase' AS check_name, CAST((0) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_estimated_before_purchase)
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'status delivered without delivery date' AS check_name, CAST((8) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_delivered_status_no_date)
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'not delivered but has delivery date' AS check_name, CAST((6) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_not_delivered_has_date)
FROM dbo.vw_clean_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'shipping limit date after 2018' AS check_name, CAST((4) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_shipping_limit_after_2018)
FROM dbo.vw_clean_order_items) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'review created before purchase' AS check_name, CAST((74) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(flag_created_before_purchase) 
FROM dbo.vw_clean_order_reviews) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'valid deliveries' AS check_name, CAST((96447) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(valid_delivery) FROM dbo.vw_clean_orders) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V6 AGGREGATION AT THE CORRECT GRAIN (no multiplied rows)
-- 
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'orders with several reviews' AS check_name, CAST((547) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_agg_order_reviews WHERE n_reviews>1) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'reviewed orders (distinct)' AS check_name, CAST((98673) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_agg_order_reviews) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders with 2+ payment rows (information)' AS check_name, CAST((SELECT COUNT(*) FROM dbo.vw_agg_order_payments WHERE n_payment_rows>1)
AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_agg_order_payments WHERE n_payment_rows>1) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders with 2+ sellers' AS check_name, CAST((1278) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_agg_order_items WHERE n_sellers>1) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V7 UNEXPECTED EXCLUSIONS: which orders are outside the sales KPIs and why
-- Total orders 99441 = valid sales orders 98199 + 1242 excluded (canceled / unavailable / no items).
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'valid sales orders' AS check_name, CAST((98199) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(is_sales_order) FROM dbo.vw_analytics_orders) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'excluded from sales KPIs' AS check_name, CAST((1242) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) 
FROM dbo.vw_analytics_orders WHERE is_sales_order=0) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'valid + excluded = all orders' AS check_name, CAST((SELECT COUNT(*) FROM dbo.orders) AS DECIMAL(18,4)) 
AS expected, CAST((SELECT SUM(is_sales_order)+SUM(1-is_sales_order) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V8 PAYMENT AND ITEM-VALUE RECONCILIATION
-- Item value + freight vs payments. Small differences are rounding/vouchers; 249 orders differ by more than 1 BRL and are documented, not corrected.
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'item price: source = analytics view' AS check_name, CAST((SELECT SUM(price) FROM dbo.order_items) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT SUM(item_sales) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'freight: source = analytics view' AS check_name, CAST((SELECT SUM(freight_value) FROM dbo.order_items) AS DECIMAL(18,4))
AS expected, CAST((SELECT SUM(freight) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments: source = analytics view' AS check_name, CAST((SELECT SUM(payment_value) FROM dbo.order_payments) AS DECIMAL(18,4))
AS expected, CAST((SELECT SUM(payment_total) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments total (Python)' AS check_name, CAST((16008872.12) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(payment_value) 
FROM dbo.order_payments) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'valid orders: items + freight (Python)' AS check_name, CAST((15735527.03) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(item_sales+freight) 
FROM dbo.vw_analytics_orders WHERE is_sales_order=1) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'valid orders: payments (Python)' AS check_name, CAST((15738221.95) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(payment_total) 
FROM dbo.vw_analytics_orders WHERE is_sales_order=1) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'payments on the 1242 excluded orders (Python)' AS check_name, CAST((270650.17) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(payment_total) 
FROM dbo.vw_analytics_orders WHERE is_sales_order=0) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders compared (items and payments both exist)' AS check_name, CAST((98665) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) 
FROM dbo.vw_analytics_orders WHERE has_items=1 AND has_payment=1) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'orders where items+freight and payments differ by more than 1 BRL' AS check_name, CAST((249) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders WHERE has_items=1 AND has_payment=1 AND ABS(item_sales+freight-payment_total)>1) AS DECIMAL(18,4)) AS actual, 
CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V9 SOURCE vs CLEANED CONSISTENCY ON KEY MEASURES
-- 
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'distinct orders: source = analytics' AS check_name, CAST((SELECT COUNT(DISTINCT order_id) FROM dbo.orders) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(DISTINCT order_id) FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'sum of review scores averaged per order stays plausible (orders reviewed)' AS check_name, CAST((98673) AS DECIMAL(18,4)) AS expected, 
CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'unique customers = 96096' AS check_name, CAST((96096) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(DISTINCT customer_unique_id) 
FROM dbo.vw_analytics_orders) AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
) r;
GO

-- V10 KPI RECONCILIATION WITH THE PYTHON RESULTS (file 03 definitions)
-- Differences beyond the tolerance mean the SQL or the rule must be reviewed.
SELECT r.check_name, r.expected, r.actual,
       CASE WHEN ABS(r.actual - r.expected) <= r.tolerance THEN 'PASS' ELSE 'CHECK' END AS result
FROM (
SELECT 'orders (valid)' AS check_name, CAST((98199) AS DECIMAL(18,4)) AS expected, CAST((SELECT COUNT(*) FROM dbo.vw_analytics_orders WHERE is_sales_order=1) 
AS DECIMAL(18,4)) AS actual, CAST(0 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'item sales' AS check_name, CAST((13494400.74) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(item_sales) FROM dbo.vw_analytics_orders 
WHERE is_sales_order=1) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'freight' AS check_name, CAST((2241126.29) AS DECIMAL(18,4)) AS expected, CAST((SELECT SUM(freight) FROM dbo.vw_analytics_orders 
WHERE is_sales_order=1) AS DECIMAL(18,4)) AS actual, CAST(0.05 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'average item order value' AS check_name, CAST((137.42) AS DECIMAL(18,4)) AS expected, CAST((SELECT AVG(item_sales) 
FROM dbo.vw_analytics_orders WHERE is_sales_order=1) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'repeat customer rate %' AS check_name, CAST((3.12) AS DECIMAL(18,4)) AS expected, CAST((SELECT 100.0*SUM(CASE WHEN n_orders>1 THEN 1 ELSE 0 END)/COUNT(*) 
FROM dbo.vw_analytics_customers) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'average review score (order level)' AS check_name, CAST((4.09) AS DECIMAL(18,4)) AS expected, CAST((SELECT AVG(review_score) 
FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT '% orders score 4-5' AS check_name, CAST((77.05) AS DECIMAL(18,4)) AS expected, CAST((SELECT 100.0*AVG(CASE WHEN review_score>=4 THEN 1.0 ELSE 0 END)
FROM dbo.vw_analytics_orders WHERE review_score IS NOT NULL) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'average delivery days' AS check_name, CAST((12.56) AS DECIMAL(18,4)) AS expected, CAST((SELECT AVG(delivery_days) FROM dbo.vw_analytics_orders 
WHERE valid_delivery=1) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'late delivery %' AS check_name, CAST((8.11) AS DECIMAL(18,4)) AS expected, CAST((SELECT 100.0*AVG(CAST(is_late AS FLOAT)) FROM dbo.vw_analytics_orders 
WHERE valid_delivery=1) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
UNION ALL SELECT 'average delay of late orders (days)' AS check_name, CAST((9.55) AS DECIMAL(18,4)) AS expected, CAST((SELECT AVG(delay_days) FROM dbo.vw_analytics_orders
WHERE is_late=1) AS DECIMAL(18,4)) AS actual, CAST(0.01 AS DECIMAL(18,4)) AS tolerance
) r;
GO
-- END OF FILE 4.
