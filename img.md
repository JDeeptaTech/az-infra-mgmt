``` txt
#!/bin/bash

VCENTER_HOST="your-vcenter.example.com"
SESSION_ID="your-session-token"
TEMPLATE_NAME="Windows-Template"  # Change this to your template name

# Get all VMs
ALL_VMS=$(curl -s -X GET "https://${VCENTER_HOST}/api/vcenter/vm" \
  -H "vmware-api-session-id: ${SESSION_ID}" \
  -H "Content-Type: application/json")

# Find the VM ID by name (case-insensitive search)
VM_ID=$(echo "$ALL_VMS" | jq -r --arg NAME "$TEMPLATE_NAME" '.[] | select(.name | ascii_downcase == ($NAME | ascii_downcase)) | .vm')

if [ -z "$VM_ID" ]; then
  echo "Template not found: $TEMPLATE_NAME"
  exit 1
fi

echo "Found VM ID: $VM_ID for template: $TEMPLATE_NAME"

# Get detailed template information
curl -s -X GET "https://${VCENTER_HOST}/api/vcenter/vm/${VM_ID}" \
  -H "vmware-api-session-id: ${SESSION_ID}" \
  -H "Content-Type: application/json" | jq .
```
