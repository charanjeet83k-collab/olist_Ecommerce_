/*==============================================================================
 PROJECT      : Brazilian E-Commerce (Olist) Sales & Customer Insights Analysis
 DELIVERABLE  : First Deliverable - SQL Data Audit
 DATABASE     : Microsoft SQL Server (SSMS)
 PURPOSE      : Check data quality & consistency BEFORE any cleaning.
                Every query is SELECT-only. Nothing is updated or deleted.

 ASSUMED TABLE NAMES
   dbo.Customer                        
   dbo.geolocation                     
   dbo.order_items                 
   dbo.order_payments                 
   dbo.order_reviews                   
   dbo.orders                          
   dbo.product_category_name_translation 
   dbo.products                        
   dbo.sellers                         

 SECTIONS
   1 Database & table overview        6 Date / time consistency
   2 Missing (NULL) values            7 Categorical & text consistency
   3 Duplicates & primary keys        8 Business-rule validation
   4 Relationships & orphan records   9 Geolocation checks
   5 Data types & invalid values     
==============================================================================*/

Create DataBase olist_ECommerce

use olist_ECommerce

select table_name from INFORMATION_SCHEMA.TABLES

/*==============================================================================
 SECTION 1 : DATABASE & TABLE OVERVIEW
==============================================================================*/

-- 1.1 ROW COUNT OF EVERY TABLE

SELECT 'Customer' AS table_name,COUNT(*) AS total_rows FROM Customer
UNION ALL
SELECT 'geolocation',COUNT(*) FROM geolocation
UNION ALL 
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments',COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews',COUNT(*) FROM order_reviews
UNION ALL
SELECT 'orders',COUNT(*) FROM orders
UNION ALL
SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
UNION ALL 
SELECT 'products',COUNT(*) FROM products
UNION ALL 
SELECT 'sellers',COUNT(*) FROM sellers

-- 1.2 COLUMN LIST AND DATA TYPES OF EVERY TABLE

SELECT TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
ORDER BY TABLE_NAME, ORDINAL_POSITION

-- 1.3 NUMBER OF COLUMNS PER TABLE

SELECT TABLE_NAME, COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME

-- 1.4 ORDER STATUS DISTRIBUTION (understanding the main table)

SELECT order_status, COUNT(*) AS order_count
FROM dbo.orders
GROUP BY order_status
ORDER BY order_count DESC

/*==============================================================================
 SECTION 2 : MISSING (NULL) VALUES
==============================================================================*/

-- 2.1 NULLS IN orders

SELECT COUNT(*) AS total_rows,
       COUNT(*) - COUNT(order_id) AS null_order_id,
       COUNT(*) - COUNT(customer_id)AS null_customer_id,
       COUNT(*) - COUNT(order_status) AS null_order_status,
       COUNT(*) - COUNT(order_purchase_timestamp)AS null_purchase_ts,
       COUNT(*) - COUNT(order_approved_at)AS null_approved_at,
       COUNT(*) - COUNT(order_delivered_carrier_date) AS null_delivered_carrier,
       COUNT(*) - COUNT(order_delivered_customer_date)AS null_delivered_customer,
       COUNT(*) - COUNT(order_estimated_delivery_date)AS null_estimated_delivery
FROM orders

-- 2.2 NULLS IN order_reviews

SELECT COUNT(*) AS total_rows,
       COUNT(*) - COUNT(review_id)AS null_review_id,
       COUNT(*) - COUNT(order_id)AS null_order_id,
       COUNT(*) - COUNT(review_score)AS null_review_score,
       COUNT(*) - COUNT(review_comment_title)AS null_comment_title,
       COUNT(*) - COUNT(review_comment_message)AS null_comment_message,
       COUNT(*) - COUNT(review_creation_date)AS null_creation_date,
       COUNT(*) - COUNT(review_answer_timestamp)AS null_answer_timestamp
FROM order_reviews

-- 2.3 NULLS IN products

SELECT COUNT(*) AS total_rows,
       COUNT(*) - COUNT(product_id)AS null_product_id,
       COUNT(*) - COUNT(product_category_name)AS null_category,
       COUNT(*) - COUNT(product_name_lenght)AS null_name_length,
       COUNT(*) - COUNT(product_description_lenght) AS null_description_length,
       COUNT(*) - COUNT(product_photos_qty)AS null_photos_qty,
       COUNT(*) - COUNT(product_weight_g)AS null_weight,
       COUNT(*) - COUNT(product_length_cm)AS null_length,
       COUNT(*) - COUNT(product_height_cm)AS null_height,
       COUNT(*) - COUNT(product_width_cm) AS null_width
