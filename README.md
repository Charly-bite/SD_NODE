# Multipass Cluster Automation - Distributed Systems Project

This project automates the creation and management of an Ubuntu VM cluster using Multipass. It provisions VMs pre-configured for distributed system testing, complete with Docker, an NFS shared filesystem, and automated SSH access.

## Architecture

```mermaid
graph TD;
    Host("Host Machine (Windows)") --> |Scripts (setup, configure, deploy)| Node1;
    Host --> Node2;
    Host --> Node3;
    
    Node1("node1 (NFS Server, Redis, Producer)") <--> |/shared| Node2("node2 (Worker)");
    Node1 <--> |/shared| Node3("node3 (Worker)");
```

## Getting Started

Follow these steps to launch your cluster and deploy the sample app:

### 1. Setup the Cluster
Launch 3 Nodes (10GB disk each), install dependencies (Docker, NFS), configure `/etc/hosts` for direct lookups (`ping node1`), and set up passwordless SSH between all nodes.

```powershell
.\setup_cluster.ps1
```

### 2. Configure Services
Setup node1 as an NFS server, mount the `/shared` folder on node2 and node3, and verify Docker.

```powershell
.\configure_cluster.ps1
```

### 3. Deploy Sample App
Deploys a Flask API (Producer) backed by Redis on node1, and background Workers on node2 and node3. They share code via the NFS `/shared` mount.

```powershell
.\deploy_app.ps1
```

## Cluster Management

Use `manage_cluster.ps1` to easily manage the group of VMs:

```powershell
.\manage_cluster.ps1 -Action status
.\manage_cluster.ps1 -Action start
.\manage_cluster.ps1 -Action stop
.\manage_cluster.ps1 -Action restart
.\manage_cluster.ps1 -Action shell -Node node1
.\manage_cluster.ps1 -Action destroy
```

## Testing the Sample App

Once `deploy_app.ps1` is run, find the IP of `node1` (via `.\manage_cluster.ps1 -Action status`) and hit the API:

```powershell
# In PowerShell:
curl http://<node1-ip>:5000/enqueue?task=my_first_task
```
Workers on node2 and node3 will pull the job from Redis and process it. You can see their logs:
```powershell
multipass exec node2 -- cat /shared/app/worker_node2.log
```
