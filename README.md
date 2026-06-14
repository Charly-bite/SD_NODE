# SD_NODE: Distributed Cluster Management & Task Queue System

`SD_NODE` is a lightweight, automated infrastructure-as-code and orchestration setup designed to deploy and manage a distributed cluster of Virtual Machines (VMs) using Canonical's **Multipass**. The system sets up a multi-node network complete with shared network filesystems (NFS), inter-node passwordless SSH, a Redis-backed distributed task queue, and producer/worker execution roles.

---

## System Architecture

The cluster consists of three Ubuntu virtual machine nodes (`node1`, `node2`, and `node3`) configured in a local private network:

```mermaid
graph TD
    subgraph Host OS (Windows)
        P[setup_cluster.ps1] -->|Orchestrates| N1[node1 - Master]
        P -->|Orchestrates| N2[node2 - Worker 1]
        P -->|Orchestrates| N3[node3 - Worker 2]
    end

    subgraph node1 [node1: Master Node]
        R[(Redis Server)]
        F[Flask Producer App]
    end

    subgraph node2 [node2: Worker Node 1]
        W1[Python Worker 1]
    end

    subgraph node3 [node3: Worker Node 2]
        W2[Python Worker 2]
    end

    %% NFS Storage
    NFS[Shared NFS Storage: /shared]
    N1 ====>|NFS Export Host| NFS
    N2 ====>|NFS Client Mount| NFS
    N3 ====>|NFS Client Mount| NFS

    %% Task Queue flow
    F -->|Enqueue Tasks| R
    W1 -.->|BRPOP task_queue| R
    W2 -.->|BRPOP task_queue| R

    style node1 fill:#1c2438,stroke:#34495e,stroke-width:2px;
    style node2 fill:#1c2438,stroke:#34495e,stroke-width:2px;
    style node3 fill:#1c2438,stroke:#34495e,stroke-width:2px;
    style NFS fill:#1b4f72,stroke:#1f618d,stroke-width:2px;
    style R fill:#78281f,stroke:#922b21,stroke-width:2px;
    style F fill:#196f3d,stroke:#1e8449,stroke-width:2px;
```

### Components:
*   **`node1` (Master Node)**: Hosts the Redis server and the Flask-based producer endpoint. Also serves as the NFS host, sharing the `/shared` folder with the worker nodes.
*   **`node2` & `node3` (Worker Nodes)**: Mount the shared NFS storage `/shared` and run independent worker processes to pull and execute tasks from the Redis queue.
*   **Shared NFS Storage (`/shared`)**: Serves to unify the application directory, virtual environment, and logs across the cluster nodes.

---

## File Structure

```
SD_NODE/
│
├── app/                        # Distributed task application files
│   ├── producer.py             # Flask Web API to enqueue tasks
│   ├── worker.py               # Redis-blocking task processing daemon
│   └── requirements.txt        # Python dependency file (flask, redis, etc.)
│
├── setup_cluster.ps1           # Launches VMs, configures /etc/hosts, sets up SSH
├── configure_cluster.ps1       # Configures NFS shared storage & checks Docker
├── manage_cluster.ps1          # Control panel utility to start/stop/shell/destroy cluster
├── deploy_app.ps1              # Deploys application, configures Redis, starts processes
├── multipass-init.yaml         # Cloud-init file for VM configuration
├── documentacion_cluster.tex   # LaTeX technical cluster documentation
└── README.md                   # This instruction manual
```

---

## Prerequisites

Before setting up the cluster, ensure you have the following installed on your local host:
1. **Windows PowerShell** (run as Administrator to perform VM commands if required).
2. **Multipass**: [Download and Install Multipass](https://multipass.run/).
3. **Git** (optional, for code management).

---

## Quick Start Guide

Follow these steps in sequence to provision the cluster, set up network filesystems, deploy the Redis task queue, and run workers.

### Step 1: Provision the VM Cluster
Run the initialization script. This launches three Ubuntu `24.04` VMs, sets up inter-node name resolution `/etc/hosts`, and configures passwordless SSH communication between them.
```powershell
.\setup_cluster.ps1
```

### Step 2: Configure Shared Storage & Services
Run the configuration script to format and export `/shared` directory from `node1` to the other two client nodes, and inspect Docker status on each machine:
```powershell
.\configure_cluster.ps1
```

### Step 3: Deploy the Distributed Application
Deploy the task queue code, configure Redis, create the shared Python virtual environment, and spawn background processes (producer on `node1`, workers on `node2` and `node3`):
```powershell
.\deploy_app.ps1
```

---

## Testing & Verifying the Task Queue

1. Find the IP of `node1` by listing the cluster:
   ```powershell
   multipass list
   ```
2. Trigger the task producer endpoint using `curl` or your browser:
   ```bash
   curl "http://<node1-ip>:5000/enqueue?task=my_test_job_101"
   ```
3. Watch task worker logs in real time from the shared NFS workspace to verify task consumption:
   ```bash
   # Enter any worker node shell
   .\manage_cluster.ps1 -Action shell -Node node2
   
   # View worker logs
   cat /shared/app/worker_node2.log
   ```

---

## Management Operations

Use the `manage_cluster.ps1` helper script to control the state of the cluster VMs:

*   **View Cluster VM Status**:
    ```powershell
    .\manage_cluster.ps1 -Action status
    ```
*   **Stop All Nodes**:
    ```powershell
    .\manage_cluster.ps1 -Action stop
    ```
*   **Start All Nodes**:
    ```powershell
    .\manage_cluster.ps1 -Action start
    ```
*   **Restart All Nodes**:
    ```powershell
    .\manage_cluster.ps1 -Action restart
    ```
*   **Log Into a Node's Shell**:
    ```powershell
    .\manage_cluster.ps1 -Action shell -Node node1
    ```
*   **Destroy the Entire Cluster**:
    ```powershell
    .\manage_cluster.ps1 -Action destroy
    ```

---

## Technical Details

### Cloud-Init Configuration
The provisioning relies on `multipass-init.yaml` which performs early-boot steps:
- Creates a dedicated cluster administrator user `distadmin`.
- Updates base packages and installs essential networking and server utilities (`nfs-kernel-server`, `nfs-common`, `docker.io`, `python3-pip`, `python3-venv`).
- Pre-creates directory trees `/shared` with open execution privileges.