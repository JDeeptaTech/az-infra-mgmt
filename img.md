``` txt#!/usr/bin/python
#!/usr/bin/python

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
---
module: pg_bulk_upsert

short_description: Bulk insert / upsert into PostgreSQL from JSON file or Ansible data

version_added: "1.0.0"

description: >
  Generic bulk insert/upsert module for PostgreSQL.
  Reads rows either from a JSON file on disk or from an Ansible list of dicts,
  builds a single INSERT ... [ON CONFLICT ...] SQL statement and executes it in batches
  using psycopg2.execute_values for efficiency.

options:
  table:
    description: Target PostgreSQL table (schema-qualified if needed).
    required: true
    type: str

  columns:
    description:
      - List of target column names in the table.
      - Order here determines the order of values sent to Postgres.
    required: false
    type: list
    elements: str

  column_map:
    description:
      - Optional mapping from target column name -> key in input row.
      - If omitted, the module assumes the JSON key and column name are identical.
      - Example: {cluster_name: name, cluster_id: id}
    required: false
    type: dict

  json_file:
    description:
      - Path to a JSON file containing a list of objects (or a single object).
      - Each object represents a row.
    required: false
    type: str

  rows:
    description:
      - List of dictionaries (from Ansible vars) representing rows.
      - Either rows or json_file must be provided.
    required: false
    type: list
    elements: dict

  pg_host:
    description: PostgreSQL host.
    required: true
    type: str

  pg_port:
    description: PostgreSQL port.
    required: false
    type: int
    default: 5432

  pg_db:
    description: PostgreSQL database name.
    required: true
    type: str

  pg_user:
    description: PostgreSQL user.
    required: true
    type: str

  pg_password:
    description: PostgreSQL password.
    required: true
    type: str
    no_log: true

  on_conflict:
    description:
      - What to do on conflict with existing rows.
      - C(none): plain INSERT, no ON CONFLICT clause.
      - C(nothing): ON CONFLICT (...) DO NOTHING.
      - C(update): ON CONFLICT (...) DO UPDATE SET ...
    required: false
    type: str
    choices: [none, nothing, update]
    default: none

  conflict_columns:
    description:
      - Columns that form the ON CONFLICT target.
      - Required when on_conflict is C(nothing) or C(update).
    required: false
    type: list
    elements: str

  update_columns:
    description:
      - Columns to update when on_conflict=update.
      - Default is all columns except the conflict_columns.
    required: false
    type: list
    elements: str

  extra_update_sql:
    description:
      - Extra SQL fragments appended to the SET list when on_conflict=update.
      - Example: C(last_sync = NOW()).
      - Do NOT include the word SET.
    required: false
    type: str
    default: ""

  returning_column:
    description:
      - Optional column name to RETURN from the INSERT/UPSERT (e.g. id).
      - When set, the module will return a list of values for that column.
    required: false
    type: str

  batch_size:
    description: Number of rows per batch when sending to PostgreSQL.
    required: false
    type: int
    default: 5000

author:
  - "You"
'''

EXAMPLES = r'''
- name: Bulk upsert cluster_cache from variable
  pg_bulk_upsert:
    table: cluster_cache
    rows: "{{ cluster_data_csv | selectattr('tags','defined') | selectattr('tags','ne',[]) | list }}"
    columns:
      - cluster_name
      - cluster_id
      - tags
      - datacenter_id
    column_map:
      cluster_name: name
      cluster_id: id
      tags: tags
      datacenter_id: datacenter_id
    pg_host: "{{ pg_host }}"
    pg_db: "{{ pg_db }}"
    pg_user: "{{ pg_user }}"
    pg_password: "{{ pg_password }}"
    on_conflict: update
    conflict_columns:
      - cluster_id
      - datacenter_id
    update_columns:
      - tags
    extra_update_sql: "last_sync = NOW()"
    returning_column: id
'''

RETURN = r'''
rows_processed:
  description: Number of rows processed (attempted inserts).
  type: int
  returned: always

returned_values:
  description:
    - List of values returned from RETURNING clause (if returning_column is set).
  type: list
  elements: raw
  returned: when supported
'''

from ansible.module_utils.basic import AnsibleModule

import json
import os

try:
    import psycopg2
    from psycopg2.extras import execute_values
    HAS_PSYCOPG2 = True
except ImportError:
    HAS_PSYCOPG2 = False


def load_json(path):
    if not os.path.exists(path):
        raise FileNotFoundError("JSON file not found: %s" % path)
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        raise ValueError("JSON root must be an object or an array of objects.")
    return data


def build_sql(table, columns, on_conflict, conflict_columns,
              update_columns, extra_update_sql, returning_column):
    # quoted column list
    cols_sql = ", ".join(f'"{c}"' for c in columns)

    sql = f'INSERT INTO {table} ({cols_sql}) VALUES %s'

    if on_conflict != "none":
        if not conflict_columns:
            raise ValueError("conflict_columns must be set when on_conflict != 'none'")
        conflict_sql = ", ".join(f'"{c}"' for c in conflict_columns)
        if on_conflict == "nothing":
            sql += f' ON CONFLICT ({conflict_sql}) DO NOTHING'
        elif on_conflict == "update":
            if not update_columns:
                # default: all non-conflict columns
                update_columns = [c for c in columns if c not in conflict_columns]
            assignments = [f'"{c}" = EXCLUDED."{c}"' for c in update_columns]
            if extra_update_sql:
                assignments.append(extra_update_sql)
            assign_sql = ", ".join(assignments)
            sql += f' ON CONFLICT ({conflict_sql}) DO UPDATE SET {assign_sql}'

    if returning_column:
        sql += f' RETURNING "{returning_column}"'

    sql += ';'
    return sql


def build_rows(input_rows, columns, column_map):
    """Return list of tuples in column order"""
    rows = []
    for obj in input_rows:
        if not isinstance(obj, dict):
            raise ValueError("Each row must be a dict")
        row = []
        for col in columns:
            src_key = column_map.get(col, col) if column_map else col
            row.append(obj.get(src_key))
        rows.append(tuple(row))
    return rows


def run_module():
    module_args = dict(
        table=dict(type='str', required=True),
        columns=dict(type='list', elements='str', required=False, default=None),
        column_map=dict(type='dict', required=False, default=None),
        json_file=dict(type='str', required=False, default=None),
        rows=dict(type='list', elements='dict', required=False, default=None),

        pg_host=dict(type='str', required=True),
        pg_port=dict(type='int', required=False, default=5432),
        pg_db=dict(type='str', required=True),
        pg_user=dict(type='str', required=True),
        pg_password=dict(type='str', required=True, no_log=True),

        on_conflict=dict(type='str',
                         choices=['none', 'nothing', 'update'],
                         default='none'),
        conflict_columns=dict(type='list', elements='str', required=False, default=None),
        update_columns=dict(type='list', elements='str', required=False, default=None),
        extra_update_sql=dict(type='str', required=False, default=""),
        returning_column=dict(type='str', required=False, default=None),
        batch_size=dict(type='int', required=False, default=5000),
    )

    result = dict(
        changed=False,
        rows_processed=0,
        returned_values=[],
    )

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True
    )

    if not HAS_PSYCOPG2:
        module.fail_json(msg="psycopg2 is required for this module", **result)

    params = module.params

    table = params["table"]
    columns = params["columns"]
    column_map = params["column_map"]
    json_file = params["json_file"]
    rows_param = params["rows"]

    pg_host = params["pg_host"]
    pg_port = params["pg_port"]
    pg_db = params["pg_db"]
    pg_user = params["pg_user"]
    pg_password = params["pg_password"]

    on_conflict = params["on_conflict"]
    conflict_columns = params["conflict_columns"]
    update_columns = params["update_columns"]
    extra_update_sql = params["extra_update_sql"]
    returning_column = params["returning_column"]
    batch_size = params["batch_size"]

    # load data
    if rows_param is not None:
        input_rows = rows_param
    elif json_file:
        try:
            input_rows = load_json(json_file)
        except Exception as e:
            module.fail_json(msg=f"Failed to load JSON: {e}", **result)
    else:
        module.fail_json(msg="Either 'rows' or 'json_file' must be provided", **result)

    if not input_rows:
        module.exit_json(msg="No rows to process", **result)

    # determine columns if not provided
    if columns is None:
        if not isinstance(input_rows[0], dict):
            module.fail_json(msg="First row is not a dict and no 'columns' were provided", **result)
        columns = list(input_rows[0].keys())

    try:
        values_rows = build_rows(input_rows, columns, column_map)
    except Exception as e:
        module.fail_json(msg=f"Failed to build row data: {e}", **result)

    try:
        sql = build_sql(table, columns, on_conflict,
                        conflict_columns, update_columns,
                        extra_update_sql, returning_column)
    except Exception as e:
        module.fail_json(msg=f"Failed to build SQL: {e}", **result)

    # Check mode – we don't hit DB
    if module.check_mode:
        result["rows_processed"] = len(values_rows)
        module.exit_json(msg="Check mode - SQL not executed", **result)

    try:
        conn = psycopg2.connect(
            host=pg_host,
            port=pg_port,
            dbname=pg_db,
            user=pg_user,
            password=pg_password,
        )
        cur = conn.cursor()

        total = 0
        returned_values = []

        if returning_column:
            # need fetch=True to get returned values from execute_values
            for i in range(0, len(values_rows), batch_size):
                batch = values_rows[i:i + batch_size]
                rows_ret = execute_values(cur, sql, batch, fetch=True)
                total += len(batch)
                # rows_ret is list of tuples, one column each
                returned_values.extend([r[0] for r in rows_ret])
        else:
            for i in range(0, len(values_rows), batch_size):
                batch = values_rows[i:i + batch_size]
                execute_values(cur, sql, batch)
                total += len(batch)

        conn.commit()
        cur.close()
        conn.close()

        result["rows_processed"] = total
        result["changed"] = total > 0
        result["returned_values"] = returned_values
        module.exit_json(msg=f"Successfully processed {total} rows", **result)

    except Exception as e:
        module.fail_json(msg=f"Database error: {e}", **result)


def main():
    run_module()


if __name__ == "__main__":
    main()


```
