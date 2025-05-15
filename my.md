```python
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

import ssl

def get_cluster_performance_and_cpu(vcenter_host, vcenter_user, vcenter_password, cluster_name):
    """
    Retrieves and prints performance overview and vCPU information for a vCenter cluster.
    """
    si = None
    try:
        # Disable SSL certificate verification (for development/testing purposes only!)
        context = ssl._create_unverified_context()
        si = SmartConnect(host=vcenter_host,
                           user=vcenter_user,
                           pwd=vcenter_password,
                           sslContext=context)

        content = si.RetrieveContent()

        cluster = None
        compute_resources = content.rootFolder.childEntity
        for compute_resource in compute_resources:
            if isinstance(compute_resource, vim.ComputeResource) and compute_resource.name == cluster_name:
                cluster = compute_resource
                break

        if not cluster:
            print(f"Cluster '{cluster_name}' not found.")
            return

        print(f"Information for Cluster: {cluster.name}")
        print("-" * 40)

        # --- Performance Overview ---
        perf_manager = content.perfManager
        counter_names = ['cpu.usage.average', 'mem.usage.average',
                         'net.transmitted.average', 'net.received.average',
                         'disk.read.average', 'disk.write.average']
        perf_dicts = perf_manager.QueryPerfCounterByLevel(intervalId=None, entityType=vim.ComputeResource)
        query_counters = []
        for counter in perf_dicts:
            if counter.counterInfo.name in counter_names and counter.counterInfo.level == '2':
                query_counters.append(counter.counterInfo)

        if query_counters:
            query = vim.PerformanceManager.QuerySpec(
                entity=cluster,
                maxSample=1,
                intervalId=20,
                metric=[vim.PerformanceManager.MetricSpec(counterId=counter.key) for counter in query_counters]
            )
            perf_data = perf_manager.QueryStats(querySpec=[query])

            if perf_data and perf_data[0].entity == cluster:
                print("Cluster Performance (Latest):")
                for metric in perf_data[0].value:
                    for counter in query_counters:
                        if counter.key == metric.id.counterId:
                            print(f"  {counter.name}: {metric.value[0]} {counter.unitInfo.label}")
            else:
                print("  No recent performance data available for the cluster.")
        else:
            print("  No relevant performance counters found for the cluster.")

        print("\nHost CPU Information:")
        if cluster.host:
            for host_ref in cluster.host:
                host = host_ref.ManagedObject()
                hardware = host.hardware
                if hardware and hardware.cpuInfo:
                    num_physical_cpu_packages = len(hardware.cpuPkg) if hardware.cpuPkg else 0
                    num_cpu_cores = hardware.cpuInfo.numCpuCores if hardware.cpuInfo.numCpuCores else 0
                    num_cpu_threads = hardware.cpuInfo.numCpuThreads if hardware.cpuInfo.numCpuThreads else 0
                    model = hardware.cpuInfo.model if hardware.cpuInfo.model else "N/A"

                    print(f"  Host: {host.name}")
                    print(f"    Model: {model}")
                    print(f"    Physical CPU Packages: {num_physical_cpu_packages}")
                    print(f"    CPU Cores per Package: {num_cpu_cores // num_physical_cpu_packages if num_physical_cpu_packages else 0}")
                    print(f"    Total CPU Cores: {num_cpu_cores}")
                    print(f"    Total Logical CPUs (vCPUs): {num_cpu_threads}")
                else:
                    print(f"  Host: {host.name} - CPU information not available.")
        else:
            print("  No hosts found in the cluster.")

    except vmodl.MethodFault as error:
        print(f"Caught vmodl fault : {error.msg}")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if si:
            Disconnect(si)

if __name__ == "__main__":
    vcenter_host = "your_vcenter_ip_or_hostname"
    vcenter_user = "your_username"
    vcenter_password = "your_password"
    cluster_name = "YourClusterName"

    get_cluster_performance_and_cpu(vcenter_host, vcenter_user, vcenter_password, cluster_name)
```

```python
from typing import Callable, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

class APIRequest(BaseModel):
    endpoint: str
    payload: dict = {}

class APIResponse(BaseModel):
    status_code: int
    data: dict = {}

class APIHandler:
    """
    Abstract handler for API calls.
    """
    def __init__(self, successor: Optional['APIHandler'] = None):
        self._successor = successor

    def set_successor(self, successor: 'APIHandler') -> 'APIHandler':
        self._successor = successor
        return successor

    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        raise NotImplementedError("Subclasses must implement handle_request")

class UserAPIHandler(APIHandler):
    """
    Handles API calls related to users.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/users"):
            # Simulate calling a user management API
            print(f"UserAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/users" and request.payload.get("action") == "create":
                return APIResponse(status_code=201, data={"message": "User created successfully", "user_id": 123})
            elif request.endpoint == "/users/123":
                return APIResponse(status_code=200, data={"id": 123, "username": "testuser"})
            else:
                return APIResponse(status_code=404, data={"error": "User endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

class ProductAPIHandler(APIHandler):
    """
    Handles API calls related to products.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/products"):
            # Simulate calling a product catalog API
            print(f"ProductAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/products":
                return APIResponse(status_code=200, data=[{"id": 1, "name": "Laptop"}, {"id": 2, "name": "Mouse"}])
            elif request.endpoint == "/products/1":
                return APIResponse(status_code=200, data={"id": 1, "name": "Laptop", "price": 1200})
            else:
                return APIResponse(status_code=404, data={"error": "Product endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

class OrderAPIHandler(APIHandler):
    """
    Handles API calls related to orders.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/orders"):
            # Simulate calling an order management API
            print(f"OrderAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/orders" and request.payload.get("action") == "create":
                return APIResponse(status_code=201, data={"message": "Order created successfully", "order_id": 456})
            elif request.endpoint == "/orders/456":
                return APIResponse(status_code=200, data={"id": 456, "items": [1, 2], "total": 1500})
            else:
                return APIResponse(status_code=404, data={"error": "Order endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

# Create the chain of responsibility
user_handler = UserAPIHandler()
product_handler = ProductAPIHandler()
order_handler = OrderAPIHandler()

user_handler.set_successor(product_handler).set_successor(order_handler)

async def invoke_api(request: APIRequest) -> APIResponse:
    """
    Invokes the appropriate API based on the request using the chain of responsibility.
    """
    response = await user_handler.handle_request(request)
    if response:
        return response
    else:
        raise HTTPException(status_code=404, detail="Endpoint not found")

@app.post("/invoke")
async def invoke(api_request: APIRequest):
    return await invoke_api(api_request)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```
