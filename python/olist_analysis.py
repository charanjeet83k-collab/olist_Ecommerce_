"""
OLIST BRAZILIAN E-COMMERCE - ANALYSIS (one file)
Reads the nine CSV files, checks data quality, builds order-level and item-level tables at the right grain,
calculates KPIs, runs the EDA (sales, customers, sellers, delivery, reviews, geography) and saves tables and charts.

Run:   set OLIST_DATA_DIR to the folder with the nine CSV files, then
       python olist_analysis.py            (all steps)
       python olist_analysis.py build      (or: quality | kpis | extra)
Outputs: data/processed/*.csv.gz, reports/*.csv, reports/kpi_summary.json, reports/charts/*.png
Nothing in the source CSV files is changed. Rules: see the KPI notes in the comments below.
"""
import json, os, sys
from pathlib import Path
import numpy as np, pandas as pd
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt


# ==============================================================================
# 1. SETTINGS
# ==============================================================================
ROOT = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("OLIST_DATA_DIR", ROOT / "data" / "raw"))
PROCESSED_DIR = Path(os.environ.get("OLIST_PROCESSED_DIR", ROOT / "data" / "processed"))  # can point to a disk or private folder when deploying
REPORTS_DIR = ROOT / "reports"
FILES = {  # table name -> csv file name (as received)
    "customers": "Customer.csv", "geolocation": "geolocation_2.csv", "order_items": "order_items.csv",
    "order_payments": "order_payments.csv", "order_reviews": "order_reviews.csv", "orders": "orders.csv",
    "category_translation": "product_category_name_translation.csv", "products": "products.csv", "sellers": "sellers.csv"}
