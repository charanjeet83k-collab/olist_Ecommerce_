"""
Olist E-Commerce Dashboard - Streamlit version of the Power BI report.
Pages: Home, Executive Sales Overview, Sales & Products, Customer and Reviews,
       Delivery and Logistics, Payment & Geography.
Measure logic mirrors the DAX in the .pbix file (see README.md for details).
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from plotly.subplots import make_subplots

st.set_page_config(page_title="Olist E-Commerce Dashboard", page_icon="🛒", layout="wide")
BASE = Path(__file__).parent
DATA = BASE / "data" if (BASE / "data").exists() else BASE

# ---- Theme (taken from the Power BI theme "Olist Teal Light") ----
TEAL, AMBER, GREY, LTEAL, RED = "#348E90", "#D98E1F", "#6B6B6B", "#7FC1C2", "#B84A3E"
PALETTE = ["#348E90", "#D98E1F", "#6B6B6B", "#7FC1C2", "#B84A3E", "#262626",
           "#A9D3D4", "#F0C27A", "#3599B8", "#DFBFBF", "#4AC5BB", "#5F6B6D"]
HEADER = "#1F4E79"
BG = "#EEF2F6"
CARD_BORDER, CARD_LABEL, CARD_VALUE = "#D5DEE6", "#07566B", "#123B46"

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
PAGES = ["Home", "Executive Sales Overview", "Sales & Products",
         "Customer and Reviews", "Delivery and Logistics", "Payment & Geography"]

st.markdown(f"""
<style>
.stApp {{ background-color: {BG}; }}
.block-container {{ padding-top: 1rem; padding-bottom: 1rem; max-width: 1500px; }}
header[data-testid="stHeader"] {{ background: transparent; }}
.topbar {{ background:{HEADER}; color:white; padding:14px 22px; border-radius:6px;
          font-size:24px; font-weight:700; margin-bottom:10px; }}
.kpi {{ background:white; border:1px solid {CARD_BORDER}; border-radius:8px; padding:10px 14px;
        text-align:center; height:92px; }}
