```python
def calculate_usage(used, capacity):
    return (used / capacity) * 100

# Values from the screenshot
cpu_used = 32.94  # GHz
cpu_capacity = 293.76  # GHz

memory_used = 701.16  # GB
memory_capacity = 1462.72  # GB

storage_used = 28307.34  # GB
storage_capacity = 42231.5  # GB

# Calculating usage
cpu_usage_pct = calculate_usage(cpu_used, cpu_capacity)
memory_usage_pct = calculate_usage(memory_used, memory_capacity)
storage_usage_pct = calculate_usage(storage_used, storage_capacity)

print(f"CPU Usage: {cpu_usage_pct:.2f}%")
print(f"Memory Usage: {memory_usage_pct:.2f}%")
print(f"Storage Usage: {storage_usage_pct:.2f}%")

```

```python
import json
import requests
from typing import Dict, List

class DatastoreSelector:
    def __init__(self, config_file: str):
        with open(config_file) as f:
            self.config = json.load(f)
        self.session = None  # vCenter session placeholder
    
    def connect_vcenter(self, credentials: Dict):
        """Use previous connection logic to establish session"""
        self.session = connect_vcenter(**credentials)
    
    def normalize(self, value: float, min_val: float, max_val: float, reverse: bool = False) -> float:
        """Normalize values to 0-1 scale"""
        if max_val - min_val == 0:
            return 0.5
        normalized = (value - min_val) / (max_val - min_val)
        return 1 - normalized if reverse else normalized
    
    def calculate_score(self, datastore: Dict) -> float:
        """Calculate weighted score for a datastore"""
        scores = {}
        
        # Tag-based scoring
        tag_score = 0
        matched_tags = [
            tag for tag in datastore['tags']
            if tag in self.config['scoring']['tags']['datastore_tags']
        ]
        tag_score += len(matched_tags) / len(self.config['scoring']['tags']['datastore_tags'])
        
        matched_cluster_tags = [
            tag for tag in datastore['cluster_tags']
            if tag in self.config['scoring']['tags']['cluster_tags']
        ]
        tag_score += len(matched_cluster_tags) / len(self.config['scoring']['tags']['cluster_tags'])
        
        scores['tags'] = (tag_score / 2) * self.config['scoring']['tags']['weight']
        
        # Resource-based scoring
        cpu_score = self.normalize(
            datastore['cpu_usage'],
            0, self.config['scoring']['resources']['cpu_usage_threshold'],
            reverse=True
        )
        
        mem_score = self.normalize(
            datastore['memory_usage'],
            0, self.config['scoring']['resources']['memory_usage_threshold'],
            reverse=True
        )
        
        space_score = self.normalize(
            datastore['free_space'],
            0, datastore['capacity']
        )
        
        latency_score = self.normalize(
            datastore['network_latency'],
            0, 100,  # Example latency range in ms
            reverse=True
        )
        
        resource_score = (
            (cpu_score + mem_score) * 0.5 * self.config['scoring']['resources']['free_space_weight'] +
            space_score * self.config['scoring']['resources']['free_space_weight'] +
            latency_score * self.config['scoring']['resources']['latency_weight']
        )
        scores['resources'] = resource_score * self.config['scoring']['resources']['weight']
        
        # Network scoring
        network_score = 0
        if datastore['network_zone'] in self.config['scoring']['network']['preferred_zones']:
            network_score += 0.7
        if datastore['bandwidth'] > self.config['scoring']['network']['bandwidth_threshold']:
            network_score += 0.3
            
        scores['network'] = network_score * self.config['scoring']['network']['weight']
        
        return sum(scores.values())
    
    def filter_datastores(self, datastores: List[Dict]) -> List[Dict]:
        """Apply filters and scoring"""
        # Filter by required tags
        filtered = [
            ds for ds in datastores
            if all(tag in ds['tags'] for tag in self.config['required_tags'])
        ]
        
        # Calculate scores
        for ds in filtered:
            ds['score'] = self.calculate_score(ds)
        
        # Sort by score descending
        return sorted(filtered, key=lambda x: x['score'], reverse=True)

    def get_datastore_data(self):
        """Fetch live data from vCenter (pseudo-code)"""
        # Example API calls:
        # - GET /rest/vcenter/datastore
        # - GET /rest/vcenter/cluster
        # - GET performance metrics
        return []  # Implement actual API calls here

# Usage Example
if __name__ == "__main__":
    selector = DatastoreSelector("datastore_rules.json")
    selector.connect_vcenter({
        "vcenter_url": "https://vcenter.example.com",
        "username": "admin",
        "password": "secret"
    })
    
    datastores = selector.get_datastore_data()
    sorted_datastores = selector.filter_datastores(datastores)
    
    print("Best datastore options:")
    for idx, ds in enumerate(sorted_datastores[:3], 1):
        print(f"{idx}. {ds['name']} - Score: {ds['score']:.2f}")
        print(f"   CPU: {ds['cpu_usage']}%, Memory: {ds['memory_usage']}%")
        print(f"   Free Space: {ds['free_space']}GB, Latency: {ds['network_latency']}ms\n")
````

``` python
import requests
import json
from typing import Dict, List

