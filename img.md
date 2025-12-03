``` txt#!/usr/bin/python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = r'''
---
module: json_to_postgres

short_description: Load JSON data from a file and insert/upsert into PostgreSQL

version_added: "1.0.0"

description: >
  Reads a JSON file (list of objects or single object) and inserts/updates rows
  in a PostgreSQL table using bulk insert. Keys of the JSON objects must match
  column names in the target table.

options:
  json_file:
    description: Path to the JSON file on the controller/host.
    required: true
    type: str
  table:
    description: Target PostgreSQL table name (schema-qualified if needed).
    required: true
    type: str
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
  upsert:
    description: Whether to perform an upsert (INSERT ... ON CONFLICT ...).
    required: false
    type: bool
    default: false
  key_column:
    description: >
      Column to use for ON CONFLICT when upsert=true (usually primary key).
    required: false
    type: str
  batch_size:
    description: Number of rows per batch for bulk insert.
    required: false
    type: int
    default: 5000

author:
  - "You"
'''

EXAMPLES = r'''
- name: Insert JSON data into devices table
  json_to_postgres:
    json_file: /tmp/devices.json
    table: public.devices
    pg_host: db.example.com
    pg_port: 5432
    pg_db: inventory
    pg_user: inv_user
    pg_password: secret
    upsert: true
    key_column: id
'''

RETURN = r'''
rows_processed:
  description: Number of rows successfully inserted/updated.
  type: int
  returned: always
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
    if not data:
        return []
    if not isinstance(data[0], dict):
        raise ValueError("JSON array must contain objects.")
    return data


def build_sql(table, columns, upsert, key_column):
    cols_sql = ", ".join('"%s"' % c for c in columns)
    placeholder = "%s"  # execute_values will build row placeholders

    if upsert:
        if not key_column:
            raise ValueError("key_column must be set when upsert=true")
        if key_column not in columns:
            raise ValueError("key_column '%s' not found in JSON columns" % key_column)

        update_assignments = []
        for col in columns:
            if col == key_column:
                continue
            update_assignments.append('"%s" = EXCLUDED."%s"' % (col, col))
        update_sql = ", ".join(update_assignments) or '"%s" = EXCLUDED."%s"' % (key_column, key_column)

        sql = (
            f'INSERT INTO {table} ({cols_sql}) VALUES %s '
            f'ON CONFLICT ("{key_column}") DO UPDATE SET {update_sql};'
        )
    else:
        sql = f'INSERT INTO {table} ({cols_sql}) VALUES %s;'

    return sql


def run_module():
    module_args = dict(
        json_file=dict(type='str', required=True),
        table=dict(type='str', required=True),
        pg_host=dict(type='str', required=True),
        pg_port=dict(type='int', required=False, default=5432),
        pg_db=dict(type='str', required=True),
        pg_user=dict(type='str', required=True),
        pg_password=dict(type='str', required=True, no_log=True),
        upsert=dict(type='bool', required=False, default=False),
        key_column=dict(type='str', required=False, default=None),
        batch_size=dict(type='int', required=False, default=5000),
    )

    result = dict(
        changed=False,
        rows_processed=0,
    )

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True
    )

    if not HAS_PSYCOPG2:
        module.fail_json(msg="psycopg2 is required for this module", **result)

    json_file = module.params["json_file"]
    table = module.params["table"]
    pg_host = module.params["pg_host"]
    pg_port = module.params["pg_port"]
    pg_db = module.params["pg_db"]
    pg_user = module.params["pg_user"]
    pg_password = module.params["pg_password"]
    upsert = module.params["upsert"]
    key_column = module.params["key_column"]
    batch_size = module.params["batch_size"]

    try:
        data = load_json(json_file)
    except Exception as e:
        module.fail_json(msg=f"Failed to load JSON: {e}", **result)

    if not data:
        module.exit_json(msg="JSON file is empty, nothing to do", **result)

    # Use keys from first object as columns
    columns = list(data[0].keys())

    # Build row tuples in the same column order
    rows = []
    for obj in data:
        # basic validation
        if not isinstance(obj, dict):
            module.fail_json(msg="All items in JSON array must be objects", **result)
        row = tuple(obj.get(col) for col in columns)
        rows.append(row)

    sql = None
    try:
        sql = build_sql(table, columns, upsert, key_column)
    except Exception as e:
        module.fail_json(msg=f"Failed to build SQL: {e}", **result)

    if module.check_mode:
        result["changed"] = False
        result["rows_processed"] = len(rows)
        module.exit_json(msg="Check mode - no changes made", **result)

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
        for i in range(0, len(rows), batch_size):
            batch = rows[i:i+batch_size]
            execute_values(cur, sql, batch)
            total += len(batch)

        conn.commit()
        cur.close()
        conn.close()

        result["rows_processed"] = total
        result["changed"] = total > 0
        module.exit_json(msg=f"Successfully processed {total} rows", **result)

    except Exception as e:
        module.fail_json(msg=f"Database error: {e}", **result)


def main():
    run_module()


if __name__ == '__main__':
    main()

```