FROM products

-- 2.4 NULLS IN order_items

SELECT 'order_items' AS table_name,
       COUNT(*)-COUNT(order_id)as null_order_id, 
       COUNT(*)-COUNT(order_item_id) as null_order_item_id,
       COUNT(*)-COUNT(product_id) as null_product_id,
       COUNT(*)-COUNT(seller_id)as null_seller_id , 
       COUNT(*)-COUNT(shipping_limit_date)as null_shipping_limit_date,
       COUNT(*)-COUNT(price) as null_price,
       COUNT(*)-COUNT(freight_value)as null_freight_value
FROM order_items

-- 2.5 Null check in order_payments

SELECT 'order_payments'AS table_name,
       COUNT(*)-COUNT(order_id)as null_order_id, 
       COUNT(*)-COUNT(payment_sequential) as null_payment_sequential,
       count(*)-count(payment_type)as null_payment_type,
       COUNT(*)-COUNT(payment_installments) as null_product_installment,
       COUNT(*)-COUNT(payment_value)as null_payment_value
from order_payments

-- 2.6 Null check in customer

SELECT 'Customer',
     COUNT(*)-COUNT(customer_id)as null_cust_id,
     COUNT(*)-COUNT(customer_unique_id)as null_cust_unique_id,
     COUNT(*)-COUNT(customer_zip_code_prefix)as null_zip_code,
     COUNT(*)-COUNT(customer_city)as null_cust_city,
     COUNT(*)-COUNT(customer_state)as null_cust_state
FROM Customer

--2.7 null check in sellers

SELECT 'sellers',
       COUNT(*)-COUNT(seller_id)as null_seller_id,
       COUNT(*)-COUNT(seller_zip_code_prefix)as null_seller_zip_code,
     COUNT(*)-COUNT(seller_city)as null_seller_city,
     COUNT(*)-COUNT(seller_state)as null_seller_state
FROM sellers

-- 2.8 Null Check in Product_category_name_translation

SELECT 'product_category_name_translation',
       COUNT(*)-COUNT(product_category_name)as null_product_category_name,
       COUNT(*)-COUNT(product_category_name_english)as null_product_category_name_english
FROM product_category_name_translation

-- 2.9 Null check in Geolocation

SELECT 'geolocation',
       COUNT(*)-COUNT(geolocation_zip_code_prefix)as null_geolocation_zip_code_prefix,
       COUNT(*)-COUNT(geolocation_lat)as null_geolocation_lat,
      COUNT(*)-COUNT(geolocation_lng)as null_geolocation_lng,
      COUNT(*)-COUNT(geolocation_city)as null_geolocation_city,
      COUNT(*)-COUNT(geolocation_state)as null_geolocation_state
FROM dbo.geolocation

-- 2.5 BLANK TEXT (empty or space-only values) IN EVERY TEXT COLUMN

