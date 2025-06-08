'''
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: default # Ensure this matches the namespace used in the Vault role

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
        # Inject the 'db_url' secret from 'secret/my-app/config' into an env var named DB_URL
        vault.hashicorp.com/agent-inject-env-db_url: "secret/data/my-app/config#db_url"
        # Inject the 'api_key' secret from 'secret/my-app/config' into an env var named API_KEY
        vault.hashicorp.com/agent-inject-env-api_key: "secret/data/my-app/config#api_key"
        # (Optional) Template the secrets into a file instead of env vars
        # vault.hashicorp.com/agent-inject-template-config: |
        #   {{- with secret "secret/data/my-app/config" -}}
        #   DB_URL="{{ .Data.data.db_url }}"
        #   API_KEY="{{ .Data.data.api_key }}"
        #   {{- end }}
    spec:
      serviceAccountName: my-app-sa # Link to the ServiceAccount created above
      containers:
      - name: fastapi-app
        image: your-docker-registry/fastapi-vault-app:latest # Replace with your image
        ports:
        - containerPort: 8000
        # If you were templating to a file, you would mount a volume here
        # volumeMounts:
        # - name: vault-secrets
        #   mountPath: /vault/secrets
        # readOnly: true
      # If you were templating to a file, you would define the volume here
      # volumes:
      # - name: vault-secrets
      #   emptyDir:
      #     medium: Memory


from fastapi import FastAPI, HTTPException
import os

app = FastAPI()

# Retrieve secrets from environment variables
# These environment variables will be injected by the Vault Agent sidecar
DB_URL = os.getenv("DB_URL")
API_KEY = os.getenv("API_KEY")

# Basic validation (optional, but good practice)
if not DB_URL or not API_KEY:
    # In a real application, you might want to log this critical error
    # and potentially exit or use a default value if appropriate.
    print("WARNING: DB_URL or API_KEY environment variables not set. "
          "This might indicate an issue with Vault secret injection.")

@app.get("/")
async def read_root():
    return {"message": "Hello from FastAPI!", "status": "running"}

@app.get("/secret-info")
async def get_secret_info():
    if not DB_URL or not API_KEY:
        raise HTTPException(status_code=500, detail="Secrets not loaded.")

    # In a real application, you would use these secrets
    # to connect to a database, call an external API, etc.
    return {
        "db_url_status": "loaded" if DB_URL else "not loaded",
        "api_key_status": "loaded" if API_KEY else "not loaded",
        "example_usage": "These secrets would be used for database connections or API calls."
        # IMPORTANT: Do NOT return actual secret values in a real API endpoint!
    }

# Example of how you might use the DB_URL (not actually connecting here)
@app.get("/connect-db-example")
async def connect_db_example():
    if not DB_URL:
        raise HTTPException(status_code=500, detail="Database URL not available.")
    # Simulate database connection (replace with actual database logic)
    print(f"Attempting to connect to database using URL: {DB_URL[:10]}...") # Print only prefix for security
    return {"message": "Simulated database connection attempt successful."}
'''