.kpi .l {{ color:{CARD_LABEL}; font-size:13px; font-weight:600; }}
.kpi .v {{ color:{CARD_VALUE}; font-size:28px; font-weight:700; line-height:1.4; }}
.home-title {{ text-align:center; color:{HEADER}; font-size:38px; font-weight:800; margin:30px 0 40px 0; }}
div[data-testid="stVerticalBlockBorderWrapper"] {{ background:white; }}
</style>
""", unsafe_allow_html=True)


# ------------------------------------------------------------------ data
def _clean(df: pd.DataFrame) -> pd.DataFrame:
    for c in df.columns:
        dt = df[c].dtype
        if pd.api.types.is_datetime64_any_dtype(dt):
            continue
        if pd.api.types.is_numeric_dtype(dt):
            df[c] = df[c].astype("float64")
        else:
            df[c] = df[c].astype(object).where(df[c].notna(), None)
    return df


@st.cache_data(show_spinner="Loading data...")
def load():
    o = _clean(pd.read_parquet(DATA / "orders.parquet"))
    oi = _clean(pd.read_parquet(DATA / "order_items.parquet"))
    p = _clean(pd.read_parquet(DATA / "payments.parquet"))
    meta = json.load(open(DATA / "meta.json"))
    geo = json.load(open(DATA / "brazil_states.geojson"))

    # Date_Table link (Year / Month / Year-Month) on purchase_date
    o["year"] = o["purchase_date"].dt.year.astype("float64")
    o["month_num"] = o["purchase_date"].dt.month.astype("float64")
    o["month"] = o["purchase_date"].dt.month.map(lambda m: MONTHS[int(m) - 1] if pd.notna(m) else None)
    o["ym"] = o["purchase_date"].dt.strftime("%Y-%m")

    # relationships: orders (1) -> order_items (M), orders (1) -> payments (M)
    oi = oi.merge(o[["order_id", "is_sales_order", "customer_state"]], on="order_id", how="left")
    p = p.merge(o[["order_id", "customer_state"]], on="order_id", how="left")
    return o, oi, p, meta, geo


orders, items, pays, META, GEO = load()


# ------------------------------------------------------------------ filter context
def ctx(years=None, months=None, o_f=None, oi_f=None, pay_types=None,
        price_rng=None, year_rng=None, score_rng=None):
    """Reproduces Power BI filter propagation.
    orders filters flow down to order_items and payments.
    order_items / payments filters do NOT flow back to orders."""
    O = orders
    if years:
        O = O[O["year"].isin(years)]
    if year_rng:
        O = O[O["year"].between(year_rng[0], year_rng[1])]
    if months:
        O = O[O["month"].isin(months)]
    if score_rng and tuple(score_rng) != (1, 5):
        O = O[O["Score_Rounded"].between(score_rng[0], score_rng[1])]
    for col, vals in (o_f or {}).items():
        if vals:
            O = O[O[col].isin(vals)]
    narrowed = len(O) != len(orders)

    OI = items[items["order_id"].isin(O["order_id"])] if narrowed else items
    for col, vals in (oi_f or {}).items():
        if vals:
            OI = OI[OI[col].isin(vals)]
    if price_rng and (price_rng[0] > items["price"].min() or price_rng[1] < items["price"].max()):
        OI = OI[OI["price"].between(price_rng[0], price_rng[1])]

    P = pays[pays["order_id"].isin(O["order_id"])] if narrowed else pays
    if pay_types:
        P = P[P["payment_type"].isin(pay_types)]
    return O, OI, P


# ------------------------------------------------------------------ measures (DAX equivalents)
def sales_orders(O):            return O[O["is_sales_order"] == 1]
def m_orders_valid(O):          return sales_orders(O)["order_id"].nunique()
def m_item_sales(OI):           return OI.loc[OI["is_sales_order"] == 1, "price"].sum()
def m_freight(OI):              return OI.loc[OI["is_sales_order"] == 1, "freight_value"].sum()
def m_items_sold(OI):           return int((OI["is_sales_order"] == 1).sum())
def m_active_sellers(OI):       return OI.loc[OI["is_sales_order"] == 1, "seller_id"].nunique()
def m_unique_customers(O):      return O["customer_unique_id"].nunique()
def m_avg_review(O):            return O["review_score"].mean()
def m_pct_45(O):
    r = O["review_score"].dropna();  return (r >= 4).sum() / len(r) if len(r) else np.nan
def m_pct_12(O):
    r = O["review_score"].dropna();  return (r <= 2).sum() / len(r) if len(r) else np.nan
def m_repeat_rate(O):
    n = O.groupby("customer_unique_id")["order_id"].nunique()
    return (n > 1).sum() / len(n) if len(n) else np.nan
def m_valid_delivered(O):       return int((O["valid_delivery"] == 1).sum())
def m_avg_delivery(O):          return O.loc[O["valid_delivery"] == 1, "delivery_days"].mean()
def m_avg_estimated(O):         return O.loc[O["valid_delivery"] == 1, "estimated_days"].mean()
def m_late_pct(O):
    v = m_valid_delivered(O)
    return (O["is_late"] == 1).sum() / v if v else np.nan
def m_avg_delay_late(O):        return O.loc[O["is_late"] == 1, "delay_days"].mean()


# ------------------------------------------------------------------ formatting / UI helpers
def compact(v, prefix=""):
    if v is None or pd.isna(v):
        return "-"
    a = abs(v)
    if a >= 1e6:  return f"{prefix}{v/1e6:.2f}M"
    if a >= 1e3:  return f"{prefix}{v/1e3:.2f}K"
    return f"{prefix}{v:,.2f}" if isinstance(v, float) and v != int(v) else f"{prefix}{int(v):,}"

def pct(v):   return "-" if v is None or pd.isna(v) else f"{v*100:.2f}%"
def num2(v):  return "-" if v is None or pd.isna(v) else f"{v:,.2f}"

def kpi_row(items_):
    cols = st.columns(len(items_))
    for c, (label, value) in zip(cols, items_):
        c.markdown(f'<div class="kpi"><div class="l">{label}</div><div class="v">{value}</div></div>',
                   unsafe_allow_html=True)

def style(fig, title, h=300, legend=False):
    fig.update_layout(
        title=dict(text=title, x=0.01, font=dict(size=14, color=CARD_VALUE)),
        height=h, margin=dict(l=10, r=10, t=45, b=10),
        paper_bgcolor="white", plot_bgcolor="white", showlegend=legend,
        font=dict(color="#333"),
        legend=dict(orientation="h", y=-0.2),
    )
    fig.update_xaxes(showgrid=False)
    fig.update_yaxes(gridcolor="#E8ECEF")
    return fig

def show(fig):
    st.plotly_chart(fig, width="stretch", config={"displaylogo": False})

def goto(p):
    st.session_state["page"] = p

def topbar(title):
    st.markdown(f'<div class="topbar">{title}</div>', unsafe_allow_html=True)
    i = PAGES.index(st.session_state["page"])
    spacer, a, b, c = st.columns([6, 1, 1, 1])
    if i > 1:
        a.button("‹  Previous", key=f"prev{i}", on_click=goto, args=(PAGES[i - 1],), width="stretch")
    c.button("Home", key=f"home{i}", on_click=goto, args=("Home",), width="stretch")
    if i < len(PAGES) - 1:
        b.button("Next  ›", key=f"next{i}", on_click=goto, args=(PAGES[i + 1],), width="stretch")

def opts(series):
    return sorted(series.dropna().unique().tolist())

YEARS = [2016, 2017, 2018]


# ================================================================== HOME
def page_home():
    st.markdown('<div class="home-title">Brazilian E-Commerce Sales &amp; Customer Insights</div>',
                unsafe_allow_html=True)
    cols = st.columns(5)
    labels = ["Executive Sales Overview", "Sales & Product", "Customer and Reviews",
              "Delivery and Logistics", "Payment & Geography"]
    for c, lab, pg in zip(cols, labels, PAGES[1:]):
        with c:
            st.button(lab, key=f"h_{pg}", on_click=goto, args=(pg,), width="stretch")
    st.caption("Source: Olist Brazilian e-commerce dataset (orders 2016-09 to 2018-10).")


# ================================================================== EXECUTIVE
def page_exec():
    topbar("Executive Overview")
    left, main = st.columns([1, 6])
    with left:
        mo = st.multiselect("Month", MONTHS, key="ex_m")
        yr = st.multiselect("Year", YEARS, key="ex_y")
        stt = st.multiselect("Customer state", opts(orders["customer_state"]), key="ex_s")
        sts = st.multiselect("Order status", opts(orders["order_status"]), key="ex_os")
        cat = st.multiselect("Category", opts(items["category"]), key="ex_c")
    O, OI, _ = ctx(yr, mo, {"customer_state": stt, "order_status": sts}, {"category": cat})

    kpi_row([("Item Sales", compact(m_item_sales(OI))),
             ("Orders (valid)", f"{m_orders_valid(O):,}"),
             ("Unique Customers", f"{m_unique_customers(O):,}"),
             ("Active Sellers", f"{m_active_sellers(OI):,}"),
             ("Avg Review Score", num2(m_avg_review(O)))])

    with main:
        pass
    with main:
        c1, c2 = st.columns([2, 1])
        with c1:
            with st.container(border=True):
                g = O.groupby(["month_num", "month"]).apply(
                    lambda d: pd.Series({"orders": m_orders_valid(d), "sales": d["item_sales"].sum()}),
                    include_groups=False).reset_index().sort_values("month_num")
                fig = make_subplots(specs=[[{"secondary_y": True}]])
                fig.add_bar(x=g["month"], y=g["orders"], name="Orders (valid)", marker_color=TEAL)
                fig.add_scatter(x=g["month"], y=g["sales"], name="Item Sales", mode="lines+markers",
                                line=dict(color=AMBER, width=3), secondary_y=True)
                style(fig, "Monthly Orders and Item Sales Trend", 300, legend=True)
                show(fig)
        with c2:
            with st.container(border=True):
                t = OI.groupby("category")["price"].sum().nlargest(10).iloc[::-1]
                fig = go.Figure(go.Bar(x=t.values, y=t.index, orientation="h", marker_color=TEAL))
                show(style(fig, "Top 10 Categories by Sales Value", 300))
        c3, c4 = st.columns([2, 1])
        with c3:
            with st.container(border=True):
                a = sales_orders(O).groupby("customer_state")["order_id"].nunique()
                d = OI[OI["is_sales_order"] == 1].groupby("customer_state")["order_id"].nunique()
                t = a.sort_values(ascending=False)
                fig = go.Figure(go.Bar(x=t.index, y=t.values, marker_color=TEAL,
                                       customdata=d.reindex(t.index).fillna(0).values,
                                       hovertemplate="%{x}<br>Orders (valid): %{y:,}<br>Delivered orders: %{customdata:,}<extra></extra>"))
                show(style(fig, "Orders Placed by Customer State", 300))
        with c4:
            with st.container(border=True):
                t = O["order_status"].value_counts()
                fig = go.Figure(go.Pie(labels=t.index, values=t.values, hole=0.55,
                                       marker=dict(colors=PALETTE), textinfo="percent"))
                show(style(fig, "Share of Orders by Status", 300, legend=True))


# ================================================================== SALES & PRODUCTS
def page_sales():
    topbar("Sales &amp; Customer Insights")
    left, main = st.columns([1, 6])
    with left:
        yr = st.multiselect("Year", YEARS, key="sp_y")
        mo = st.multiselect("Month", MONTHS, key="sp_m")
        cat = st.multiselect("Category", opts(items["category"]), key="sp_c")
        ss = st.multiselect("Seller state", opts(items["seller_state"]), key="sp_ss")
        sid = st.multiselect("Seller id", opts(items["seller_id"]), key="sp_sid")
        pmin, pmax = float(items["price"].min()), float(items["price"].max())
        pr = st.slider("Price", pmin, pmax, (pmin, pmax), key="sp_p")
    O, OI, _ = ctx(yr, mo, None, {"category": cat, "seller_state": ss, "seller_id": sid}, price_rng=pr)

    sales, n_items = m_item_sales(OI), m_items_sold(OI)
    kpi_row([("Item Sales", compact(sales)),
             ("Items Sold", f"{n_items:,}"),
             ("Avg Item Price", num2(sales / n_items if n_items else np.nan)),
             ("Avg Freight per Item", num2(m_freight(OI) / n_items if n_items else np.nan)),
             ("Freight Share of Item Sales", pct(m_freight(OI) / sales if sales else np.nan))])

    with main:
        c1, c2 = st.columns([1, 1])
        with c1:
            with st.container(border=True):
                top = OI.groupby("category")["price"].sum().nlargest(10).index      # ranked by Total_item_sales
                t = OI[OI["is_sales_order"] == 1].groupby("category")["price"].sum().reindex(top).fillna(0).iloc[::-1]
                fig = go.Figure(go.Bar(x=t.values, y=t.index, orientation="h", marker_color=TEAL))
                show(style(fig, "Top 10 Categories by Item Sales", 300))
        with c2:
            with st.container(border=True):
                t = OI.groupby("category")["price"].sum()
                t = t[t > 0].reset_index()
                fig = px.treemap(t, path=["category"], values="price", color_discrete_sequence=PALETTE)
                fig.update_traces(marker=dict(colors=None), textinfo="label+percent root")
                show(style(fig, "Which Categories Drive Item Sales", 300))
        c3, c4 = st.columns([1, 1])
        with c3:
            with st.container(border=True):
                t = OI.groupby("seller_id")["price"].sum().nlargest(10)
                fig = go.Figure(go.Bar(x=[s[:8] + "…" for s in t.index], y=t.values, marker_color=TEAL,
                                       customdata=t.index,
                                       hovertemplate="%{customdata}<br>%{y:,.2f}<extra></extra>"))
                show(style(fig, "Top 10 Sellers by Item Sales", 300))
        with c4:
            with st.container(border=True):
                g = O.groupby(["year", "month_num", "month"])["item_sales"].sum().reset_index().sort_values("month_num")
                fig = go.Figure()
                for i, (y, d) in enumerate(g.groupby("year")):
                    fig.add_scatter(x=d["month"], y=d["item_sales"], mode="lines+markers",
                                    name=str(int(y)), line=dict(color=PALETTE[i % len(PALETTE)], width=3))
                fig.update_xaxes(categoryorder="array", categoryarray=MONTHS)
                show(style(fig, "Monthly Item Sales: Year-on-Year", 300, legend=True))


# ================================================================== CUSTOMER & REVIEWS
def page_customer():
    topbar("Customer and Reviews Insights")
    left, main = st.columns([1, 6])
    with left:
        mo = st.multiselect("Month", MONTHS, key="cu_m")
        yr = st.multiselect("Year", YEARS, key="cu_y")
        stt = st.multiselect("Customer state", opts(orders["customer_state"]), key="cu_s")
        cat = st.multiselect("First item category", opts(orders["first_item_category"]), key="cu_c")
        sc = st.slider("Review score (rounded)", 1, 5, (1, 5), key="cu_sc")
    O, OI, _ = ctx(yr, mo, {"customer_state": stt, "first_item_category": cat}, score_rng=sc)

    kpi_row([("Unique Customers", f"{m_unique_customers(O):,}"),
             ("Repeat Customer Rate", pct(m_repeat_rate(O))),
             ("Avg Review Score", num2(m_avg_review(O))),
             ("% 4-5 Star", pct(m_pct_45(O))),
             ("% 1-2 Star", pct(m_pct_12(O)))])

    with main:
        c1, c2 = st.columns([1, 1.2])
        with c1:
            with st.container(border=True):
                t = O["Score_Rounded"].value_counts(dropna=False)
                lab = [("Blank" if pd.isna(i) else str(int(i))) for i in t.index]
                df = pd.DataFrame({"s": lab, "n": t.values, "k": [99 if pd.isna(i) else i for i in t.index]}).sort_values("k")
                fig = go.Figure(go.Bar(x=df["s"], y=df["n"], marker_color=TEAL))
                show(style(fig, "How Customers Rate Their Orders (1-5 Stars)", 300))
        with c2:
            with st.container(border=True):
                t = O.groupby("ym")["review_score"].mean().dropna()
                fig = go.Figure(go.Scatter(x=t.index, y=t.values, mode="lines+markers",
                                           line=dict(color=TEAL, width=3)))
                fig.update_yaxes(range=[max(0, t.min() - 0.2) if len(t) else 0, 5])
                show(style(fig, "Average Review Score Trend by Month", 300))
        c3, c4 = st.columns([2, 1])
        with c3:
            with st.container(border=True):
                t = O.groupby("customer_state")["customer_unique_id"].nunique().sort_values(ascending=False)
                fig = go.Figure(go.Bar(x=t.index, y=t.values, marker_color=TEAL))
                show(style(fig, "Customer Base by State", 300))
        with c4:
            with st.container(border=True):
                n = META["customer_count"]
                fig = go.Figure(go.Pie(labels=["Customers"], values=[n], hole=0.6,
                                       marker=dict(colors=[TEAL]), textinfo="none"))
                fig.add_annotation(text=f"<b>{n:,}</b>", showarrow=False, font=dict(size=24, color=CARD_VALUE))
                show(style(fig, "Customer Count", 300))


# ================================================================== DELIVERY
def page_delivery():
    topbar("Delivery and Logistics")
    left, main = st.columns([1, 6])
    with left:
        yr = st.slider("Year", 2016, 2018, (2016, 2018), key="de_y")
        mo = st.multiselect("Month", MONTHS, key="de_m")
        cat = st.multiselect("First item category", opts(orders["first_item_category"]), key="de_c")
        stt = st.multiselect("Customer state", opts(orders["customer_state"]), key="de_s")
        sst = st.multiselect("First seller state", opts(orders["first_seller_state"]), key="de_ss")
    O, _, _ = ctx(None, mo, {"first_item_category": cat, "customer_state": stt, "first_seller_state": sst},
                  year_rng=yr)

    kpi_row([("Avg Delivery Days", num2(m_avg_delivery(O))),
             ("Avg Estimated Days", num2(m_avg_estimated(O))),
             ("On-time Delivery %", pct(1 - m_late_pct(O) if pd.notna(m_late_pct(O)) else np.nan)),
             ("Late Delivery %", pct(m_late_pct(O))),
             ("Avg Delay (late orders)", num2(m_avg_delay_late(O)))])

    V = O[O["valid_delivery"] == 1]
    with main:
        c1, c2 = st.columns([2, 1])
        with c1:
            with st.container(border=True):
                t = V.groupby("customer_state")["delivery_days"].mean().sort_values(ascending=False)
                fig = go.Figure(go.Bar(x=t.index, y=t.values, marker_color=TEAL))
                show(style(fig, "Average Delivery Time by State (Days)", 300))
        with c2:
            with st.container(border=True):
                t = O[O["Delay Bucket"] != "n/a"].groupby("Delay Bucket")["review_score"].mean().sort_index()
                fig = go.Figure(go.Bar(x=[s[2:] for s in t.index], y=t.values, marker_color=TEAL))
                show(style(fig, "How Delivery Delay Hurts Review Scores", 300))
        c3, c4 = st.columns([1, 1])
        with c3:
            with st.container(border=True):
                late = O[O["is_late"] == 1].groupby("ym").size()
                valid = V.groupby("ym").size()
                t = (late.reindex(valid.index).fillna(0) / valid).dropna()
                fig = go.Figure(go.Scatter(x=t.index, y=t.values, mode="lines+markers",
                                           line=dict(color=RED, width=3)))
                fig.update_yaxes(tickformat=".0%")
                show(style(fig, "Late Delivery Rate by Month", 300))
        with c4:
            with st.container(border=True):
                t = V.groupby("ym")[["delivery_days", "estimated_days"]].mean()
                fig = go.Figure()
                fig.add_bar(x=t.index, y=t["delivery_days"], name="Avg Delivery Days", marker_color=TEAL)
                fig.add_bar(x=t.index, y=t["estimated_days"], name="Avg Estimated Days", marker_color=AMBER)
                fig.update_layout(barmode="group")
                show(style(fig, "Promised vs Actual Delivery Days by Month", 300, legend=True))


# ================================================================== PAYMENT & GEOGRAPHY
def page_payment():
    topbar("Payment &amp; Geography Insights")
    left, main = st.columns([1, 6])
    with left:
        yr = st.multiselect("Year", YEARS, key="pa_y")
        mo = st.multiselect("Month", MONTHS, key="pa_m")
        cat = st.multiselect("First item category", opts(orders["first_item_category"]), key="pa_c")
        stt = st.multiselect("Customer state", opts(orders["customer_state"]), key="pa_s")
        pt = st.multiselect("Payment type", opts(pays["payment_type"]), key="pa_t")
    O, _, P = ctx(yr, mo, {"first_item_category": cat, "customer_state": stt}, pay_types=pt)

    total = P["payment_value"].sum()
    cc = P.loc[P["payment_type"] == "credit_card", "payment_value"].sum()
    kpi_row([("Payment Total", compact(total)),
             ("Avg Payment per Order", num2(total / P["order_id"].nunique() if len(P) else np.nan)),
             ("Credit Card Share of Payment Value", pct(cc / total if total else np.nan)),
             ("Avg Instalments", num2(P["payment_installments"].mean())),
             ("Cities Served", f"{O['customer_city'].nunique():,}")])

    with main:
        c1, c2 = st.columns([1, 1])
        with c1:
            with st.container(border=True):
                t = P.groupby("payment_type")["payment_value"].sum().sort_values(ascending=False)
                fig = go.Figure(go.Pie(labels=t.index, values=t.values, hole=0.55,
                                       marker=dict(colors=PALETTE), textinfo="percent"))
                show(style(fig, "Payment Method Mix", 300, legend=True))
        with c2:
            with st.container(border=True):
                t = P.groupby("payment_installments")["order_id"].count().sort_index()
                fig = go.Figure(go.Bar(x=t.index.astype(int).astype(str), y=t.values, marker_color=TEAL))
                show(style(fig, "Credit Card Instalments Chosen", 300))
        c3, c4 = st.columns([1, 1])
        with c3:
            with st.container(border=True):
                t = P.groupby("customer_state")["payment_value"].sum().reset_index()
                fig = px.choropleth(t, geojson=GEO, locations="customer_state", featureidkey="properties.sigla",
                                    color="payment_value", color_continuous_scale=["#D6ECEC", TEAL, "#123B46"])
                fig.update_geos(fitbounds="locations", visible=False)
                fig.update_coloraxes(colorbar=dict(title="", thickness=10))
                show(style(fig, "Payment Value by State", 300))
        with c4:
            with st.container(border=True):
                t = sales_orders(O).groupby("customer_city")["order_id"].nunique().nlargest(10).iloc[::-1]
                fig = go.Figure(go.Bar(x=t.values, y=t.index, orientation="h", marker_color=TEAL))
                show(style(fig, "Top 10 Cities by Orders", 300))


# ------------------------------------------------------------------ router
if "page" not in st.session_state:
    st.session_state["page"] = "Home"

{"Home": page_home,
 "Executive Sales Overview": page_exec,
 "Sales & Products": page_sales,
 "Customer and Reviews": page_customer,
 "Delivery and Logistics": page_delivery,
 "Payment & Geography": page_payment}[st.session_state["page"]]()
