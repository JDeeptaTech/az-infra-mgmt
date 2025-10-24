variable "vsphere_user" {}
variable "vsphere_password" {}
variable "vsphere_server" {}

variable "datacenter" {}
variable "cluster" {}
variable "datastore" {}
variable "template" {}
variable "vm_name" {}
variable "network" {}

variable "static_ip" {}
variable "gateway" {}
variable "netmask" {}
variable "dns_servers" {
  type = list(string)
}


import streamlit as st
import pandas as pd
from sqlalchemy import create_engine, text
from datetime import datetime

# -----------------------------
# 🔧 Database Connection
# -----------------------------
# Example: postgresql://username:password@hostname:port/dbname
DB_URL = st.secrets.get("DB_URL", "postgresql://postgres:password@localhost:5432/mydb")
engine = create_engine(DB_URL)

# -----------------------------
# 🎛️ Streamlit UI
# -----------------------------
st.set_page_config(page_title="Release Details Dashboard", layout="wide")

st.title("📦 Release Details Dashboard")

# Sidebar filters
with st.sidebar:
    st.header("🔍 Filters")

    search = st.text_input("Search (in release name or description):", "")
    start_date = st.date_input("Start date", datetime(2024, 1, 1))
    end_date = st.date_input("End date", datetime.now().date())
    rows_per_page = st.slider("Rows per page", 5, 50, 10)
    page = st.number_input("Page number", min_value=1, step=1)

# -----------------------------
# 📥 Query Data
# -----------------------------
def load_data(search, start_date, end_date, limit, offset):
    query = text("""
        SELECT id, release_name, description, created_at
        FROM releases
        WHERE 
            (release_name ILIKE :search OR description ILIKE :search)
            AND created_at BETWEEN :start_date AND :end_date
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """)

    with engine.connect() as conn:
        df = pd.read_sql_query(
            query,
            conn,
            params={
                "search": f"%{search}%",
                "start_date": start_date,
                "end_date": end_date,
                "limit": limit,
                "offset": offset
            }
        )
    return df

offset = (page - 1) * rows_per_page
df = load_data(search, start_date, end_date, rows_per_page, offset)

# -----------------------------
# 📊 Display Results
# -----------------------------
if not df.empty:
    st.write(f"Showing results for **page {page}** with filter: `{search}`")
    st.dataframe(df, use_container_width=True)
else:
    st.warning("No results found for the given filters.")

# -----------------------------
# 🧭 Pagination
# -----------------------------
# Count total rows (for pagination info)
with engine.connect() as conn:
    total = conn.execute(text("""
        SELECT COUNT(*) 
        FROM releases 
        WHERE 
            (release_name ILIKE :search OR description ILIKE :search)
            AND created_at BETWEEN :start_date AND :end_date
    """), {"search": f"%{search}%", "start_date": start_date, "end_date": end_date}).scalar()

total_pages = (total // rows_per_page) + (1 if total % rows_per_page else 0)
st.sidebar.info(f"Total records: {total} | Pages: {total_pages}")
