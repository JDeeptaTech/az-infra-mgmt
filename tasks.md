```
#!/bin/bash

THRESHOLD=80  # percent
vc_host="vcenter.example.com"
vc_user="your-username"
vc_pass="your-password"

export GOVC_URL="$vc_host"
export GOVC_USERNAME="$vc_user"
export GOVC_PASSWORD="$vc_pass"
export GOVC_INSECURE=1

# You can filter datacenters and clusters here
best_cluster=""
best_dc=""

# List all datacenters
for dc in $(govc ls /); do
  clusters=$(govc ls "$dc/host")
  for cluster in $clusters; do
    usage=$(govc metric.sample -instance "" -name "cpu.usage.average" "$cluster" -json | jq '.[0].value[0]')
    usage_percent=${usage%.*}
    if [[ $usage_percent -lt $THRESHOLD ]]; then
      best_cluster=$(basename "$cluster")
      best_dc=$(basename "$dc")
      break 2
    fi
  done
done

echo "{\"datacenter\": \"$best_dc\", \"cluster\": \"$best_cluster\"}"

```

**Terraform Development Task List (vCenter + Vault)**

**1. Project Initialization**

* Create
  project repository and directory structure
* Initialize
  Git and .gitignore for Terraform (*.tfstate, .terraform/, etc.)
* Write
  a README.md for project overview and usage

---

**2. Terraform Configuration Setup**

* Install
  Terraform CLI
* Set
  up Terraform provider blocks:
  * vsphere
    provider for vCenter
  * vault
    provider for HashiCorp Vault
* Create
  a versions.tf file to pin provider versions and Terraform version

---

**3. Vault Integration**

* Configure
  Vault provider
* Authenticate
  to Vault (token, AppRole, etc.)
* Read
  secrets from Vault (e.g., vSphere credentials)
* Use vault_generic_secret
  or vault_generic_endpoint as needed

---

**4. vCenter Integration**

* Create
  a base main.tf to manage vCenter infrastructure:
  * Datacenter
  * Cluster
  * Resource
    pool
  * VM
    templates or VM provisioning
* Configure
  network, datastore, and folder resources
* Use
  Vault secrets to inject vCenter credentials securely

---

**5. Environment & Variable Management**

* Create
  variables.tf for input variables
* Create
  terraform.tfvars or environment-specific *.tfvars files
* Create
  outputs.tf to expose important outputs

---

**6. State Management**

* Configure
  remote backend (use postgreSQL backend)
* Use terraform
  workspace for environment separation if needed

---

**7. Modules (for Reusability)**

* Create
  reusable Terraform modules for:
  * VM
    creation
  * Network
    configuration
  * Secrets
    injection

---

**8. Testing & Validation**

* Run terraform
  fmt and terraform validate
* Use terraform
  plan to preview changes
* Apply
  with terraform apply (preferably in a non-prod environment)

---

**9. Security Best Practices**

* Use terraform-provider-vault
  to dynamically retrieve credentials

---

**10. CI/CD Pipeline**

* Set
  up Jenkins pipeline
* Lint,
  format, versioning