SELECT table_name, column_checked, blank_rows
FROM (
SELECT 'Customer' AS table_name, 'customer_id' AS column_checked, COUNT(*) AS blank_rows 
FROM Customer WHERE LTRIM(RTRIM(customer_id)) = ''
UNION ALL SELECT 'Customer', 'customer_unique_id', COUNT(*) 
FROM Customer WHERE LTRIM(RTRIM(customer_unique_id)) = ''
UNION ALL SELECT 'Customer', 'customer_city', COUNT(*) 
FROM Customer WHERE LTRIM(RTRIM(customer_city)) = ''
UNION ALL SELECT 'Customer', 'customer_state', COUNT(*) 
FROM Customer WHERE LTRIM(RTRIM(customer_state)) = ''
UNION ALL SELECT 'geolocation', 'geolocation_city', COUNT(*) 
FROM geolocation WHERE LTRIM(RTRIM(geolocation_city)) = ''
UNION ALL SELECT 'geolocation', 'geolocation_state', COUNT(*) 
FROM geolocation WHERE LTRIM(RTRIM(geolocation_state)) = ''
UNION ALL SELECT 'order_items', 'order_id', COUNT(*) 
FROM order_items WHERE LTRIM(RTRIM(order_id)) = ''
UNION ALL SELECT 'order_items', 'product_id', COUNT(*)
FROM order_items WHERE LTRIM(RTRIM(product_id)) = ''
UNION ALL SELECT 'order_items', 'seller_id', COUNT(*) 
FROM order_items WHERE LTRIM(RTRIM(seller_id)) = ''
UNION ALL SELECT 'order_payments', 'payment_type', COUNT(*) 
FROM order_payments WHERE LTRIM(RTRIM(payment_type)) = ''
UNION ALL SELECT 'order_reviews', 'review_id', COUNT(*) 
FROM order_reviews WHERE LTRIM(RTRIM(review_id)) = ''
UNION ALL SELECT 'order_reviews', 'review_comment_title', COUNT(*) 
FROM order_reviews WHERE LTRIM(RTRIM(review_comment_title)) = ''
UNION ALL SELECT 'order_reviews', 'review_comment_message', COUNT(*) 
FROM order_reviews WHERE LTRIM(RTRIM(review_comment_message)) = ''
UNION ALL SELECT 'orders', 'order_id', COUNT(*) FROM orders
WHERE LTRIM(RTRIM(order_id)) = ''
UNION ALL SELECT 'orders', 'order_status', COUNT(*)
FROM orders WHERE LTRIM(RTRIM(order_status)) = ''
UNION ALL SELECT 'product_category_name_translation', 'product_category_name', COUNT(*)
FROM product_category_name_translation WHERE LTRIM(RTRIM(product_category_name)) = ''
UNION ALL SELECT 'product_category_name_translation', 'product_category_name_english', COUNT(*)
FROM product_category_name_translation WHERE LTRIM(RTRIM(product_category_name_english)) = ''
UNION ALL SELECT 'products', 'product_id', COUNT(*) 
FROM products WHERE LTRIM(RTRIM(product_id)) = ''
UNION ALL SELECT 'products', 'product_category_name', COUNT(*) 
FROM products WHERE LTRIM(RTRIM(product_category_name)) = ''
UNION ALL SELECT 'sellers', 'seller_id', COUNT(*)
FROM sellers WHERE LTRIM(RTRIM(seller_id)) = ''
UNION ALL SELECT 'sellers', 'seller_city', COUNT(*) 
FROM sellers WHERE LTRIM(RTRIM(seller_city)) = ''
UNION ALL SELECT 'sellers', 'seller_state', COUNT(*) 
FROM sellers WHERE LTRIM(RTRIM(seller_state)) = ''
) x
WHERE blank_rows > 0
ORDER BY table_name, column_checked

/*==============================================================================
 SECTION 3 : DUPLICATES & PRIMARY-KEY UNIQUENESS
==============================================================================*/

-- 3.1 orders.order_id UNIQUE?

SELECT order_id, COUNT(*) AS times_repeated
FROM orders GROUP BY order_id HAVING COUNT(*) > 1

-- 3.2 Customer.customer_id UNIQUE?

SELECT customer_id, COUNT(*) AS times_repeated
FROM Customer GROUP BY customer_id HAVING COUNT(*) > 1

-- 3.3 customer_id vs customer_unique_id (REAL CUSTOMER COUNT)

SELECT COUNT(DISTINCT customer_id)AS distinct_customer_id,
       COUNT(DISTINCT customer_unique_id)AS distinct_customer_unique_id
FROM Customer

SELECT COUNT(*) AS people_with_multiple_customer_ids
FROM (SELECT customer_unique_id FROM Customer
      GROUP BY customer_unique_id HAVING COUNT(*) > 1) x


-- 3.4 order_items composite key (order_id + order_item_id) UNIQUE?

SELECT order_id, order_item_id, COUNT(*) AS times_repeated
FROM order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1

-- 3.5 order_payments composite key (order_id + payment_sequential) UNIQUE?

SELECT order_id, payment_sequential, COUNT(*) AS times_repeated
FROM order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1

-- 3.6 order_reviews.review_id UNIQUE?

SELECT SUM(c - 1) AS extra_rows_with_repeated_review_id
FROM (SELECT review_id, COUNT(*) AS c FROM order_reviews
      GROUP BY review_id HAVING COUNT(*) > 1) x

-- 3.7 ORDERS WITH MORE THAN ONE REVIEW

SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM dbo.order_reviews
      GROUP BY order_id HAVING COUNT(*) > 1) x

-- 3.8 products.product_id, sellers.seller_id, translation category UNIQUE?

