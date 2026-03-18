#!/usr/bin/env python3
"""
Redis Enterprise Active-Active Monitoring UI
Flask-based web interface for monitoring dual-region Redis Enterprise clusters
"""

import os
import json
import requests
import yaml
from datetime import datetime
from flask import Flask, render_template, jsonify, request
from urllib3.exceptions import InsecureRequestWarning
from kubernetes import client, config

# Suppress SSL warnings (Redis Enterprise uses self-signed certs)
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

# Load Kubernetes config (in-cluster)
try:
    config.load_incluster_config()
except:
    # Fallback to kubeconfig for local development
    try:
        config.load_kube_config()
    except:
        print("Warning: Could not load Kubernetes configuration")

app = Flask(__name__)

# Load configuration
CONFIG_PATH = os.getenv('CONFIG_PATH', '/app/config/config.yaml')
with open(CONFIG_PATH, 'r') as f:
    config = yaml.safe_load(f)

# Load secrets
def load_secret(secret_name):
    """Load username and password from Kubernetes secret"""
    username_path = f'/app/secrets/{secret_name}/username'
    password_path = f'/app/secrets/{secret_name}/password'
    
    with open(username_path, 'r') as f:
        username = f.read().strip()
    with open(password_path, 'r') as f:
        password = f.read().strip()
    
    return username, password

# API client
class RedisEnterpriseAPI:
    def __init__(self, region_config):
        self.endpoint = region_config['api_endpoint']
        self.port = region_config['api_port']
        self.base_url = f"https://{self.endpoint}:{self.port}/v1"
        
        username, password = load_secret(region_config['secret_name'])
        self.auth = (username, password)
    
    def get_cluster_info(self):
        """Get cluster information"""
        try:
            response = requests.get(
                f"{self.base_url}/cluster",
                auth=self.auth,
                verify=False,
                timeout=5
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def get_nodes(self):
        """Get cluster nodes"""
        try:
            response = requests.get(
                f"{self.base_url}/nodes",
                auth=self.auth,
                verify=False,
                timeout=5
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def get_databases(self):
        """Get all databases"""
        try:
            response = requests.get(
                f"{self.base_url}/bdbs",
                auth=self.auth,
                verify=False,
                timeout=5
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def get_database(self, db_name):
        """Get specific database by name"""
        databases = self.get_databases()
        if isinstance(databases, dict) and "error" in databases:
            return databases
        
        for db in databases:
            if db.get('name') == db_name:
                return db
        
        return {"error": f"Database {db_name} not found"}

# Routes
@app.route('/')
def index():
    """Main dashboard"""
    return render_template(
        'index.html',
        config=config,
        refresh_interval=config['refresh_interval']
    )

@app.route('/api/cluster/<region>')
def get_cluster_status(region):
    """Get cluster status for a region"""
    if region not in config['regions']:
        return jsonify({"error": "Invalid region"}), 400
    
    api = RedisEnterpriseAPI(config['regions'][region])
    cluster_info = api.get_cluster_info()
    nodes = api.get_nodes()
    
    return jsonify({
        "region": region,
        "cluster": cluster_info,
        "nodes": nodes,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/database/<region>')
def get_database_status(region):
    """Get database status for a region"""
    if region not in config['regions']:
        return jsonify({"error": "Invalid region"}), 400
    
    api = RedisEnterpriseAPI(config['regions'][region])
    db = api.get_database(config['database_name'])
    
    return jsonify({
        "region": region,
        "database": db,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/crdb')
def get_crdb_status():
    """Get CRDB replication status from both regions"""
    result = {}
    
    for region_key, region_config in config['regions'].items():
        api = RedisEnterpriseAPI(region_config)
        db = api.get_database(config['database_name'])
        result[region_key] = db
    
    return jsonify({
        "database_name": config['database_name'],
        "regions": result,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()})

@app.route('/api/nodes/<region>')
def get_nodes(region):
    """Get EKS nodes running Redis Enterprise pods"""
    try:
        v1 = client.CoreV1Api()
        namespace = config.get('namespace', 'redis-enterprise')

        # Get all pods in the redis-enterprise namespace
        pods = v1.list_namespaced_pod(namespace=namespace)

        # Get unique node names running Redis Enterprise pods
        node_pod_count = {}
        for pod in pods.items:
            if pod.spec.node_name:
                node_name = pod.spec.node_name
                if node_name not in node_pod_count:
                    node_pod_count[node_name] = 0
                node_pod_count[node_name] += 1

        # Build node list with pod counts
        nodes = []
        for node_name, pod_count in node_pod_count.items():
            nodes.append({
                "name": node_name,
                "pod_count": pod_count
            })

        # Sort by node name
        nodes.sort(key=lambda x: x['name'])

        return jsonify({
            "region": region,
            "nodes": nodes,
            "total_nodes": len(nodes),
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/simulate/node-failure', methods=['POST'])
def simulate_node_failure():
    """Simulate node failure by cordoning and draining a node"""
    try:
        data = request.get_json()
        node_name = data.get('node_name')
        region = data.get('region')

        if not node_name:
            return jsonify({"error": "node_name is required"}), 400

        v1 = client.CoreV1Api()

        # Get the node
        try:
            node = v1.read_node(name=node_name)
        except client.exceptions.ApiException as e:
            return jsonify({"error": f"Node not found: {node_name}"}), 404

        # Cordon the node (mark as unschedulable)
        node.spec.unschedulable = True
        v1.patch_node(name=node_name, body=node)

        # Delete pods on the node to simulate drain
        # (In production, you might want to use a more graceful drain)
        namespace = config.get('namespace', 'redis-enterprise')
        pods = v1.list_namespaced_pod(
            namespace=namespace,
            field_selector=f'spec.nodeName={node_name}'
        )

        deleted_pods = []
        for pod in pods.items:
            try:
                v1.delete_namespaced_pod(
                    name=pod.metadata.name,
                    namespace=namespace,
                    body=client.V1DeleteOptions()
                )
                deleted_pods.append(pod.metadata.name)
            except Exception as e:
                print(f"Error deleting pod {pod.metadata.name}: {e}")

        return jsonify({
            "status": "success",
            "node_name": node_name,
            "region": region,
            "cordoned": True,
            "deleted_pods": deleted_pods,
            "pod_count": len(deleted_pods),
            "message": f"Node {node_name} has been cordoned and {len(deleted_pods)} pod(s) deleted",
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)