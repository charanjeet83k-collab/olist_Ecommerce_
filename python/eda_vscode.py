# %% [markdown]
# # Olist Brazilian E-Commerce - Exploratory Data Analysis (VS Code)
# Open this file in VS Code, then click **Run Cell** above each `# %%` line (or press Shift+Enter).
# Charts appear in the Interactive Window. Needs: Python + Jupyter extensions, the nine CSV files in `data/raw/`
# (or set OLIST_DATA_DIR), and `pip install -r requirements.txt`. The source files are only read, never changed.

# %% 1. Setup
import warnings; warnings.filterwarnings("ignore")
import numpy as np, pandas as pd
import matplotlib.pyplot as plt
from olist_analysis import (load_tables, row_counts, run_checks, build_order_level, build_item_level, DATA_DIR)
pd.set_option("display.width", 160); pd.set_option("display.max_columns", 30)
plt.rcParams.update({"figure.figsize": (9, 4), "axes.grid": True, "grid.alpha": .25, "axes.spines.top": False, "axes.spines.right": False})
TEAL, AMBER = "#348E90", "#D98E1F"
print("Reading CSV files from:", DATA_DIR)

# %% 2. Load the nine tables and check their size
t = load_tables()                       # also validates that every expected column exists
row_counts(t)

# %% 3. Look at each table (first rows)
for name, df in t.items():
    print(f"\n--- {name}: {df.shape[0]:,} rows x {df.shape[1]} columns"); print(df.head(3))

# %% 4. Data-quality checks (Python version of the SQL audit)
dq = run_checks(t)
print(dq.status.value_counts().to_dict())
dq[dq.status == "Issue"]

# %% 5. Missing values per column (only columns that have any)
miss = pd.concat({k: v.isna().sum() for k, v in t.items()}).rename("missing").reset_index()
miss.columns = ["table", "column", "missing"]; miss[miss.missing > 0].sort_values("missing", ascending=False)

# %% 6. Build analysis tables at the right grain (one row per order / per item)
o = build_order_level(t); it = build_item_level(t)
print("orders:", len(o), "= source", len(t["orders"]), "| items:", len(it), "= source", len(t["order_items"]))
assert len(o) == len(t["orders"]) and o.order_id.is_unique, "joins multiplied rows"
assert abs(o.item_sales.sum() - t["order_items"].price.sum()) < 0.05, "item value changed"
print("OK: no row multiplication, item value equals the source")

# %% 7. KPI summary (sales KPIs exclude canceled and unavailable orders)
s = o[o.is_sales_order]; v = o[o.valid_delivery]; per = o.groupby("customer_unique_id").order_id.nunique()
kpi = pd.Series({"Orders (valid)": len(s), "Item sales (R$)": round(s.item_sales.sum(), 2), "Freight (R$)": round(s.freight.sum(), 2),
                 "Avg item order value (R$)": round(s.item_sales.mean(), 2), "Payment total, all orders (R$)": round(o.payment_total.sum(), 2),
                 "Unique customers": o.customer_unique_id.nunique(), "Repeat customer rate (%)": round(100 * (per > 1).mean(), 2),
                 "Avg review score": round(o.review_score.mean(), 3), "Late deliveries (%)": round(100 * v.is_late.mean(), 2),
                 "Avg delivery days": round(v.delivery_days.mean(), 2)}); kpi

# %% 8. Distributions: price, freight, delivery days
fig, ax = plt.subplots(1, 3, figsize=(14, 3.6))
t["order_items"].price.clip(upper=500).plot.hist(bins=40, ax=ax[0], color=TEAL, title="Item price (R$, capped at 500)")
t["order_items"].freight_value.clip(upper=100).plot.hist(bins=40, ax=ax[1], color=AMBER, title="Freight (R$, capped at 100)")
v.delivery_days.clip(upper=60).plot.hist(bins=40, ax=ax[2], color="#4A6F8A", title="Delivery days (capped at 60)"); plt.tight_layout(); plt.show()

# %% 9. Sales trend by month (Jan 2017 - Aug 2018; first and last months are incomplete)
m = s.groupby("purchase_month").agg(orders=("order_id", "count"), item_sales=("item_sales", "sum")).loc["2017-01":"2018-08"]
fig, ax = plt.subplots(1, 2, figsize=(13, 3.8)); m.item_sales.plot(ax=ax[0], marker="o", color=TEAL, title="Item sales per month (R$)"); m.orders.plot.bar(ax=ax[1], color=AMBER, title="Orders per month"); plt.tight_layout(); plt.show()

# %% 10. Categories: top 10 by item sales and their share
sales_items = it[~it.order_status.isin(["canceled", "unavailable"])]
cat = sales_items.groupby("category").price.agg(item_sales="sum", items="count").sort_values("item_sales", ascending=False)
cat["share_%"] = (100 * cat.item_sales / cat.item_sales.sum()).round(1)
print("Top 5 share %:", round(100 * cat.item_sales.head(5).sum() / cat.item_sales.sum(), 1), "| Top 10 share %:", round(100 * cat.item_sales.head(10).sum() / cat.item_sales.sum(), 1))
cat.head(10)[::-1].item_sales.plot.barh(color=TEAL, title="Top 10 categories by item sales (R$)"); plt.show()