SELECT 'products.product_id' AS key_checked, COUNT(*) - COUNT(DISTINCT product_id) AS repeated_rows FROM dbo.products
UNION ALL SELECT 'sellers.seller_id', COUNT(*) - COUNT(DISTINCT seller_id) FROM dbo.sellers
UNION ALL SELECT 'translation.product_category_name', COUNT(*) - COUNT(DISTINCT product_category_name)
FROM dbo.product_category_name_translation

-- 3.9 FULL-ROW DUPLICATES IN geolocation

SELECT SUM(c - 1) AS extra_duplicate_rows
FROM (SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
             geolocation_city, geolocation_state, COUNT(*) AS c
      FROM dbo.geolocation
      GROUP BY geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
               geolocation_city, geolocation_state
      HAVING COUNT(*) > 1) x

-- 3.10 IS geolocation_zip_code_prefix A PRIMARY KEY?

SELECT COUNT(*) AS distinct_zip_prefixes,
       SUM(CASE WHEN c > 1 THEN 1 ELSE 0 END) AS zips_with_more_than_one_row
FROM (SELECT geolocation_zip_code_prefix, COUNT(*) AS c
      FROM geolocation GROUP BY geolocation_zip_code_prefix) x

/*==============================================================================
 SECTION 4 : RELATIONSHIPS & ORPHAN RECORDS (referential integrity)
==============================================================================*/

-- 4.1 orders -> Customer
-- CHECK  : orders whose customer_id is missing from Customer.

SELECT COUNT(*) AS orders_without_customer
FROM orders o LEFT JOIN Customer c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL

-- 4.2 Customer rows with no order
-- CHECK  : customers that never appear in orders.

SELECT COUNT(*) AS customers_without_orders
FROM Customer c LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL

-- 4.3 order_items -> orders (child with no parent)
-- CHECK  : item rows whose order_id is not in orders.

SELECT COUNT(*) AS items_without_order
FROM order_items oi LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL

-- 4.4 orders with NO items, split by status
-- CHECK  : orders that have no row in order_items.

SELECT o.order_status, COUNT(*) AS orders_without_items
FROM orders o LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status ORDER BY orders_without_items DESC

-- 4.5 order_items -> products and sellers
-- CHECK  : item rows pointing to a product_id or seller_id that does not exist.

SELECT
  (SELECT COUNT(*) FROM order_items oi LEFT JOIN products p ON oi.product_id = p.product_id
   WHERE p.product_id IS NULL) AS items_without_product,
  (SELECT COUNT(*) FROM order_items oi LEFT JOIN sellers s ON oi.seller_id = s.seller_id
   WHERE s.seller_id IS NULL)  AS items_without_seller

-- 4.6 order_payments -> orders, and orders with NO payment
-- CHECK  : (a) payments with no order, (b) orders with no payment row.

SELECT
  (SELECT COUNT(*) FROM order_payments p LEFT JOIN orders o ON p.order_id = o.order_id
   WHERE o.order_id IS NULL) AS payments_without_order,
  (SELECT COUNT(*) FROM orders o LEFT JOIN order_payments p ON o.order_id = p.order_id
   WHERE p.order_id IS NULL) AS orders_without_payment

-- 4.7 order_reviews -> orders, and orders with NO review
-- CHECK  : (a) reviews with no order, (b) orders never reviewed.

SELECT
  (SELECT COUNT(*) FROM order_reviews r LEFT JOIN orders o ON r.order_id = o.order_id
   WHERE o.order_id IS NULL) AS reviews_without_order,
  (SELECT COUNT(*) FROM orders o LEFT JOIN order_reviews r ON o.order_id = r.order_id
   WHERE r.order_id IS NULL) AS orders_without_review;

-- 4.8 products -> category translation
-- CHECK  : (a) products whose category has no English translation (ignoring NULL category),
--          (b) which categories are missing.

SELECT p.product_category_name, COUNT(*) AS products_affected
FROM products p
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
GROUP BY p.product_category_name

-- 4.9 Unused rows in lookup tables
-- CHECK  : products never sold, sellers with no items, translations not used by any product.

SELECT
  (SELECT COUNT(*) FROM products p LEFT JOIN order_items oi ON p.product_id = oi.product_id
   WHERE oi.product_id IS NULL) AS products_never_sold,
  (SELECT COUNT(*) FROM sellers s LEFT JOIN order_items oi ON s.seller_id = oi.seller_id
   WHERE oi.seller_id IS NULL)  AS sellers_with_no_items,
  (SELECT COUNT(*) FROM product_category_name_translation t
   LEFT JOIN products p ON t.product_category_name = p.product_category_name
   WHERE p.product_id IS NULL)  AS translations_not_used