class ClusterOptimizer:
    def __init__(self, config_file: str):
        with open(config_file) as f:
            self.config = json.load(f)
        self.session = requests.Session()
        self.base_url = ""
        
    def connect_vcenter(self, vcenter_url: str, username: str, password: str):
        self.base_url = f"{vcenter_url}/rest"
        auth_url = f"{self.base_url}/com/vmware/cis/session"
        try:
            response = self.session.post(
                auth_url,
                auth=(username, password),
                verify=False
            )
            if response.status_code == 200:
                self.session.headers.update({
                    'vmware-api-session-id': response.json()['value']
                })
                return True
            return False
        except Exception as e:
            print(f"Connection error: {str(e)}")
            return False

    def _get_api(self, endpoint: str) -> List[Dict]:
        url = f"{self.base_url}{endpoint}"
        response = self.session.get(url, verify=False)
        if response.status_code == 200:
            return response.json()['value']
        return []

    def get_clusters(self) -> List[Dict]:
        return self._get_api("/vcenter/cluster")

    def get_datastores(self) -> List[Dict]:
        return self._get_api("/vcenter/datastore")

    def get_hosts(self, cluster: str) -> List[Dict]:
        return self._get_api(f"/vcenter/host?filter.clusters={cluster}")

    def get_cluster_resources(self, cluster: str) -> Dict:
        # Get real-time resource usage
        url = f"{self.base_url}/vcenter/cluster/{cluster}/summary"
        response = self.session.get(url, verify=False)
        if response.status_code == 200:
            return response.json()['value']
        return {}

    def get_datastore_performance(self, datastore: str) -> Dict:
        # Get datastore metrics (requires vCenter performance APIs)
        url = f"{self.base_url}/vcenter/datastore/{datastore}/summary"
        response = self.session.get(url, verify=False)
        if response.status_code == 200:
            return response.json()['value']
        return {}

    def calculate_cluster_score(self, cluster: Dict, datastores: List[Dict]) -> float:
        score = 0
        
        # Cluster resource scoring
        resources = self.get_cluster_resources(cluster['cluster'])
        cpu_usage = resources.get('cpu.usage', 0)
        mem_usage = resources.get('memory.usage', 0)
        
        score += (100 - cpu_usage)/100 * self.config['weights']['cpu']
        score += (100 - mem_usage)/100 * self.config['weights']['memory']

        # Datastore scoring
        cluster_datastores = [ds for ds in datastores 
                            if ds['datastore'] in cluster['datastores']]
        
        ds_scores = []
        for ds in cluster_datastores:
            ds_info = self.get_datastore_performance(ds['datastore'])
            free_space = ds_info.get('free_space', 0)
            capacity = ds_info.get('capacity', 1)
            ds_score = (free_space / capacity) * self.config['weights']['storage']
            
            if any(tag in ds_info.get('tags', []) for tag in self.config['required_ds_tags']):
                ds_score *= self.config['tag_boost']
                
            ds_scores.append(ds_score)
        
        score += (sum(ds_scores)/len(ds_scores)) if ds_scores else 0

        # Network scoring
        if cluster['network_zone'] in self.config['preferred_network_zones']:
            score += self.config['weights']['network']

        return score

    def get_best_cluster(self):
        clusters = self.get_clusters()
        datastores = self.get_datastores()
        
        scored_clusters = []
        for cluster in clusters:
            # Enrich cluster data with datastore info
            cluster['datastores'] = [ds['datastore'] for ds in datastores 
                                    if ds['cluster'] == cluster['cluster']]
            cluster['score'] = self.calculate_cluster_score(cluster, datastores)
            scored_clusters.append(cluster)
        
        return sorted(scored_clusters, key=lambda x: x['score'], reverse=True)

# Configuration file (cluster_config.json)
"""
{
    "weights": {
        "cpu": 0.3,
        "memory": 0.3,
        "storage": 0.25,
        "network": 0.15
    },
    "required_ds_tags": ["ssd", "high-availability"],
    "preferred_network_zones": ["zone-a", "zone-b"],
    "tag_boost": 1.2
}
"""

# Usage example
if __name__ == "__main__":
    optimizer = ClusterOptimizer("cluster_config.json")
    if optimizer.connect_vcenter(
        "https://vcenter.example.com",
        "admin@vsphere.local",
        "password"
    ):
        best_clusters = optimizer.get_best_cluster()
        print("Top clusters for VM deployment:")
        for idx, cluster in enumerate(best_clusters[:3], 1):
            print(f"{idx}. {cluster['name']} - Score: {cluster['score']:.2f}")
            print(f"   CPU Usage: {cluster.get('cpu.usage', 'N/A')}%")
            print(f"   Memory Usage: {cluster.get('memory.usage', 'N/A')}%")
            print(f"   Available Datastores: {len(cluster['datastores'])}\n")
````

``` txt
Key improvements and features:

vCenter REST API Integration:

Cluster resource monitoring (/vcenter/cluster/{id}/summary)

Datastore metrics (/vcenter/datastore/{id}/summary)

Host and cluster enumeration

Scoring Logic:

Real-time CPU/Memory utilization

Datastore capacity and tagging

Network zone preferences

Weighted scoring system

Customization:

JSON-configurable weights and priorities

Tag-based filtering and scoring boosts

Network zone preferences

Storage performance considerations

Multi-factor Analysis:
````