EXPECTED_COLUMNS = {
    "customers": ["customer_id", "customer_unique_id", "customer_zip_code_prefix", "customer_city", "customer_state"],
    "geolocation": ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng", "geolocation_city", "geolocation_state"],
    "order_items": ["order_id", "order_item_id", "product_id", "seller_id", "shipping_limit_date", "price", "freight_value"],
    "order_payments": ["order_id", "payment_sequential", "payment_type", "payment_installments", "payment_value"],
    "order_reviews": ["review_id", "order_id", "review_score", "review_comment_title", "review_comment_message", "review_creation_date", "review_answer_timestamp"],
    "orders": ["order_id", "customer_id", "order_status", "order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date", "order_delivered_customer_date", "order_estimated_delivery_date"],
    "category_translation": ["product_category_name", "product_category_name_english"],
    "products": ["product_id", "product_category_name", "product_name_lenght", "product_description_lenght", "product_photos_qty", "product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"],
    "sellers": ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"]}
# KPI rules (same rules are used in the SQL views and the DAX measures)
EXCLUDED_SALES_STATUS = ("canceled", "unavailable")   # not counted in sales KPIs
BRAZIL_BOX = dict(lat_min=-34.0, lat_max=5.3, lng_min=-74.0, lng_max=-34.0)  # approximate bounding box


# ==============================================================================
# 2. LOAD AND VALIDATE THE NINE TABLES
# ==============================================================================
DATE_COLS = {"orders": ["order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date",
                        "order_delivered_customer_date", "order_estimated_delivery_date"],
             "order_items": ["shipping_limit_date"], "order_reviews": ["review_creation_date", "review_answer_timestamp"]}

def load_tables(data_dir=None):
    data_dir = data_dir or DATA_DIR
    tables = {}
    for name, fname in FILES.items():
        df = pd.read_csv(f"{data_dir}/{fname}")
        missing = [c for c in EXPECTED_COLUMNS[name] if c not in df.columns]
        if missing:
            raise ValueError(f"{fname}: missing columns {missing}")
        for c in DATE_COLS.get(name, []):
            df[c] = pd.to_datetime(df[c], errors="coerce")
        tables[name] = df
    return tables

def row_counts(tables):
    return pd.DataFrame({"table": list(tables), "rows": [len(t) for t in tables.values()],
                         "columns": [t.shape[1] for t in tables.values()]})


# ==============================================================================
# 3. DATA-QUALITY CHECKS (Python mirror of the SQL audit)
# ==============================================================================
def run_checks(t):
    rows = []
    def add(table, check, value, kind="defect"):   # kind: defect (issue if >0), info (expected/explained), count
        v = int(value)
        status = "Info" if kind in ("info", "count") else ("Issue" if v > 0 else "No issue")
        rows.append({"table": table, "check": check, "result": v, "status": status})
    o, it, pay, rv, c, p, s, g, tr = (t[k] for k in ["orders", "order_items", "order_payments", "order_reviews", "customers", "products", "sellers", "geolocation", "category_translation"])
    for k, df in t.items(): add(k, "row count", len(df), "count")
    for col in ["order_approved_at", "order_delivered_carrier_date", "order_delivered_customer_date"]: add("orders", f"NULL {col}", o[col].isna().sum(), "info")
    add("order_reviews", "NULL review_comment_title", rv.review_comment_title.isna().sum(), "info"); add("order_reviews", "NULL review_comment_message", rv.review_comment_message.isna().sum(), "info")
    add("products", "NULL product_category_name", p.product_category_name.isna().sum()); add("products", "NULL product_weight_g", p.product_weight_g.isna().sum())
    add("orders", "repeated order_id", o.order_id.duplicated().sum()); add("customers", "repeated customer_id", c.customer_id.duplicated().sum())
    add("customers", "extra records for repeated customer_unique_id", c.customer_unique_id.duplicated().sum(), "info")
    add("order_items", "repeated (order_id, order_item_id)", it.duplicated(["order_id", "order_item_id"]).sum()); add("order_payments", "repeated (order_id, payment_sequential)", pay.duplicated(["order_id", "payment_sequential"]).sum())
    add("products", "repeated product_id", p.product_id.duplicated().sum()); add("sellers", "repeated seller_id", s.seller_id.duplicated().sum())
    add("order_reviews", "extra rows sharing a review_id", rv.review_id.duplicated().sum()); add("order_reviews", "full-row duplicates", rv.duplicated().sum())
    add("order_reviews", "orders with 2+ reviews", (rv.order_id.value_counts() > 1).sum()); add("geolocation", "exact duplicate rows", g.duplicated().sum())
    vc = g.geolocation_zip_code_prefix.value_counts(); add("geolocation", "ZIP prefixes with 2+ rows", (vc > 1).sum(), "info")
    add("orders", "orders without customer", (~o.customer_id.isin(c.customer_id)).sum()); add("order_items", "items without order", (~it.order_id.isin(o.order_id)).sum())
    add("order_items", "items without product", (~it.product_id.isin(p.product_id)).sum()); add("order_items", "items without seller", (~it.seller_id.isin(s.seller_id)).sum())
    add("order_payments", "payments without order", (~pay.order_id.isin(o.order_id)).sum()); add("order_reviews", "reviews without order", (~rv.order_id.isin(o.order_id)).sum())
    add("orders", "orders without items", (~o.order_id.isin(it.order_id)).sum()); add("orders", "orders without payment", (~o.order_id.isin(pay.order_id)).sum())
    add("orders", "orders without review", (~o.order_id.isin(rv.order_id)).sum(), "info")
    add("products", "products whose category has no English name", (p.product_category_name.notna() & ~p.product_category_name.isin(tr.product_category_name)).sum())
    add("customers", "customer rows with ZIP not in geolocation", (~c.customer_zip_code_prefix.isin(g.geolocation_zip_code_prefix)).sum()); add("sellers", "seller rows with ZIP not in geolocation", (~s.seller_zip_code_prefix.isin(g.geolocation_zip_code_prefix)).sum())
    add("orders", "carrier pickup before purchase", (o.order_delivered_carrier_date < o.order_purchase_timestamp).sum()); add("orders", "delivered before carrier pickup", (o.order_delivered_customer_date < o.order_delivered_carrier_date).sum())
    add("orders", "approved after carrier pickup", (o.order_approved_at > o.order_delivered_carrier_date).sum()); add("orders", "delivered before purchase", (o.order_delivered_customer_date < o.order_purchase_timestamp).sum())
    add("orders", "estimated before purchase", (o.order_estimated_delivery_date < o.order_purchase_timestamp).sum())
    add("orders", "status delivered without delivery date", ((o.order_status == "delivered") & o.order_delivered_customer_date.isna()).sum())
    add("orders", "status not delivered but has delivery date", ((o.order_status != "delivered") & o.order_delivered_customer_date.notna()).sum())
    add("order_items", "shipping_limit_date after 2018", (it.shipping_limit_date.dt.year > 2018).sum())
    m = rv.merge(o[["order_id", "order_purchase_timestamp"]], on="order_id"); add("order_reviews", "review created before purchase", (m.review_creation_date < m.order_purchase_timestamp).sum())
    add("order_reviews", "answered before created", (rv.review_answer_timestamp < rv.review_creation_date).sum())
    add("order_items", "price <= 0", (it.price <= 0).sum()); add("order_items", "freight < 0", (it.freight_value < 0).sum()); add("order_items", "freight = 0", (it.freight_value == 0).sum(), "info")
    add("order_payments", "payment_value = 0", (pay.payment_value == 0).sum()); add("order_payments", "payment_type = not_defined", (pay.payment_type == "not_defined").sum())
    add("order_payments", "instalments < 1", (pay.payment_installments < 1).sum()); add("order_reviews", "review_score outside 1-5", (~rv.review_score.between(1, 5)).sum())
    add("products", "product_weight_g = 0", (p.product_weight_g == 0).sum())
    b = BRAZIL_BOX; add("geolocation", "points outside Brazil box", (~(g.geolocation_lat.between(b["lat_min"], b["lat_max"]) & g.geolocation_lng.between(b["lng_min"], b["lng_max"]))).sum())
    add("sellers", "seller_city with digits or symbols", s.seller_city.str.contains(r"[0-9/\\@,]").sum())
    i2 = (it.price + it.freight_value).groupby(it.order_id).sum(); p2 = pay.groupby("order_id").payment_value.sum(); j = pd.concat([i2, p2], axis=1, keys=["i", "p"]).dropna()
    add("orders vs payments", "item value + freight vs payments differ by more than 1 BRL", ((j.i - j.p).abs() > 1).sum())
    add("order_items", "orders with 2+ sellers", (it.groupby("order_id").seller_id.nunique() > 1).sum(), "info")
    return pd.DataFrame(rows)

def main_quality():
    df = run_checks(load_tables()); REPORTS_DIR.mkdir(exist_ok=True); df.to_csv(REPORTS_DIR / "data_quality_report.csv", index=False)
    print(df.to_string(index=False)); print(df.status.value_counts().to_dict())


# ==============================================================================
# 4. BUILD ANALYSIS TABLES (one row per order / per item; no join multiplication)
# ==============================================================================
def haversine_km(lat1, lng1, lat2, lng2):
    r = 6371.0
    p1, p2 = np.radians(lat1), np.radians(lat2)
    a = np.sin((p2 - p1) / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(np.radians(lng2 - lng1) / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))

def zip_centroids(geo):
    """One row per ZIP prefix: drop points outside Brazil, then average lat/lng."""
    b = BRAZIL_BOX
    g = geo[geo.geolocation_lat.between(b["lat_min"], b["lat_max"]) & geo.geolocation_lng.between(b["lng_min"], b["lng_max"])]
    return g.groupby("geolocation_zip_code_prefix").agg(lat=("geolocation_lat", "mean"), lng=("geolocation_lng", "mean")).reset_index()

def build_item_level(t):
    items = t["order_items"].merge(t["products"], on="product_id", how="left").merge(
        t["category_translation"], on="product_category_name", how="left")
    # unknown categories are preserved: missing -> "Unknown"; untranslated -> Portuguese name kept
    items["category"] = items["product_category_name_english"].fillna(items["product_category_name"]).fillna("Unknown")
    items = items.merge(t["sellers"], on="seller_id", how="left")
    o = t["orders"][["order_id", "customer_id", "order_status", "order_purchase_timestamp"]]
    items = items.merge(o, on="order_id", how="left").merge(
        t["customers"][["customer_id", "customer_unique_id", "customer_state", "customer_city"]], on="customer_id", how="left")
    return items

def build_order_level(t):
    o = t["orders"].copy()
    items = build_item_level(t)
    first = items.sort_values(["order_id", "order_item_id"]).groupby("order_id").first()
    agg = items.groupby("order_id").agg(item_sales=("price", "sum"), freight=("freight_value", "sum"), n_items=("order_item_id", "count"),
                                        n_sellers=("seller_id", "nunique"), total_weight_g=("product_weight_g", "sum"),
                                        max_photos=("product_photos_qty", "max"))
    agg["category"] = first["category"]; agg["seller_state"] = first["seller_state"]
    agg["seller_zip"] = first["seller_zip_code_prefix"]
    pay = t["order_payments"]
    pa = pay.groupby("order_id").agg(payment_total=("payment_value", "sum"), n_payment_rows=("payment_sequential", "count"),
                                     max_installments=("payment_installments", "max"))
    main = pay.sort_values("payment_value", ascending=False).drop_duplicates("order_id").set_index("order_id")["payment_type"].rename("main_payment_type")
    rv = t["order_reviews"].groupby("order_id").agg(review_score=("review_score", "mean"), n_reviews=("review_id", "count"))
    o = o.merge(t["customers"], on="customer_id", how="left")
    o = o.merge(agg, left_on="order_id", right_index=True, how="left").merge(pa, left_on="order_id", right_index=True, how="left")
    o = o.merge(main, left_on="order_id", right_index=True, how="left").merge(rv, left_on="order_id", right_index=True, how="left")
    cz = zip_centroids(t["geolocation"]).set_index("geolocation_zip_code_prefix")
    o = o.join(cz.rename(columns={"lat": "c_lat", "lng": "c_lng"}), on="customer_zip_code_prefix")
    o = o.join(cz.rename(columns={"lat": "s_lat", "lng": "s_lng"}), on="seller_zip")
    o["distance_km"] = haversine_km(o.c_lat, o.c_lng, o.s_lat, o.s_lng)
    p = o["order_purchase_timestamp"]
    o["purchase_month"] = p.dt.to_period("M").astype(str); o["purchase_year"] = p.dt.year
    o["purchase_dow"] = p.dt.dayofweek; o["purchase_hour"] = p.dt.hour
    o["approval_hours"] = (o.order_approved_at - p).dt.total_seconds() / 3600
    o["estimated_days"] = (o.order_estimated_delivery_date - p).dt.total_seconds() / 86400
    o["delivery_days"] = (o.order_delivered_customer_date - p).dt.total_seconds() / 86400
    o["delay_days"] = (o.order_delivered_customer_date - o.order_estimated_delivery_date).dt.total_seconds() / 86400
    o["valid_delivery"] = (o.order_status == "delivered") & o.order_delivered_customer_date.notna() & (o.delivery_days >= 0) & (
        o.order_delivered_carrier_date.isna() | (o.order_delivered_customer_date >= o.order_delivered_carrier_date))
    o["is_late"] = np.where(o.valid_delivery, (o.order_delivered_customer_date > o.order_estimated_delivery_date).astype(float), np.nan)
    o["same_state"] = (o.customer_state == o.seller_state).astype(float).where(o.seller_state.notna())
    o["is_sales_order"] = (~o.order_status.isin(EXCLUDED_SALES_STATUS)) & o.n_items.notna()
    return o

def main_build():
    t = load_tables(); PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    o = build_order_level(t); o.to_csv(PROCESSED_DIR / "order_level.csv.gz", index=False)
    it = build_item_level(t); it.to_csv(PROCESSED_DIR / "item_level.csv.gz", index=False)
    t["order_payments"].to_csv(PROCESSED_DIR / "payment_level.csv.gz", index=False)   # one row per payment part (for the dashboard)
    print("order_level", o.shape, "item_level", it.shape)


# ==============================================================================
# 5. KPIs, TABLES AND CHARTS
# ==============================================================================
def load_processed():
    o = pd.read_csv(PROCESSED_DIR / "order_level.csv.gz", parse_dates=["order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date"])
    it = pd.read_csv(PROCESSED_DIR / "item_level.csv.gz", parse_dates=["order_purchase_timestamp"])
    return o, it

def kpi_summary(o, it):
    s = o[o.is_sales_order]; v = o[o.valid_delivery]
    per_person = o.groupby("customer_unique_id").order_id.nunique()
    it_s = it[~it.order_status.isin(["canceled", "unavailable"])]
    top10 = it_s.groupby("seller_id").price.sum().nlargest(10).sum() / it_s.price.sum()
    return {
        "orders_all": int(len(o)), "orders_sales_valid": int(len(s)),
        "item_sales_brl_valid_orders": round(float(s.item_sales.sum()), 2), "freight_brl_valid_orders": round(float(s.freight.sum()), 2),
        "avg_item_order_value_brl": round(float(s.item_sales.mean()), 2),
        "payment_total_brl_all_payments": round(float(o.payment_total.sum()), 2),
        "unique_customers": int(o.customer_unique_id.nunique()),
        "repeat_customer_rate_pct": round(100 * float((per_person > 1).mean()), 2),
        "active_sellers": int(it_s.seller_id.nunique()), "top10_seller_share_pct": round(100 * float(top10), 2),
        "avg_review_score_order_level": round(float(o.review_score.mean()), 3),
        "pct_orders_score_4_5": round(100 * float((o.review_score.dropna() >= 4).mean()), 2),
        "pct_orders_score_1_2": round(100 * float((o.review_score.dropna() <= 2).mean()), 2),
        "review_coverage_pct": round(100 * float(o.review_score.notna().mean()), 2),
        "valid_delivered_orders": int(len(v)), "avg_delivery_days": round(float(v.delivery_days.mean()), 2),
        "avg_estimated_days": round(float(v.estimated_days.mean()), 2),
        "late_pct_timestamp_rule": round(100 * float(v.is_late.mean()), 2),
        "late_pct_date_only_rule": round(100 * float((v.order_delivered_customer_date.dt.normalize() > v.order_estimated_delivery_date.dt.normalize()).mean()), 2),
        "avg_delay_days_late_orders": round(float(v[v.is_late == 1].delay_days.mean()), 2)}

def tables(o, it):
    s = o[o.is_sales_order]; v = o[o.valid_delivery]
    it_s = it[~it.order_status.isin(["canceled", "unavailable"])]
    out = {}
    out["monthly_sales"] = s.groupby("purchase_month").agg(orders=("order_id", "count"), item_sales=("item_sales", "sum"), freight=("freight", "sum")).reset_index()
    out["category_sales"] = it_s.groupby("category").agg(item_sales=("price", "sum"), items_sold=("price", "count"), avg_price=("price", "mean")).sort_values("item_sales", ascending=False).reset_index()
    out["state_orders"] = s.groupby("customer_state").agg(orders=("order_id", "count"), item_sales=("item_sales", "sum")).sort_values("orders", ascending=False).reset_index()
    out["payment_mix"] = o.dropna(subset=["main_payment_type"]).groupby("main_payment_type").agg(orders=("order_id", "count"), payment_total=("payment_total", "sum")).reset_index()
    out["review_distribution"] = o.review_score.dropna().round().astype(int).value_counts().sort_index().rename_axis("score").reset_index(name="orders")
    out["delivery_by_state"] = v.groupby("customer_state").agg(orders=("order_id", "count"), avg_delivery_days=("delivery_days", "mean"), late_pct=("is_late", lambda x: 100 * x.mean())).sort_values("avg_delivery_days").reset_index()
    out["delivery_monthly"] = v.groupby("purchase_month").agg(orders=("order_id", "count"), avg_delivery_days=("delivery_days", "mean"), avg_estimated_days=("estimated_days", "mean"), late_pct=("is_late", lambda x: 100 * x.mean())).reset_index()
    b = v.dropna(subset=["review_score"]).copy()
    b["delay_bucket"] = pd.cut(b.delay_days, [-1e9, 0, 3, 7, 1e9], labels=["on time or early", "1-3 days late", "4-7 days late", "over 7 days late"])
    out["score_by_delay"] = b.groupby("delay_bucket", observed=True).agg(orders=("order_id", "count"), avg_score=("review_score", "mean")).reset_index()
    out["seller_scorecard"] = it_s.groupby("seller_id").agg(item_sales=("price", "sum"), items=("price", "count"), orders=("order_id", "nunique")).sort_values("item_sales", ascending=False).head(25).reset_index()
    return out

def charts(t):
    d = REPORTS_DIR / "charts"; d.mkdir(parents=True, exist_ok=True)
    def save(name): plt.tight_layout(); plt.savefig(d / name, dpi=130); plt.close()
    m = t["monthly_sales"]; m = m[(m.purchase_month >= "2017-01") & (m.purchase_month <= "2018-08")]
    fig, ax = plt.subplots(figsize=(9, 4)); ax.plot(m.purchase_month, m.item_sales / 1e3, marker="o", color="#348E90")
    ax.set_title("Monthly item sales, Jan 2017 - Aug 2018 (valid orders)"); ax.set_ylabel("R$ thousand"); plt.xticks(rotation=60); save("monthly_item_sales.png")
    c = t["category_sales"].head(10)[::-1]; plt.figure(figsize=(8, 4.5)); plt.barh(c.category, c.item_sales / 1e3, color="#348E90")
    plt.title("Top 10 categories by item sales"); plt.xlabel("R$ thousand"); save("top_categories.png")
    r = t["review_distribution"]; plt.figure(figsize=(6, 4)); plt.bar(r.score, r.orders, color="#D98E1F"); plt.title("Order-level review score (rounded)"); plt.xlabel("score"); plt.ylabel("orders"); save("review_distribution.png")
    s = t["score_by_delay"]; plt.figure(figsize=(7, 4)); plt.bar(s.delay_bucket.astype(str), s.avg_score, color="#4A6F8A"); plt.ylim(1, 5); plt.title("Average review score by delivery delay (association)"); plt.xticks(rotation=15); save("score_by_delay.png")
    d_ = t["delivery_by_state"]; plt.figure(figsize=(9, 4)); plt.bar(d_.customer_state, d_.avg_delivery_days, color="#348E90"); plt.title("Average delivery days by customer state"); plt.ylabel("days"); save("delivery_by_state.png")
    p = t["payment_mix"]; plt.figure(figsize=(5.5, 5.5)); plt.pie(p.payment_total, labels=p.main_payment_type, autopct="%1.0f%%"); plt.title("Share of payment value by main payment type"); save("payment_mix.png")

def main_kpis():
    o, it = load_processed(); REPORTS_DIR.mkdir(exist_ok=True)
    k = kpi_summary(o, it); json.dump(k, open(REPORTS_DIR / "kpi_summary.json", "w"), indent=2)
    t = tables(o, it)
    for n, df in t.items(): df.to_csv(REPORTS_DIR / f"{n}.csv", index=False)
    charts(t); print(json.dumps(k, indent=2))


# ==============================================================================
# 6. CUSTOMERS, SELLERS, REGIONS AND CATEGORIES
# ==============================================================================
def build(o, it):
    out, facts = {}, {}
    sales = o[o.is_sales_order]; valid = o[o.valid_delivery]
    # customers: orders per real person, new vs returning customers per month
    per = o.groupby("customer_unique_id").agg(n_orders=("order_id", "nunique"), first_month=("purchase_month", "min"))
    out["orders_per_customer"] = per.n_orders.value_counts().sort_index().rename_axis("orders").reset_index(name="customers")
    m = o.merge(per[["first_month"]], left_on="customer_unique_id", right_index=True)
    nr = m.groupby("purchase_month").agg(customers=("customer_unique_id", "nunique"), returning=("customer_unique_id", lambda x: x[m.loc[x.index, "purchase_month"] > m.loc[x.index, "first_month"]].nunique()))
    out["new_vs_returning_monthly"] = nr.reset_index()
    facts["people_with_2plus_orders"] = int((per.n_orders > 1).sum())
    # sellers: scorecard, concentration, late share (valid deliveries), review score
    si = it[~it.order_status.isin(["canceled", "unavailable"])].merge(o[["order_id", "valid_delivery", "is_late", "review_score"]], on="order_id", how="left")
    g = si.groupby("seller_id").agg(item_sales=("price", "sum"), items=("price", "count"), orders=("order_id", "nunique"))
    late = si[si.valid_delivery == True].groupby("seller_id").agg(delivered_items=("is_late", "count"), late_pct=("is_late", lambda x: 100 * x.mean()))
    rev = si.dropna(subset=["review_score"]).groupby("seller_id").review_score.mean().rename("avg_review_score")
    sc = g.join(late).join(rev).sort_values("item_sales", ascending=False)
    sc["share_pct"] = 100 * sc.item_sales / sc.item_sales.sum(); sc["cum_share_pct"] = sc.share_pct.cumsum()
    out["seller_scorecard"] = sc.head(25).reset_index(); out["seller_pareto"] = sc[["item_sales", "share_pct", "cum_share_pct"]].reset_index(drop=True).reset_index().rename(columns={"index": "rank"})
    out["sellers_highest_late_share"] = sc[sc.delivered_items >= 50].sort_values("late_pct", ascending=False).head(10).reset_index()
    facts["sellers_for_50pct_sales"] = int((sc.cum_share_pct < 50).sum() + 1); facts["sellers_for_80pct_sales"] = int((sc.cum_share_pct < 80).sum() + 1); facts["active_sellers"] = int(len(sc))
    # geography
    st = sales.groupby("customer_state").agg(orders=("order_id", "count"), item_sales=("item_sales", "sum"))
    v = valid.groupby("customer_state").agg(avg_delivery_days=("delivery_days", "mean"), late_pct=("is_late", lambda x: 100 * x.mean()), delivered_orders=("order_id", "count"))
    out["state_summary"] = st.join(v).join(o.groupby("customer_state").review_score.mean().rename("avg_review_score")).sort_values("orders", ascending=False).reset_index()
    out["top_cities"] = sales.groupby(["customer_city", "customer_state"]).size().rename("orders").sort_values(ascending=False).head(10).reset_index()
    # categories: monthly trend of the top 5, late share and score for big categories
    sc_items = it[~it.order_status.isin(["canceled", "unavailable"])]
    top5 = sc_items.groupby("category").price.sum().nlargest(5).index
    t = sc_items[sc_items.category.isin(top5)].assign(month=lambda d: d.order_purchase_timestamp.dt.strftime("%Y-%m")).groupby(["month", "category"]).price.sum().unstack().fillna(0)
    out["category_monthly_top5"] = t.reset_index()
    ci = it[~it.order_status.isin(["canceled", "unavailable"])].merge(o[["order_id", "valid_delivery", "is_late", "review_score"]], on="order_id")
    cat = ci.groupby("category").agg(items=("price", "count"), item_sales=("price", "sum"), avg_review=("review_score", "mean"), late_pct=("is_late", lambda x: 100 * x.mean()))
    out["category_quality"] = cat[cat["items"] >= 200].sort_values("item_sales", ascending=False).head(15).reset_index()
    return out, facts

def charts_extra(t):
    d = REPORTS_DIR / "charts"
    def save(n): plt.tight_layout(); plt.savefig(d / n, dpi=130); plt.close()
    p = t["seller_pareto"]; plt.figure(figsize=(7, 4)); plt.plot(p["rank"] + 1, p.cum_share_pct, color="#348E90"); plt.axhline(80, ls="--", color="#999"); plt.title("Seller concentration: cumulative share of item sales"); plt.xlabel("sellers ranked by sales"); plt.ylabel("% of item sales"); save("seller_pareto.png")
    c = t["orders_per_customer"]; plt.figure(figsize=(6, 4)); plt.bar(c.orders.astype(str), c.customers, color="#D98E1F"); plt.yscale("log"); plt.title("Orders per customer (log scale)"); plt.xlabel("orders"); plt.ylabel("customers"); save("orders_per_customer.png")
    n = t["new_vs_returning_monthly"]; n = n[(n.purchase_month >= "2017-01") & (n.purchase_month <= "2018-08")]; plt.figure(figsize=(9, 4)); plt.plot(n.purchase_month, n.customers, label="customers", color="#348E90"); plt.plot(n.purchase_month, n.returning, label="returning (first order in an earlier month)", color="#D98E1F"); plt.legend(); plt.xticks(rotation=60); plt.title("Customers and returning customers per month"); save("new_vs_returning.png")
    s = t["state_summary"].head(10); plt.figure(figsize=(8, 4)); plt.bar(s.customer_state, s.item_sales / 1e3, color="#4A6F8A"); plt.title("Top 10 states by item sales (R$ thousand)"); save("state_item_sales.png")
    k = t["category_monthly_top5"]; k = k[(k.month >= "2017-01") & (k.month <= "2018-08")]; plt.figure(figsize=(9, 4.5))
    for col in k.columns[1:]: plt.plot(k.month, k[col] / 1e3, label=col)
    plt.legend(fontsize=7); plt.xticks(rotation=60); plt.title("Monthly item sales of the top 5 categories (R$ thousand)"); save("category_trends.png")

def main_extra():
    o, it = load_processed(); t, facts = build(o, it)
    for n, df in t.items(): df.to_csv(REPORTS_DIR / f"{n}.csv", index=False)
    charts_extra(t); json.dump(facts, open(REPORTS_DIR / "extra_facts.json", "w"), indent=2); print(json.dumps(facts, indent=1))
    print(t["state_summary"].head(5).round(2).to_string(index=False)); print(t["sellers_highest_late_share"].head(3).round(2).to_string(index=False)); print(t["orders_per_customer"].head(6).to_string(index=False))


# ==============================================================================
# 7. COMMAND LINE
# ==============================================================================
STEPS = {"build": main_build, "quality": main_quality, "kpis": main_kpis, "extra": main_extra}

if __name__ == "__main__":
    wanted = sys.argv[1:] or ["build", "quality", "kpis", "extra"]
    for step in wanted:
        print(f"\n=== {step}"); STEPS[step]()