-- 4.10 Zip prefix links (INFERRED relationship, not a declared key)
-- CHECK  : customer / seller zip prefixes that do not exist in geolocation.

SELECT
  (SELECT COUNT(*) FROM Customer c
   WHERE NOT EXISTS (SELECT 1 FROM dbo.geolocation g WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix))AS customer_rows_without_geo,
  (SELECT COUNT(*) FROM sellers s
   WHERE NOT EXISTS (SELECT 1 FROM dbo.geolocation g WHERE g.geolocation_zip_code_prefix = s.seller_zip_code_prefix))AS seller_rows_without_geo

/*==============================================================================
 SECTION 5 : DATA TYPES & INVALID VALUES
==============================================================================*/

-- 5.1 TEXT DATES THAT CANNOT BE CONVERTED
-- CHECK  : non-NULL date values that TRY_CAST cannot turn into a date.

SELECT
 (SELECT COUNT(*) FROM orders WHERE order_purchase_timestamp IS NOT NULL AND 
 TRY_CAST(order_purchase_timestamp AS DATETIME2) IS NULL) AS bad_purchase_ts,
 (SELECT COUNT(*) FROM orders WHERE order_approved_at IS NOT NULL AND 
 TRY_CAST(order_approved_at AS DATETIME2) IS NULL) AS bad_approved_at,
 (SELECT COUNT(*) FROM orders WHERE order_delivered_carrier_date IS NOT NULL AND
 TRY_CAST(order_delivered_carrier_date AS DATETIME2) IS NULL) AS bad_carrier_date,
 (SELECT COUNT(*) FROM orders WHERE order_delivered_customer_date IS NOT NULL AND 
 TRY_CAST(order_delivered_customer_date AS DATETIME2) IS NULL) AS bad_customer_date,
 (SELECT COUNT(*) FROM orders WHERE order_estimated_delivery_date IS NOT NULL AND 
 TRY_CAST(order_estimated_delivery_date AS DATETIME2) IS NULL) AS bad_estimated_date,
 (SELECT COUNT(*) FROM order_items WHERE TRY_CAST(shipping_limit_date AS DATETIME2) IS NULL) AS bad_shipping_limit,
 (SELECT COUNT(*) FROM order_reviews WHERE TRY_CAST(review_creation_date AS DATETIME2) IS NULL
                                              OR TRY_CAST(review_answer_timestamp AS DATETIME2) IS NULL) AS bad_review_dates

-- 5.2 PRICE AND FREIGHT RANGE (order_items)
-- CHECK  : min / max / average of price and freight_value; zero or negative values.

SELECT MIN(price) AS min_price, MAX(price) AS max_price, AVG(price) AS avg_price,
       MIN(freight_value) AS min_freight, MAX(freight_value) AS max_freight,
       SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END) AS price_zero_or_negative,
       SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS freight_negative,
       SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END) AS freight_zero
FROM order_items

-- 5.3 PAYMENT VALUES, INSTALMENTS AND TYPES
-- CHECK  : zero / negative payment values, instalments below 1, and the payment_type list.

SELECT SUM(CASE WHEN payment_value = 0 THEN 1 ELSE 0 END) AS payment_value_zero,
       SUM(CASE WHEN payment_value < 0 THEN 1 ELSE 0 END) AS payment_value_negative,
       SUM(CASE WHEN payment_installments < 1 THEN 1 ELSE 0 END) AS installments_below_1,
       SUM(CASE WHEN payment_type = 'not_defined' THEN 1 ELSE 0 END) AS payment_type_not_defined
FROM order_payments

SELECT payment_type, COUNT(*) AS payment_rows, SUM(payment_value) AS total_value
FROM order_payments GROUP BY payment_type ORDER BY payment_rows DESC

-- 5.5 REVIEW SCORE RANGE
-- CHECK  : review_score values outside 1-5 and the count per score.

SELECT review_score, COUNT(*) AS review_count
FROM order_reviews GROUP BY review_score ORDER BY review_score

-- 5.6 PRODUCT WEIGHT AND SIZE
-- CHECK  : zero or negative weight / dimensions, and the maximum weight.

