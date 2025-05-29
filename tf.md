``` python
from pyVim import connect
from pyVmomi import vim
import ssl
import atexit
import os
import certifi # For standard CA bundle, if not using system trust store

# --- Configuration Variables ---
VCENTER_SERVER = "your_vcenter_fqdn_or_ip"
VCENTER_USER = "your_vcenter_username"
VCENTER_PASSWORD = "your_vcenter_password"
DATACENTER_NAME = "YourDatacenterName"
CLUSTER_NAME = "YourClusterName"
VM_NAME_TO_ADD = "YourVMName"
EXISTING_VM_GROUP_NAME = "YourExistingVMGroupName"

# --- SSL Certificate Handling Option ---
# Set to True to verify SSL certificates (recommended for production).
# Set to False to disable SSL verification (for labs/testing only).
VERIFY_SSL = True
# Path to a custom CA bundle file (e.g., your vCenter's self-signed cert).
# If VERIFY_SSL is True and this is None, 'certifi.where()' or system trust store is used.
CA_BUNDLE_PATH = None # e.g., "/path/to/your/vcenter_ca.pem"

# --- Helper Function to Find Objects using PropertyCollector ---
def get_obj_by_name(content, vimtype, name):
    """
    Retrieves a vCenter object by its type and name using PropertyCollector.
    This is generally more efficient for large inventories.
    """
    view_ref = content.viewManager.CreateContainerView(
        content.rootFolder, vimtype, True
    )
    # Define the properties to retrieve (only 'name' is needed for filtering)
    property_spec = vim.PropertySpec(type=vimtype[0], pathSet=['name'])
    object_spec = vim.ObjectSpec(obj=view_ref)
    property_filter_spec = vim.PropertyFilterSpec(
        objectSet=[object_spec],
        propSet=[property_spec]
    )

    # Retrieve properties
    objects = content.propertyCollector.RetrieveContents([property_filter_spec])

    obj = None
    for o in objects:
        for prop in o.propSet:
            if prop.name == 'name' and prop.val == name:
                obj = o.obj
                break
        if obj:
            break
    
    view_ref.Destroy()
    return obj

# --- Main Logic ---
def add_vm_to_vm_host_group_pyvmomi_updated():
    service_instance = None
    try:
        # 1. Connect to vCenter
        print(f"Connecting to vCenter: {VCENTER_SERVER}...")
        
        context = None
        if VERIFY_SSL:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.load_verify_locations(CA_BUNDLE_PATH if CA_BUNDLE_PATH else certifi.where())
            context.verify_mode = ssl.CERT_REQUIRED
            print("SSL verification enabled.")
        else:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.verify_mode = ssl.CERT_NONE
            print("SSL verification disabled (WARNING: insecure for production).")

        service_instance = connect.SmartConnect(
            host=VCENTER_SERVER,
            user=VCENTER_USER,
            pwd=VCENTER_PASSWORD,
            port=443,
            sslContext=context
        )
        # Ensure proper logout on script exit
        atexit.register(connect.Disconnect, service_instance)
        content = service_instance.RetrieveContent()
        print("Connected to vCenter.")

        # 2. Find Objects using the updated helper
        print(f"\nFinding Datacenter '{DATACENTER_NAME}'...")
        datacenter = get_obj_by_name(content, [vim.Datacenter], DATACENTER_NAME)
        if not datacenter:
            raise ValueError(f"Datacenter '{DATACENTER_NAME}' not found.")
        print(f"Found Datacenter: {datacenter.name} (MoRef: {datacenter._moId})")

        print(f"\nFinding Cluster '{CLUSTER_NAME}'...")
        cluster = get_obj_by_name(content, [vim.ClusterComputeResource], CLUSTER_NAME)
        if not cluster:
            raise ValueError(f"Cluster '{CLUSTER_NAME}' not found.")
        print(f"Found Cluster: {cluster.name} (MoRef: {cluster._moId})")

        print(f"\nFinding VM '{VM_NAME_TO_ADD}'...")
        vm_to_add = get_obj_by_name(content, [vim.VirtualMachine], VM_NAME_TO_ADD)
        if not vm_to_add:
            raise ValueError(f"VM '{VM_NAME_TO_ADD}' not found.")
        print(f"Found VM: {vm_to_add.name} (MoRef: {vm_to_add._moId})")

        print(f"\nFinding existing VM Host Group '{EXISTING_VM_GROUP_NAME}' in cluster '{CLUSTER_NAME}'...")
        existing_vm_group_found = None
        current_vms_in_group = []

        if cluster.configurationEx and cluster.configurationEx.group:
            for group in cluster.configurationEx.group:
                if isinstance(group, vim.ClusterVmGroup) and group.name == EXISTING_VM_GROUP_NAME:
                    existing_vm_group_found = group
                    if group.vm:
                        current_vms_in_group = [vm._moId for vm in group.vm]
                    break
        
        if not existing_vm_group_found:
            raise ValueError(f"VM Host Group '{EXISTING_VM_GROUP_NAME}' not found in cluster '{CLUSTER_NAME}'.")
        
        print(f"Found existing VM Group: {existing_vm_group_found.name}")
        print(f"Current VMs in group (MoRef IDs): {current_vms_in_group}")

        # 3. Modify VM Host Group
        # Create a new list of VM MoRef IDs including the VM to add
        # Use set for deduplication and convert to list
        new_vm_mo_ids = list(set(current_vms_in_group + [vm_to_add._moId]))
        print(f"New list of VM MoRef IDs for group: {new_vm_mo_ids}")

        # Create a ClusterConfigSpec to modify the cluster configuration
        cluster_config_spec = vim.cluster.ConfigSpecEx()

        # Create a VmGroupSpec to specify the changes to the VM group
        vm_group_spec = vim.cluster.VmGroupSpec()
        vm_group_spec.info = vim.cluster.VmGroup()
        vm_group_spec.info.name = EXISTING_VM_GROUP_NAME
        # The 'vm' attribute expects a list of ManagedObjectReference objects, not just their IDs
        vm_group_spec.info.vm = [vim.ManagedObjectReference(type="VirtualMachine", value=mo_id) for mo_id in new_vm_mo_ids]

        # Operation to edit the VM group
        vm_group_spec.operation = vim.option.ArrayUpdateSpec.Operation.edit

        cluster_config_spec.vmGroup = [vm_group_spec]

        # 4. Reconfigure Cluster
        print(f"\nReconfiguring cluster '{CLUSTER_NAME}' to add VM to group...")
        task = cluster.ReconfigureComputeResource_Task(spec=cluster_config_spec, modify=True)

        # Wait for the task to complete
        print("Waiting for task to complete...")
        task.wait_for_completion()

        if task.info.state == vim.TaskInfo.State.success:
            print(f"Successfully added VM '{VM_NAME_TO_ADD}' to VM Host Group '{EXISTING_VM_GROUP_NAME}'.")
        else:
            raise RuntimeError(f"Task failed: {task.info.error.localizedMessage}")

    except ValueError as e:
        print(f"Configuration Error: {e}")
    except vim.fault.InvalidLogin as e:
        print(f"Authentication failed: {e.msg}")
    except ssl.SSLError as e:
        print(f"SSL Error: {e}. Please check your CA_BUNDLE_PATH or vCenter certificate.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    finally:
        # Disconnect is handled by atexit.register for pyvmomi
        pass

if __name__ == "__main__":
    add_vm_to_vm_host_group_pyvmomi_updated()
```