# %% 11. Customers: orders per real person (customer_unique_id)
print("customer_id records:", o.customer_id.nunique(), "| real people:", o.customer_unique_id.nunique(), "| repeat rate %:", round(100 * (per > 1).mean(), 2))
per.value_counts().sort_index().plot.bar(color=AMBER, logy=True, title="Customers by number of orders (log scale)"); plt.show()

# %% 12. Sellers: how concentrated are the sales?
sel = sales_items.groupby("seller_id").price.sum().sort_values(ascending=False)
cum = 100 * sel.cumsum() / sel.sum()
print("sellers:", len(sel), "| sellers for 50% of sales:", int((cum < 50).sum() + 1), "| for 80%:", int((cum < 80).sum() + 1), "| top 10 share %:", round(100 * sel.head(10).sum() / sel.sum(), 1))
plt.plot(range(1, len(cum) + 1), cum.values, color=TEAL); plt.axhline(80, ls="--", color="grey"); plt.title("Seller concentration (cumulative % of item sales)"); plt.xlabel("sellers ranked by sales"); plt.show()

# %% 13. Delivery: actual vs promised, by state
print("late % (delivered after the estimated timestamp):", round(100 * v.is_late.mean(), 2), "| avg delivery days:", round(v.delivery_days.mean(), 2), "| avg promised days:", round(v.estimated_days.mean(), 2))
st_ = v.groupby("customer_state").agg(orders=("order_id", "count"), avg_days=("delivery_days", "mean"), late_pct=("is_late", lambda x: 100 * x.mean())).sort_values("avg_days")
fig, ax = plt.subplots(1, 2, figsize=(13, 3.8)); st_.avg_days.plot.bar(ax=ax[0], color=TEAL, title="Average delivery days by state"); st_.late_pct.plot.bar(ax=ax[1], color=AMBER, title="Late deliveries % by state"); plt.tight_layout(); plt.show()
st_.sort_values("late_pct", ascending=False).head(5)

# %% 14. Reviews: score distribution and score by delivery delay (an association, not proof of cause)
rv = o.review_score.dropna()
print("avg score:", round(rv.mean(), 2), "| % 4-5:", round(100 * (rv >= 4).mean(), 1), "| % 1-2:", round(100 * (rv <= 2).mean(), 1), "| coverage %:", round(100 * o.review_score.notna().mean(), 2))
b = v.dropna(subset=["review_score"]).copy(); b["delay bucket"] = pd.cut(b.delay_days, [-1e9, 0, 3, 7, 1e9], labels=["on time or early", "1-3 days late", "4-7 days late", "over 7 days late"])
fig, ax = plt.subplots(1, 2, figsize=(12, 3.8)); rv.round().astype(int).value_counts().sort_index().plot.bar(ax=ax[0], color=AMBER, title="Order-level review score")
b.groupby("delay bucket", observed=True).review_score.mean().plot.bar(ax=ax[1], color="#4A6F8A", ylim=(1, 5), title="Average score by delay"); plt.tight_layout(); plt.show()

# %% 15. Payments: type share by value and instalments
pay = t["order_payments"]; share = (100 * pay.groupby("payment_type").payment_value.sum() / pay.payment_value.sum()).round(1).sort_values(ascending=False); print(share.to_dict())
fig, ax = plt.subplots(1, 2, figsize=(12, 3.8)); share.plot.bar(ax=ax[0], color=TEAL, title="Share of payment value by type (%)"); pay[pay.payment_type == "credit_card"].payment_installments.value_counts().sort_index().plot.bar(ax=ax[1], color=AMBER, title="Credit-card instalments"); plt.tight_layout(); plt.show()

# %% 16. Geography: orders by state
s.groupby("customer_state").size().sort_values(ascending=False).plot.bar(color=TEAL, title="Valid orders by customer state"); plt.show()

# %% 17. Correlations between numeric measures (association only)
num = v[["delivery_days", "estimated_days", "item_sales", "freight", "n_items", "distance_km", "review_score"]].dropna()
corr = num.corr(); fig, ax = plt.subplots(figsize=(6.5, 5)); im = ax.imshow(corr, cmap="BrBG", vmin=-1, vmax=1); ax.set_xticks(range(len(corr)), corr.columns, rotation=45, ha="right"); ax.set_yticks(range(len(corr)), corr.columns)
for i in range(len(corr)):
    for j in range(len(corr)): ax.text(j, i, f"{corr.iloc[i, j]:.2f}", ha="center", va="center", fontsize=8)
plt.colorbar(im); plt.title("Correlation (delivered orders)"); plt.tight_layout(); plt.show()

# %% [markdown]
# ## What to write down
# Use only what the charts show. Delay and review score move together (association); the data cannot show why.
# Profit cannot be measured: the dataset has no cost data.