SELECT SUM(CASE WHEN product_weight_g <= 0 THEN 1 ELSE 0 END) AS weight_zero_or_negative,
       SUM(CASE WHEN product_length_cm <= 0 OR product_height_cm <= 0 OR product_width_cm <= 0 THEN 1 ELSE 0 END) AS dimension_zero_or_negative,
       MAX(product_weight_g) AS max_weight_g
FROM products

-- 5.7 REVIEW TEXT LENGTH vs COLUMN SIZE (metadata match)
-- CHECK  : longest review message and how many exceed 50 characters.

SELECT MAX(LEN(review_comment_message)) AS longest_message,
       SUM(CASE WHEN LEN(review_comment_message) > 50 THEN 1 ELSE 0 END) AS messages_over_50_chars
FROM order_reviews

-- 5.8 ZIP PREFIX STORED AS NUMBER
-- CHECK  : zip prefixes below 10000 (they should have 5 digits, a leading zero may be lost).

SELECT (SELECT COUNT(*) FROM Customer    WHERE customer_zip_code_prefix < 10000)    AS customer_zip_below_10000,
       (SELECT COUNT(*) FROM geolocation WHERE geolocation_zip_code_prefix < 10000) AS geo_zip_below_10000

/*==============================================================================
 SECTION 6 : DATE / TIME CONSISTENCY (orders life cycle)
 Normal order: purchase -> approved -> handed to carrier -> delivered to customer
==============================================================================*/

-- 6.1 PERIOD COVERED
-- CHECK  : earliest and latest purchase date.

SELECT MIN(TRY_CAST(order_purchase_timestamp AS DATETIME2)) AS first_order,
       MAX(TRY_CAST(order_purchase_timestamp AS DATETIME2)) AS last_order
FROM dbo.orders

-- 6.2 ORDERS PER MONTH (to see thin or empty months)
-- CHECK  : order count per year-month.

SELECT YEAR(TRY_CAST(order_purchase_timestamp AS DATETIME2))  AS order_year,
       MONTH(TRY_CAST(order_purchase_timestamp AS DATETIME2)) AS order_month,
       COUNT(*) AS orders_count
FROM orders
GROUP BY YEAR(TRY_CAST(order_purchase_timestamp AS DATETIME2)), MONTH(TRY_CAST(order_purchase_timestamp AS DATETIME2))
ORDER BY order_year, order_month

-- 6.3 DATES IN THE WRONG ORDER
-- CHECK  : (a) approved before purchase, (b) carrier date before purchase,
--          (c) customer delivery before carrier pickup, (d) delivery before purchase.

SELECT
 SUM(CASE WHEN TRY_CAST(order_approved_at AS DATETIME2) < TRY_CAST(order_purchase_timestamp AS DATETIME2) THEN 1 ELSE 0 END) AS approved_before_purchase,
 SUM(CASE WHEN TRY_CAST(order_delivered_carrier_date AS DATETIME2) < TRY_CAST(order_purchase_timestamp AS DATETIME2) THEN 1 ELSE 0 END) 
 AS carrier_before_purchase,
 SUM(CASE WHEN TRY_CAST(order_delivered_customer_date AS DATETIME2) < TRY_CAST(order_delivered_carrier_date AS DATETIME2) THEN 1 ELSE 0 END) 
 AS delivered_before_carrier,
 SUM(CASE WHEN TRY_CAST(order_delivered_customer_date AS DATETIME2) < TRY_CAST(order_purchase_timestamp AS DATETIME2) THEN 1 ELSE 0 END) 
 AS delivered_before_purchase
FROM orders

-- 6.4 STATUS vs DATE CONTRADICTIONS
-- CHECK  : (a) status = delivered but delivery date is NULL,
--          (b) status = delivered but carrier/approval date is NULL,
--          (c) status is NOT delivered but a customer delivery date exists.

