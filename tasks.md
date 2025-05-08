


```python

from pyVim import connect
from pyVmomi import vim

def get_host_hba_luns(si, host):
    """
    Retrieves Fiber Channel and iSCSI HBAs and their associated LUN details for a host.

    Args:
        si (ServiceInstance): vSphere Service Instance.
        host (vim.HostSystem): ESXi host object.

    Returns:
        dict: A dictionary containing HBA information.
              Keys are HBA device names, and values are lists of LUN details.
    """
    hba_lun_info = {"fc": {}, "iscsi": {}}
    storage_system = host.configManager.storageSystem
    if storage_system and storage_system.storageDeviceInfo and storage_system.storageDeviceInfo.hostBusAdapter:
        for hba in storage_system.storageDeviceInfo.hostBusAdapter:
            hba_type = None
            hba_name = hba.device
            lun_details = []

            if isinstance(hba, vim.HostFibreChannelHba):
                hba_type = "fc"
            elif isinstance(hba, vim.HostInternetScsiHba):
                hba_type = "iscsi"

            if hba_type:
                for path in storage_system.storageDeviceInfo.multipathInfo.path:
                    if path.adapter == hba.key:
                        for lun in storage_system.storageDeviceInfo.multipathInfo.lun:
                            if lun.key == path.lun:
                                lun_info = {
                                    "canonical_name": lun.canonicalName,
                                    "uuid": lun.uuid,
                                    "lun_type": lun.lunType,
                                    "state": lun.state,
                                    "operational_state": lun.operationalState,
                                    # Add other relevant LUN properties
                                }
                                lun_details.append(lun_info)
                hba_lun_info[hba_type][hba_name] = lun_details
    return hba_lun_info

def get_vm_host(si, vm_name):
    """
    Retrieves the ESXi host that a given VM is running on.

    Args:
        si (ServiceInstance): vSphere Service Instance.
        vm_name (str): Name of the virtual machine.

    Returns:
        vim.HostSystem or None: The ESXi host object if found, otherwise None.
    """
    content = si.RetrieveContent()
    vm = None
    container = content.rootFolder.childEntity
    for child in container:
        if hasattr(child, 'vmFolder'):
            vm_folder = child.vmFolder
            vm_list = vm_folder.childEntity
            for v in vm_list:
                if v.name == vm_name:
                    vm = v
                    break
            if vm:
                break
        elif isinstance(child, vim.VirtualMachine) and child.name == vm_name:
            vm = child
            break
    if vm and vm.runtime and vm.runtime.host:
        return vm.runtime.host
    return None

def main(vcenter_host, vcenter_user, vcenter_password, vm_name):
    """
    Connects to vCenter, retrieves the host for a VM, and then gets FC/iSCSI HBA and LUN details.

    Args:
        vcenter_host (str): vCenter hostname or IP address.
        vcenter_user (str): vCenter username.
        vcenter_password (str): vCenter password.
        vm_name (str): Name of the virtual machine.
    """
    si = None
    try:
        si = connect.SmartConnectNoSSL(
            host=vcenter_host,
            user=vcenter_user,
            pwd=vcenter_password,
            port=443
        )

        host = get_vm_host(si, vm_name)

        if host:
            print(f"Host for VM '{vm_name}': {host.name}")
            hba_lun_info = get_host_hba_luns(si, host)

            print("\nFiber Channel HBAs and LUNs:")
            if hba_lun_info["fc"]:
                for hba_name, luns in hba_lun_info["fc"].items():
                    print(f"  HBA: {hba_name}")
                    for lun in luns:
                        print(f"    - Canonical Name: {lun['canonical_name']}")
                        print(f"      UUID: {lun['uuid']}")
                        print(f"      LUN Type: {lun['lun_type']}")
                        print(f"      State: {lun['state']}")
                        print(f"      Operational State: {lun['operational_state']}")
                        # Print other LUN details as needed
            else:
                print("  No Fiber Channel HBAs found.")

            print("\niSCSI HBAs and LUNs:")
            if hba_lun_info["iscsi"]:
                for hba_name, luns in hba_lun_info["iscsi"].items():
                    print(f"  HBA: {hba_name}")
                    for lun in luns:
                        print(f"    - Canonical Name: {lun['canonical_name']}")
                        print(f"      UUID: {lun['uuid']}")
                        print(f"      LUN Type: {lun['lun_type']}")
                        print(f"      State: {lun['state']}")
                        print(f"      Operational State: {lun['operational_state']}")
                        # Print other LUN details as needed
            else:
                print("  No iSCSI HBAs found.")

        else:
            print(f"Could not find the host for VM '{vm_name}'.")

    except vim.fault.InvalidLogin as e:
        print(f"Login error: {e.msg}")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if si:
            connect.Disconnect(si)

if __name__ == "__main__":
    vcenter_host = "your_vcenter_ip"  # Replace with your vCenter IP
    vcenter_user = "your_username"  # Replace with your vCenter username
    vcenter_password = "your_password"  # Replace with your vCenter password
    vm_name = "your_vm_name"  # Replace with the name of your VM

    main(vcenter_host, vcenter_user, vcenter_password, vm_name)

___
import requests
import json
from requests.auth import HTTPBasicAuth

# Configuration
VROPS_HOST = 'your-vrops-server.example.com'
USERNAME = 'your_username'
PASSWORD = 'your_password'
API_VERSION = '8.6'  # Adjust based on your vROps version

# API endpoints
AUTH_URL = f'https://{VROPS_HOST}/suite-api/api/auth/token/acquire'
RECOMMENDATIONS_URL = f'https://{VROPS_HOST}/suite-api/api/recommendations'

def get_auth_token():
    """Authenticate and get the auth token"""
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
    }
    auth_payload = {
        'username': USERNAME,
        'password': PASSWORD
    }
    
    try:
        response = requests.post(
            AUTH_URL,
            headers=headers,
            data=json.dumps(auth_payload),
            verify=False  # Set to True with valid certificate
        )
        response.raise_for_status()
        return response.json().get('token')
    except requests.exceptions.RequestException as e:
        print(f"Authentication failed: {e}")
        return None

def get_vm_recommendations(auth_token, resource_id=None):
    """Get VM recommendations"""
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': f'vRealizeOpsToken {auth_token}'
    }
    
    params = {
        'resourceId': resource_id,
        'recommendationState': 'ACTIVE',  # Can be ACTIVE, DISMISSED, IMPLEMENTED
        'recommendationType': 'RECONFIGURE',  # Can be RECONFIGURE, REPURPOSE, REPLACE, etc.
        'pageSize': 100  # Number of recommendations to fetch
    }
    
    try:
        response = requests.get(
            RECOMMENDATIONS_URL,
            headers=headers,
            params=params,
            verify=False  # Set to True with valid certificate
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Failed to get recommendations: {e}")
        return None

def main():
    # Step 1: Authenticate
    auth_token = get_auth_token()
    if not auth_token:
        print("Unable to authenticate. Exiting.")
        return
    
    print("Authentication successful")
    
    # Step 2: Get VM recommendations
    # If you know a specific VM resource ID, pass it as resource_id parameter
    recommendations = get_vm_recommendations(auth_token)
    
    if recommendations:
        print(f"Found {recommendations.get('total', 0)} recommendations:")
        for rec in recommendations.get('recommendationList', []):
            print(f"\nRecommendation ID: {rec.get('id')}")
            print(f"Resource: {rec.get('resourceName')} ({rec.get('resourceId')})")
            print(f"Type: {rec.get('recommendationType')}")
            print(f"State: {rec.get('recommendationState')}")
            print(f"Description: {rec.get('description')}")
            print(f"Details: {rec.get('details')}")
            print("---")
    else:
        print("No recommendations found or error occurred")

if __name__ == '__main__':
    main()
```

```
for dc in $(govc ls /); do
  echo "Datacenter: $dc"

  for cluster in $(govc find "$dc/host" -type c); do
    echo "  Cluster: $cluster"

    output=$(govc object.collect -json "$cluster" cpu.usage.average mem.usage.average 2>/dev/null)

    if echo "$output" | jq . >/dev/null 2>&1; then
      cpu_usage=$(echo "$output" | jq '[.[] | select(.Name=="cpu.usage.average") | .Value[-1]] | .[0]')
      mem_usage=$(echo "$output" | jq '[.[] | select(.Name=="mem.usage.average") | .Value[-1]] | .[0]')
    else
      cpu_usage="N/A"
      mem_usage="N/A"
    fi

    echo "    CPU Usage: $cpu_usage"
    echo "    Memory Usage: $mem_usage"
  done
done


```
```
#!/bin/bash

govc metric.sample /DC1/host/Prod-Cluster cpu.usage.average mem.usage.average datastore.used.* -json | jq -r '.[] | [.SampleInfo[].Timestamp, .Value[].Name, .Value[].Value] | @csv' > cluster_metrics.csv

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
