```yml
# k8s-manifests.yaml

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: default # Must match the namespace used in the Vault role
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-vault-app
  labels:
    app: fastapi-vault-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fastapi-vault-app
  template:
    metadata:
      labels:
        app: fastapi-vault-app
      annotations:
        # Enable the Vault Agent Injector for this pod
        vault.hashicorp.com/agent-inject: "true"
        # Specify the Vault role to use for authentication
        vault.hashicorp.com/role: "my-app-role"
        # Inject 'db_connection_string' from Vault secret/data/my-app/config into env var DB_CONNECTION_STRING
        vault.hashicorp.com/agent-inject-env-DB_CONNECTION_STRING: "secret/data/my-app/config#db_connection_string"
        # Inject 'api_key' from Vault secret/data/my-app/config into env var API_KEY
        vault.hashicorp.com/agent-inject-env-API_KEY: "secret/data/my-app/config#api_key"
        # Inject 'application_name' from Vault secret/data/my-app/config into env var APPLICATION_NAME
        vault.hashicorp.com/agent-inject-env-APPLICATION_NAME: "secret/data/my-app/config#application_name"
        # (Optional) Tell Vault Agent to log at a higher level for debugging
        # vault.hashicorp.com/agent-inject-log-level: "debug"
    spec:
      serviceAccountName: my-app-sa # Link to the ServiceAccount created above
      containers:
      - name: fastapi-app
        image: fastapi-vault-app:latest # IMPORTANT: Replace with your actual image name if pushing to a registry
        ports:
        - containerPort: 8000
        env:
          # Define placeholders or default values.
          # The injected secrets will override these if successful.
          - name: DB_CONNECTION_STRING
            value: "NOT_SET_BY_VAULT"
          - name: API_KEY
            value: "NOT_SET_BY_VAULT"
          - name: APPLICATION_NAME
            value: "NOT_SET_BY_VAULT"

---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-vault-app-service
  labels:
    app: fastapi-vault-app
spec:
  selector:
    app: fastapi-vault-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: LoadBalancer # Or ClusterIP, NodePort depending on your needs for external access
```

``` python
# main.py
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
import os
import uvicorn

app = FastAPI()

# Retrieve secrets from environment variables
# These environment variables will be injected by the Vault Agent sidecar
DB_CONNECTION_STRING = os.getenv("DB_CONNECTION_STRING")
API_KEY = os.getenv("API_KEY")
APP_NAME = os.getenv("APPLICATION_NAME") # To show another secret

@app.get("/", response_class=HTMLResponse)
async def read_root():
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>FastAPI Vault Secret Test</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 2em; }
            pre { background-color: #eee; padding: 1em; border-radius: 5px; }
            .success { color: green; font-weight: bold; }
            .warning { color: orange; font-weight: bold; }
            .error { color: red; font-weight: bold; }
        </style>
    </head>
    <body>
        <h1>FastAPI Application for Vault Secret Testing</h1>
        <p>This application attempts to read secrets injected as environment variables from HashiCorp Vault.</p>
        <p>Go to the <a href="/secrets">/secrets</a> endpoint to see the status of secret retrieval.</p>
        <p>Application Name: <strong>{}</strong></p>
    </body>
    </html>
    """.format(APP_NAME if APP_NAME else "Not Loaded")
    return HTMLResponse(content=html_content)

@app.get("/secrets")
async def get_secret_status():
    secrets_status = {
        "DB_CONNECTION_STRING": "Loaded" if DB_CONNECTION_STRING else "Not Loaded",
        "API_KEY": "Loaded" if API_KEY else "Not Loaded",
        "APPLICATION_NAME": "Loaded" if APP_NAME else "Not Loaded",
        "raw_env_vars_snippet": ""
    }

    # IMPORTANT: In a real application, NEVER return actual secret values!
    # This is for testing/debugging purposes only.
    if DB_CONNECTION_STRING:
        secrets_status["db_connection_string_value_snippet"] = f"{DB_CONNECTION_STRING[:10]}..." # Show only a snippet
    if API_KEY:
        secrets_status["api_key_value_snippet"] = f"{API_KEY[:5]}..." # Show only a snippet
    if APP_NAME:
        secrets_status["application_name_value"] = APP_NAME


    # To demonstrate that env vars are indeed set
    # Filter for injected vars only for a clean output
    injected_vars = {
        k: v for k, v in os.environ.items()
        if k in ["DB_CONNECTION_STRING", "API_KEY", "APPLICATION_NAME"]
    }
    secrets_status["raw_env_vars_snippet"] = injected_vars

    # Determine overall status
    if DB_CONNECTION_STRING and API_KEY and APP_NAME:
        secrets_status["overall_status"] = "All secrets loaded successfully!"
        secrets_status["status_color"] = "success"
    else:
        secrets_status["overall_status"] = "Some secrets are missing or not loaded."
        secrets_status["status_color"] = "error" if not (DB_CONNECTION_STRING and API_KEY and APP_NAME) else "warning"

    return secrets_status

# Optional: To run locally for quick testing before Docker/K8s
if __name__ == "__main__":
    # For local testing, you can set env vars directly to simulate injection:
    # os.environ["DB_CONNECTION_STRING"] = "local_db_conn"
    # os.environ["API_KEY"] = "local_api_key"
    # os.environ["APPLICATION_NAME"] = "LocalTestApp"
    uvicorn.run(app, host="0.0.0.0", port=8000)
````
