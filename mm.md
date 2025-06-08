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
``` python
# main.py
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import HTMLResponse
import os
import hvac
import logging
import asyncio
from datetime import datetime, timedelta

app = FastAPI()

# --- Configuration ---
# Vault address (usually the Kubernetes service for Vault)
# In Kubernetes, this might be something like "http://vault.vault.svc.cluster.local:8200"
# For local testing, keep it as it is if you port-forwarded Vault.
VAULT_ADDR = os.getenv("VAULT_ADDR", "http://127.0.0.1:8200")
VAULT_ROLE = os.getenv("VAULT_ROLE", "my-app-role") # The Vault role bound to your K8s Service Account
VAULT_SECRET_PATH = os.getenv("VAULT_SECRET_PATH", "secret/data/my-app/config")

# Kubernetes service account token path (standard in K8s pods)
KUBERNETES_SA_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Global Vault Client and Token Management ---
vault_client: hvac.Client = None
vault_token_info: dict = None # Stores {'client_token': '...', 'lease_duration': N, 'renewable': True/False, 'last_renewal': datetime}
secret_data: dict = {} # Cached secret data

async def authenticate_with_vault():
    """Authenticates with Vault using the Kubernetes auth method."""
    global vault_client, vault_token_info

    try:
        if not os.path.exists(KUBERNETES_SA_TOKEN_PATH):
            logger.error(f"Kubernetes Service Account token not found at {KUBERNETES_SA_TOKEN_PATH}. "
                         "Are you running inside a Kubernetes pod?")
            # For local testing, you might need to set a VAULT_TOKEN env var directly
            # For real usage, this should only be called inside K8s.
            if os.getenv("VAULT_TOKEN"):
                logger.info("Using VAULT_TOKEN from environment variable for local testing.")
                vault_client = hvac.Client(url=VAULT_ADDR, token=os.getenv("VAULT_TOKEN"))
                vault_token_info = {
                    'client_token': os.getenv("VAULT_TOKEN"),
                    'lease_duration': 3600, # Assume a default for local env token
                    'renewable': True,
                    'last_renewal': datetime.now()
                }
                logger.info("Vault client initialized with VAULT_TOKEN.")
                return True
            else:
                raise Exception("Kubernetes SA token missing and VAULT_TOKEN not set.")


        with open(KUBERNETES_SA_TOKEN_PATH, 'r') as f:
            jwt = f.read()

        logger.info(f"Authenticating with Vault at {VAULT_ADDR} using role '{VAULT_ROLE}'...")
        client = hvac.Client(url=VAULT_ADDR)
        auth_response = client.auth.kubernetes.login(role=VAULT_ROLE, jwt=jwt)

        vault_token_info = {
            'client_token': auth_response['auth']['client_token'],
            'lease_duration': auth_response['auth']['lease_duration'],
            'renewable': auth_response['auth']['renewable'],
            'last_renewal': datetime.now()
        }
        vault_client = client
        logger.info("Successfully authenticated with Vault.")
        return True

    except Exception as e:
        logger.error(f"Failed to authenticate with Vault: {e}")
        vault_client = None
        vault_token_info = None
        return False

async def renew_vault_token():
    """Renews the Vault token if it's renewable and approaching expiration."""
    global vault_token_info

    if not vault_client or not vault_client.is_authenticated() or not vault_token_info:
        logger.warning("No authenticated Vault client or token info found for renewal. Attempting re-authentication.")
        await authenticate_with_vault()
        return

    # Renew if within 1/2 of its lease duration, but at least 5 minutes before expiry
    # This gives ample time to handle potential network issues during renewal.
    expiry_time = vault_token_info['last_renewal'] + timedelta(seconds=vault_token_info['lease_duration'])
    renewal_threshold = vault_token_info['last_renewal'] + timedelta(seconds=vault_token_info['lease_duration'] / 2)
    min_renewal_buffer = timedelta(minutes=5)

    if datetime.now() >= (expiry_time - min_renewal_buffer) or datetime.now() >= renewal_threshold:
        if vault_token_info.get('renewable', False):
            try:
                logger.info(f"Attempting to renew Vault token (current lease: {vault_token_info['lease_duration']}s, expires around {expiry_time.strftime('%H:%M:%S')})...")
                renew_response = vault_client.auth.token.renew(vault_token_info['client_token'])
                vault_token_info['lease_duration'] = renew_response['auth']['lease_duration']
                vault_token_info['last_renewal'] = datetime.now()
                logger.info(f"Vault token renewed successfully. New lease duration: {vault_token_info['lease_duration']}s")
            except Exception as e:
                logger.error(f"Failed to renew Vault token: {e}. Attempting re-authentication.")
                # If renewal fails, try to re-authenticate from scratch
                await authenticate_with_vault()
        else:
            logger.warning("Vault token is not renewable. Will attempt re-authentication on next secret access.")
            # Set client to None to force re-authentication
            vault_client = None
            vault_token_info = None
    else:
        logger.debug(f"Token renewal not needed yet. Expires at {expiry_time.strftime('%H:%M:%S')}.")


async def get_secrets_from_vault():
    """Retrieves secrets from Vault."""
    global secret_data

    if not vault_client or not vault_client.is_authenticated():
        logger.info("Vault client not authenticated. Attempting authentication...")
        if not await authenticate_with_vault():
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Failed to authenticate with Vault.")

    # Always attempt renewal before fetching secrets, if due.
    await renew_vault_token() # This will re-authenticate if necessary

    try:
        logger.info(f"Attempting to read secrets from path: {VAULT_SECRET_PATH}")
        read_response = vault_client.secrets.kv.v2.read_secret_version(
            path=VAULT_SECRET_PATH.replace('secret/data/', '') # KV v2 path needs to be without /data/
        )
        secret_data = read_response['data']['data']
        logger.info("Secrets successfully retrieved from Vault.")
        return secret_data
    except hvac.exceptions.VaultError as e:
        logger.error(f"Vault API error when reading secrets: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Vault API error: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred while fetching secrets: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Unexpected error: {e}")


# --- FastAPI Endpoints ---

@app.on_event("startup")
async def startup_event():
    logger.info("FastAPI application startup. Attempting initial Vault authentication and secret fetch.")
    await get_secrets_from_vault() # Initial fetch
    # Schedule periodic secret refresh/token renewal if needed, though get_secrets_from_vault handles it.
    # For long-running apps, you might want a dedicated background task
    # to periodically call renew_vault_token and refresh secrets.
    # FastAPI background tasks or a separate asyncio task could be used.
    # E.g., asyncio.create_task(periodic_refresh())


@app.get("/", response_class=HTMLResponse)
async def read_root():
    app_name = secret_data.get("application_name", "Not Loaded Yet (or error)")
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>FastAPI Vault Direct Access Test</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 2em; }}
            pre {{ background-color: #eee; padding: 1em; border-radius: 5px; }}
            .success {{ color: green; font-weight: bold; }}
            .warning {{ color: orange; font-weight: bold; }}
            .error {{ color: red; font-weight: bold; }}
        </style>
    </head>
    <body>
        <h1>FastAPI Application for Vault Direct Secret Access</h1>
        <p>This application directly fetches secrets from HashiCorp Vault.</p>
        <p>Go to the <a href="/secrets">/secrets</a> endpoint to see the status of secret retrieval.</p>
        <p>Application Name: <strong>{app_name}</strong></p>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

@app.get("/secrets")
async def get_secret_status():
    secrets = {}
    try:
        # Fetch secrets again to ensure freshness or handle renewal
        current_secrets = await get_secrets_from_vault()

        secrets_status = {
            "DB_CONNECTION_STRING": "Loaded" if current_secrets.get("db_connection_string") else "Not Loaded",
            "API_KEY": "Loaded" if current_secrets.get("api_key") else "Not Loaded",
            "APPLICATION_NAME": "Loaded" if current_secrets.get("application_name") else "Not Loaded",
            "vault_token_status": "Authenticated" if vault_client and vault_client.is_authenticated() else "Not Authenticated",
            "token_info": vault_token_info,
            "overall_status": "",
            "status_color": "",
            "secret_values_snippet": {}
        }

        # IMPORTANT: In a real application, NEVER return actual secret values directly!
        # This is for testing/debugging purposes only.
        if current_secrets.get("db_connection_string"):
            secrets_status["secret_values_snippet"]["db_connection_string"] = f"{current_secrets['db_connection_string'][:10]}..."
        if current_secrets.get("api_key"):
            secrets_status["secret_values_snippet"]["api_key"] = f"{current_secrets['api_key'][:5]}..."
        if current_secrets.get("application_name"):
            secrets_status["secret_values_snippet"]["application_name"] = current_secrets['application_name']

        if all(k in current_secrets for k in ["db_connection_string", "api_key", "application_name"]):
            secrets_status["overall_status"] = "All secrets loaded successfully!"
            secrets_status["status_color"] = "success"
        else:
            secrets_status["overall_status"] = "Some secrets are missing or not loaded."
            secrets_status["status_color"] = "error"

        return secrets_status

    except HTTPException as e:
        logger.error(f"HTTPException in /secrets: {e.detail}")
        raise e
    except Exception as e:
        logger.error(f"An unexpected error occurred in /secrets: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Unexpected error retrieving secrets: {e}")


# To run locally for quick testing before Docker/K8s
# This block sets up a simple local environment to simulate secrets
if __name__ == "__main__":
    # --- Local Testing Setup (Optional) ---
    # To run this locally (outside K8s), you'll need a VAULT_TOKEN
    # and a VAULT_ADDR that points to your local Vault.
    # Make sure your Vault is running and port-forwarded (Step 0).
    # Then set VAULT_TOKEN to your root token or an app-specific token.
    # export VAULT_ADDR='http://127.0.0.1:8200'
    # export VAULT_TOKEN='<your_vault_root_token_from_helm_install>'
    #
    # If not using the K8s auth method for local testing,
    # you can comment out the KUBERNETES_SA_TOKEN_PATH check
    # or ensure VAULT_TOKEN is set.
    # When running locally, the `authenticate_with_vault` will detect VAULT_TOKEN
    # and use it instead of the K8s SA token.

    # Start Uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
````
