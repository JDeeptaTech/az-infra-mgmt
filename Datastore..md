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
