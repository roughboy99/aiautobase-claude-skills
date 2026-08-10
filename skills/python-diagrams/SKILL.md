---
name: python-diagrams
description: Generate cloud architecture diagrams using the Python diagrams library. Supports AWS, GCP, Azure, Kubernetes, on-prem, and custom nodes. Outputs PNG automatically via Graphviz.
---

# Python Diagrams Skill

You are an expert in the Python `diagrams` library for cloud and system architecture visualization.

## Setup
```bash
pip install diagrams
# Also requires Graphviz: brew install graphviz / apt install graphviz
```

## Basic Usage
Always save to a `.py` file and run it — the diagram renders automatically to PNG.

## Examples

### AWS Architecture
```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import RDS, ElastiCache
from diagrams.aws.network import CloudFront, Route53
from diagrams.aws.storage import S3

with Diagram("AI Creator OS — AWS Stack", show=True, direction="LR"):
    dns = Route53("DNS")
    cdn = CloudFront("CDN")
    with Cluster("App"):
        api = Lambda("API")
        workers = [Lambda("Worker1"), Lambda("Worker2")]
    db = RDS("Database")
    cache = ElastiCache("Cache")
    storage = S3("Media Storage")

    dns >> cdn >> api >> workers
    api >> db
    api >> cache
    workers >> storage
```

### Self-Hosted Stack (Hector's setup)
```python
from diagrams import Diagram, Cluster
from diagrams.onprem.container import Docker
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.network import Nginx
from diagrams.onprem.workflow import Airflow

with Diagram("Orbix Self-Hosted Infrastructure", show=True):
    with Cluster("Hostinger VPS (72.60.175.102)"):
        proxy = Nginx("Cloudflare Tunnel")
        with Cluster("Docker"):
            n8n = Docker("n8n")
            ghost = Docker("Ghost Blog")
            trigger = Docker("Trigger.dev")
        db = PostgreSQL("PostgreSQL")
        cache = Redis("Redis")

    proxy >> [n8n, ghost, trigger]
    [n8n, trigger] >> db
    [n8n, trigger] >> cache
```

### Kubernetes
```python
from diagrams import Diagram
from diagrams.k8s.compute import Pod, Deployment
from diagrams.k8s.network import Service, Ingress

with Diagram("K8s Deployment", show=True):
    ing = Ingress("Ingress")
    svc = Service("Service")
    deploy = Deployment("Deployment")
    pods = [Pod("Pod 1"), Pod("Pod 2"), Pod("Pod 3")]
    ing >> svc >> deploy >> pods
```

## Workflow
1. Write the Python diagram script
2. Run: `python diagram.py`
3. The PNG is automatically saved and opened
4. Iterate based on user feedback
