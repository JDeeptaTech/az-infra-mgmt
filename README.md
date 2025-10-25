# az-infra-mgmt

``` py
import streamlit as st
import psycopg2
import pandas as pd
from datetime import datetime, time

# -----------------------------
# ⚙️ PostgreSQL Connection Config
# -----------------------------
DB_CONFIG = {
    "host": "localhost",
    "port": "5432",
    "database": "mydb",
    "user": "postgres",
    "password": "password"
}

# -----------------------------
# 🔌 Connect to Database
# -----------------------------
@st.cache_resource
def get_connection():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        st.error(f"❌ Database connection failed: {e}")
        return None

# -----------------------------
# 🔍 Query Function
# -----------------------------
def query_data(search, start_dt, end_dt, limit, offset):
    query = """
        SELECT id, release_name, description, created_at
        FROM releases
        WHERE (release_name ILIKE %s OR description ILIKE %s)
          AND created_at BETWEEN %s AND %s
        ORDER BY created_at DESC
        LIMIT %s OFFSET %s
    """
    params = (f"%{search}%", f"%{search}%", start_dt, end_dt, limit, offset)

    conn = get_connection()
    if conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
            columns = [desc[0] for desc in cur.description]
        return pd.DataFrame(rows, columns=columns)
    return pd.DataFrame()

# -----------------------------
# 🔢 Count Function (for pagination)
# -----------------------------
def count_rows(search, start_dt, end_dt):
    query = """
        SELECT COUNT(*)
        FROM releases
        WHERE (release_name ILIKE %s OR description ILIKE %s)
          AND created_at BETWEEN %s AND %s
    """
    params = (f"%{search}%", f"%{search}%", start_dt, end_dt)
    conn = get_connection()
    if conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            total = cur.fetchone()[0]
        return total
    return 0

# -----------------------------
# 🎨 Streamlit UI
# -----------------------------
st.set_page_config(page_title="📦 Release Dashboard", layout="wide")
st.title("📦 Release Dashboard")

# Sidebar filters
with st.sidebar:
    st.header("🔍 Filters")

    search = st.text_input("Search text", "")
    
    st.markdown("### 📅 Date Range")
    start_date = st.date_input("Start date", datetime(2024, 1, 1))
    start_time = st.time_input("Start time", time(0, 0))
    end_date = st.date_input("End date", datetime.now().date())
    end_time = st.time_input("End time", time(23, 59))

    # Combine date and time into datetime objects
    start_dt = datetime.combine(start_date, start_time)
    end_dt = datetime.combine(end_date, end_time)

    rows_per_page = st.slider("Rows per page", 5, 50, 10)
    page = st.number_input("Page number", min_value=1, step=1)

# -----------------------------
# 📊 Query & Display Data
# -----------------------------
offset = (page - 1) * rows_per_page
df = query_data(search, start_dt, end_dt, rows_per_page, offset)
total = count_rows(search, start_dt, end_dt)
total_pages = (total // rows_per_page) + (1 if total % rows_per_page else 0)

if not df.empty:
    st.success(f"✅ Showing page {page} of {total_pages} — {total} total records")
    st.dataframe(df, use_container_width=True)
else:
    st.warning("No results found for the given filters.")

# -----------------------------
# 🧭 Pagination info
# -----------------------------
st.sidebar.info(f"Total records: {total}\nTotal pages: {total_pages}")

# -----------------------------
# 💾 Optional: Download results
# -----------------------------
if not df.empty:
    csv = df.to_csv(index=False)
    st.download_button(
        label="📥 Download current page as CSV",
        data=csv,
        file_name="releases_page.csv",
        mime="text/csv"
    )


```
