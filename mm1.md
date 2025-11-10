```py
import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
from db import run_query

st.set_page_config(page_title="Release Details", layout="wide")

st.title("🖥️ VM Lifecycle - Release Details")

# --- Sidebar Filters ---
st.sidebar.header("🔍 Filters")

# Text filters
vm_name = st.sidebar.text_input("VM Name (partial match)")
ip_addr = st.sidebar.text_input("IP Address")
correlation_id = st.sidebar.text_input("Correlation ID")
invocation_id = st.sidebar.text_input("Invocation ID")

# Lifecycle filter
lifecycle_filter = st.sidebar.multiselect(
    "Lifecycle Status",
    options=["Build_Success", "Build_Failed", "Demise_Success", "Demise_Failed", "Deploying"],
    default=["Build_Success", "Build_Failed"]
)

# Date range filter (lease or created_at)
default_start = datetime.now() - timedelta(days=30)
default_end = datetime.now()
start_date, end_date = st.sidebar.date_input(
    "Date range (Lease/Created)",
    [default_start, default_end],
)

refresh = st.sidebar.button("🔄 Refresh Data")

# --- Build SQL query dynamically ---
conditions = []
if vm_name:
    conditions.append(f"vm_name ILIKE '%{vm_name}%'")
if ip_addr:
    conditions.append(f"ip_address = '{ip_addr}'")
if correlation_id:
    conditions.append(f"correlation_id = '{correlation_id}'")
if invocation_id:
    conditions.append(f"invocation_id = '{invocation_id}'")

if lifecycle_filter:
    lifecycle_tuple = tuple(lifecycle_filter)
    conditions.append(f"lifecycle_status IN {lifecycle_tuple}")

if start_date and end_date:
    start_str = start_date[0].strftime("%Y-%m-%d")
    end_str = start_date[1].strftime("%Y-%m-%d") if isinstance(start_date, list) else end_date.strftime("%Y-%m-%d")
    conditions.append(f"(lease_start::date BETWEEN '{start_str}' AND '{end_str}' OR created_at::date BETWEEN '{start_str}' AND '{end_str}')")

where_clause = "WHERE " + " AND ".join(conditions) if conditions else ""

query = f"""
SELECT vm_id, vm_name, ip_address, cpu, memory, storage, lifecycle_status, status_reason,
environment, service_type, lease_start, lease_end, created_at, updated_at, deleted_at,
owner, requested_by, requested_for
FROM vm
{where_clause}
ORDER BY updated_at DESC
LIMIT 500;
"""

if refresh:
    st.cache_data.clear()

df = run_query(query)

# --- Display Data ---
if df.empty:
    st.warning("No records found for selected filters.")
else:
    st.success(f"Fetched {len(df)} records")

    # Metrics summary
    col1, col2, col3 = st.columns(3)
    col1.metric("Total VMs", len(df))
    col2.metric("Build Failed", (df["lifecycle_status"] == "Build_Failed").sum())
    col3.metric("Demise Failed", (df["lifecycle_status"] == "Demise_Failed").sum())

    # Table
    st.dataframe(df, use_container_width=True)

    # Chart summary (optional)
    st.subheader("📊 Lifecycle Distribution")
    st.bar_chart(df["lifecycle_status"].value_counts())


```