SELECT
 SUM(CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS delivered_but_no_customer_date,
 SUM(CASE WHEN order_status = 'delivered' AND order_delivered_carrier_date  IS NULL THEN 1 ELSE 0 END) AS delivered_but_no_carrier_date,
 SUM(CASE WHEN order_status = 'delivered' AND order_approved_at             IS NULL THEN 1 ELSE 0 END) AS delivered_but_no_approval_date,
 SUM(CASE WHEN order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS not_delivered_but_has_customer_date
FROM orders

-- 6.5 LATE DELIVERIES (business sanity check)
-- CHECK  : delivered orders where actual delivery is after the estimated date.

SELECT SUM(CASE WHEN TRY_CAST(order_delivered_customer_date AS DATETIME2) > TRY_CAST(order_estimated_delivery_date AS DATETIME2) THEN 1 ELSE 0 END)
AS late_orders,
       COUNT(order_delivered_customer_date) AS orders_with_delivery_date,
       100.0 * SUM(CASE WHEN TRY_CAST(order_delivered_customer_date AS DATETIME2) > TRY_CAST(order_estimated_delivery_date AS DATETIME2) THEN 1 ELSE 0 END)
             / NULLIF(COUNT(order_delivered_customer_date), 0) AS late_percent
FROM dbo.orders

-- 6.6 REVIEW DATE ORDER
-- CHECK  : reviews answered before they were created; reviews created before the order was placed.

SELECT
 SUM(CASE WHEN TRY_CAST(r.review_answer_timestamp AS DATETIME2) < TRY_CAST(r.review_creation_date AS DATETIME2) THEN 1 ELSE 0 END) AS answered_before_created,
 SUM(CASE WHEN TRY_CAST(r.review_creation_date AS DATETIME2) < TRY_CAST(o.order_purchase_timestamp AS DATETIME2) THEN 1 ELSE 0 END) AS review_before_purchase
FROM order_reviews r JOIN dbo.orders o ON r.order_id = o.order_id

/*==============================================================================
 SECTION 7 : CATEGORICAL & TEXT CONSISTENCY
==============================================================================*/

-- 7.1 STATES IN EACH TABLE
-- CHECK  : number of distinct states in Customer, sellers, geolocation.

SELECT (SELECT COUNT(DISTINCT customer_state)    FROM Customer)  AS customer_states,
       (SELECT COUNT(DISTINCT seller_state)      FROM sellers)     AS seller_states,
       (SELECT COUNT(DISTINCT geolocation_state) FROM geolocation) AS geolocation_states

-- 7.2 STATE CODES NOT 2 LETTERS / NOT UPPER CASE
-- CHECK  : state values that are not exactly 2 upper-case letters.

SELECT 'Customer' AS table_name, COUNT(*) AS bad_state_values FROM Customer
WHERE LEN(customer_state) <> 2 OR customer_state COLLATE Latin1_General_CS_AS <> UPPER(customer_state)
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
WHERE LEN(seller_state) <> 2 OR seller_state COLLATE Latin1_General_CS_AS <> UPPER(seller_state)
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
WHERE LEN(geolocation_state) <> 2 OR geolocation_state COLLATE Latin1_General_CS_AS <> UPPER(geolocation_state)

-- 7.3 CITY NAMES WITH SPACES OR UPPER CASE
-- CHECK  : city text that differs from its trimmed lower-case version.

SELECT (SELECT COUNT(*) FROM dbo.Customer    WHERE customer_city    COLLATE Latin1_General_CS_AS <> LOWER(LTRIM(RTRIM(customer_city)))) 
AS customer_city_issues,
       (SELECT COUNT(*) FROM dbo.sellers     WHERE seller_city      COLLATE Latin1_General_CS_AS <> LOWER(LTRIM(RTRIM(seller_city))))  
       AS seller_city_issues,
       (SELECT COUNT(*) FROM dbo.geolocation WHERE geolocation_city COLLATE Latin1_General_CS_AS <> LOWER(LTRIM(RTRIM(geolocation_city)))) 
       AS geo_city_issues

-- 7.4 SELLER CITIES CONTAINING DIGITS OR SYMBOLS
-- CHECK  : seller_city containing numbers, "/", "@" or ",".

SELECT seller_id, seller_city, seller_state
FROM sellers
WHERE seller_city LIKE '%[0-9/@,]%';

-- 7.5 SAME ZIP, DIFFERENT CITY SPELLING (geolocation)
-- CHECK  : zip prefixes that have more than one city spelling.

SELECT COUNT(*) AS zips_with_multiple_city_spellings
FROM (SELECT geolocation_zip_code_prefix
      FROM geolocation
      GROUP BY geolocation_zip_code_prefix
      HAVING COUNT(DISTINCT geolocation_city) > 1) x;

-- 7.6 PRODUCT CATEGORY NAMES (Portuguese / mixed language)
-- CHECK  : list of categories with product counts and their English translation.

SELECT p.product_category_name, t.product_category_name_english, COUNT(*) AS products
FROM products p
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY p.product_category_name, t.product_category_name_english
ORDER BY products DESC;

/*==============================================================================
 SECTION 8 : BUSINESS-RULE VALIDATION
==============================================================================*/

-- 8.1 ORDER-ITEM TOTAL vs PAYMENT TOTAL (reconciliation)
-- CHECK  : for each order, (sum of price + freight_value) compared with (sum of payment_value).

WITH i AS (SELECT order_id, SUM(price + freight_value) AS items_total FROM order_items GROUP BY order_id),
     p AS (SELECT order_id, SUM(payment_value)AS pay_total   FROM order_payments GROUP BY order_id)
SELECT COUNT(*) AS orders_compared,
       SUM(CASE WHEN ABS(i.items_total - p.pay_total) <= 1 THEN 1 ELSE 0 END) AS match_within_1,
       SUM(CASE WHEN ABS(i.items_total - p.pay_total) >  1 THEN 1 ELSE 0 END) AS mismatch_over_1
FROM i JOIN p ON i.order_id = p.order_id

-- 8.2 LIST OF THE MISMATCHING ORDERS (first 50, largest gap first)
-- CHECK  : the orders behind query 8.1.

WITH i AS (SELECT order_id, SUM(price + freight_value) AS items_total FROM order_items GROUP BY order_id),
     p AS (SELECT order_id, SUM(payment_value)        AS pay_total   FROM order_payments GROUP BY order_id)
SELECT TOP 50 i.order_id, i.items_total, p.pay_total, ABS(i.items_total - p.pay_total) AS gap
FROM i JOIN p ON i.order_id = p.order_id
WHERE ABS(i.items_total - p.pay_total) > 1
ORDER BY gap DESC

-- 8.3 ORDERS WITH MORE THAN ONE SELLER
-- CHECK  : orders whose items come from 2+ sellers.

SELECT COUNT(*) AS orders_with_multiple_sellers
FROM (SELECT order_id FROM order_items
      GROUP BY order_id HAVING COUNT(DISTINCT seller_id) > 1) x

-- 8.4 ORDERS WITH PAYMENT BUT NO ITEMS
-- CHECK  : orders that have payment rows but no order_items rows.

SELECT COUNT(DISTINCT p.order_id) AS orders_with_payment_but_no_items
FROM order_payments p
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = p.order_id)

-- 8.5 ZERO-VALUE PAYMENT ROWS BY TYPE
-- CHECK  : payment rows where payment_value = 0, by payment_type.

SELECT payment_type, COUNT(*) AS zero_value_rows
FROM dbo.order_payments WHERE payment_value = 0
GROUP BY payment_type

-- 8.6 INSTALMENTS BY PAYMENT TYPE
-- CHECK  : maximum instalments per payment type.

SELECT payment_type, MIN(payment_installments) AS min_inst, MAX(payment_installments) AS max_inst, COUNT(*) AS rows_count
FROM order_payments GROUP BY payment_type

-- 8.7 SHIPPING LIMIT DATE BEFORE PURCHASE
-- CHECK  : items whose seller shipping deadline is earlier than the order purchase date.

SELECT COUNT(*) AS items_deadline_before_purchase
FROM dbo.order_items oi JOIN dbo.orders o ON oi.order_id = o.order_id
WHERE TRY_CAST(oi.shipping_limit_date AS DATETIME2) < TRY_CAST(o.order_purchase_timestamp AS DATETIME2)

/*==============================================================================
 SECTION 9 : GEOLOCATION CHECKS
==============================================================================*/

-- 9.1 COORDINATES OUTSIDE BRAZIL
-- CHECK  : latitude / longitude outside an approximate Brazil bounding box
--          (lat -34 to 5.3 ; lng -74 to -34).

SELECT COUNT(*) AS rows_outside_brazil
FROM geolocation
WHERE geolocation_lat NOT BETWEEN -34 AND 5.3
   OR geolocation_lng NOT BETWEEN -74 AND -34

-- 9.2 ROWS PER ZIP (granularity)
-- CHECK  : how many geolocation rows each zip has (top 10).

SELECT TOP 10 geolocation_zip_code_prefix, COUNT(*) AS rows_for_zip
FROM dbo.geolocation GROUP BY geolocation_zip_code_prefix ORDER BY rows_for_zip DESC



/*==============================================================================
 END OF AUDIT. No data was changed. All queries above are SELECT-only.
 Cleaning (fixing the issues) is NOT part of this First Deliverable; it is
 planned in the Data Processing Plan slides and will be done in the final deliverable.
==============================================================================*/
