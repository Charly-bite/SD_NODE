# Multipass Distributed Cluster — AI Replication Context

> Use this file as context when replicating this exact setup on a new Windows system.
> Feed this entire file to the AI assistant at the start of the conversation.

---

## Overview

This project creates a **3-node distributed system cluster** using Canonical Multipass on Windows. The nodes run Ubuntu 24.04 and are configured with:
- **NFS shared storage** (`/shared`) across all nodes
- **Passwordless SSH** between all nodes
- **Docker** on every node
- **Redis-based distributed task queue** (producer on node1, workers on node2/node3)

---

## File Structure

```
Multipass_Cluster/
├── multipass-init.yaml       # Cloud-init: creates user, installs packages
├── setup_cluster.ps1         # Step 1: Launch nodes, configure /etc/hosts, SSH keys
├── configure_cluster.ps1     # Step 2: Setup NFS server/client, verify Docker
├── deploy_app.ps1            # Step 3: Deploy Redis + Python task queue app
├── manage_cluster.ps1        # Utility: start/stop/restart/status/destroy cluster
├── app/
│   ├── producer.py           # Flask API that enqueues tasks to Redis
│   ├── worker.py             # Python worker that consumes tasks from Redis
│   └── requirements.txt      # flask, redis
```

---

## Execution Order

```
1. .\setup_cluster.ps1        # Launch VMs, /etc/hosts, SSH keys
2. .\configure_cluster.ps1    # NFS + Docker verification
3. .\deploy_app.ps1           # Transfer app, install Redis, start services
4. (Manual) Create systemd services for producer/workers
5. (Manual) Fix Redis bind address and protected-mode
```

---

## Known Errors & Required Fixes

### Error 1: PowerShell Variable Interpolation (configure_cluster.ps1)

**Symptom:** `Variable reference is not valid. ':' was not followed by a valid variable name character.`

**Cause:** PowerShell interprets `$variable:` as a drive/scope qualifier (e.g., `$env:PATH`).

**Fix:** Use `${variable}` syntax anywhere a variable is immediately followed by a colon.

```diff
# configure_cluster.ps1 line 21 (NFS fstab entry)
- multipass exec $client -- sudo bash -c "echo '$nfsServer:/shared /shared nfs ...' >> /etc/fstab"
+ multipass exec $client -- sudo bash -c "echo '${nfsServer}:/shared /shared nfs ...' >> /etc/fstab"

# configure_cluster.ps1 lines 30, 32 (Docker version output)
- Write-Host " $node: Docker is ready ($dockerCheck)"
+ Write-Host " ${node}: Docker is ready ($dockerCheck)"
```

---

### Error 2: Invalid Redis Bind Address (deploy_app.ps1)

**Symptom:** Redis binds to `0.0.0.1` (invalid) instead of `0.0.0.0`.

**Cause:** Typo in the original script.

**Fix:**
```diff
# deploy_app.ps1 line 31
- multipass exec $nfsServer -- sudo sed -i "s/bind 127.0.0.1 ::1/bind 0.0.0.1/" /etc/redis/redis.conf
+ multipass exec $nfsServer -- sudo sed -i "s/bind 127.0.0.1 ::1/bind 0.0.0.0/" /etc/redis/redis.conf
```

---

### Error 3: Redis sed Replacement Doesn't Match (runtime)

**Symptom:** Workers on node2/node3 get `ConnectionError: Connection closed` when connecting to Redis on node1.

**Cause:** The `sed` command in `deploy_app.ps1` tries to replace `bind 127.0.0.1 ::1` but the actual redis.conf on Ubuntu 24.04 uses a different format (comments, no active bind line). The replacement silently does nothing.

**Fix (manual, after deploy_app.ps1 runs):**
```powershell
multipass exec node1 -- sudo bash -c "echo 'bind 0.0.0.0' >> /etc/redis/redis.conf"
multipass exec node1 -- sudo bash -c "echo 'protected-mode no' >> /etc/redis/redis.conf"
multipass exec node1 -- sudo systemctl restart redis-server
```

**Verify:**
```powershell
multipass exec node1 -- sudo ss -tlnp | findstr 6379
# Expected: LISTEN 0 511 0.0.0.0:6379 0.0.0.0:*
```

---

### Error 4: SFTP Transfer Permission Denied (deploy_app.ps1)

**Symptom:** `[error] [sftp] cannot ... SFTP server: Permission denied`

**Cause:** `multipass transfer` uploads to the default user's home directory. The original script used the path `$nfsServer:/home/distadmin/file` which failed because multipass SFTP does not resolve to that path correctly.

**Fix:**
```diff
# deploy_app.ps1 lines 23-24
- multipass transfer $file.FullName "$nfsServer`:/home/distadmin/$($file.Name)"
- multipass exec $nfsServer -- sudo cp "/home/distadmin/$($file.Name)" "/shared/app/$($file.Name)"
+ multipass transfer $file.FullName "$nfsServer`:$($file.Name)"
+ multipass exec $nfsServer -- sudo cp "$($file.Name)" "/shared/app/$($file.Name)"
```

Also add `chmod 777` after creating the target directory:
```diff
  multipass exec $nfsServer -- sudo mkdir -p /shared/app
+ multipass exec $nfsServer -- sudo chmod 777 /shared/app
```

---

### Error 5: nohup Processes Die After multipass exec Ends

**Symptom:** `producer.log` and `worker_nodeX.log` files are never created. Processes don't survive.

**Cause:** `multipass exec -- bash -c "nohup ... &"` does NOT persist background processes. When the exec session ends, the bash process and all its children are terminated.

**Fix:** Use **systemd service units** instead of nohup. Create these AFTER `deploy_app.ps1` finishes:

**Producer service (node1):**
```ini
# /etc/systemd/system/producer.service
[Unit]
Description=Distributed Task Queue Producer
After=network.target

[Service]
Type=simple
User=distadmin
WorkingDirectory=/shared/app
ExecStart=/shared/app/venv/bin/python /shared/app/producer.py
Restart=always
RestartSec=3
StandardOutput=append:/shared/app/producer.log
StandardError=append:/shared/app/producer.log

[Install]
WantedBy=multi-user.target
```

**Worker service (node2 and node3):**
```ini
# /etc/systemd/system/worker.service
[Unit]
Description=Distributed Task Queue Worker
After=network.target

[Service]
Type=simple
User=distadmin
WorkingDirectory=/shared/app
ExecStart=/shared/app/venv/bin/python /shared/app/worker.py
Restart=always
RestartSec=3
StandardOutput=append:/shared/app/worker.log
StandardError=append:/shared/app/worker.log

[Install]
WantedBy=multi-user.target
```

**Deploy commands:**
```powershell
# On node1
multipass exec node1 -- sudo bash -c "cat > /etc/systemd/system/producer.service << 'EOF'
<paste producer.service content>
EOF"
multipass exec node1 -- sudo systemctl daemon-reload
multipass exec node1 -- sudo systemctl restart producer.service

# On node2 (repeat for node3)
multipass exec node2 -- sudo bash -c "cat > /etc/systemd/system/worker.service << 'EOF'
<paste worker.service content>
EOF"
multipass exec node2 -- sudo systemctl daemon-reload
multipass exec node2 -- sudo systemctl restart worker.service
```

---

## Verification Checklist

After completing all steps, verify:

```powershell
# 1. All nodes are running
multipass list

# 2. Nodes can ping each other by hostname
multipass exec node2 -- ping -c 2 node1
multipass exec node3 -- ping -c 2 node1

# 3. NFS shared storage works
multipass exec node1 -- touch /shared/test.txt
multipass exec node3 -- ls /shared/test.txt

# 4. Redis is listening on all interfaces
multipass exec node1 -- sudo ss -tlnp | findstr 6379

# 5. Producer API is responding
multipass exec node1 -- curl -s http://127.0.0.1:5000/

# 6. Submit test jobs and check worker logs
multipass exec node1 -- curl -s http://127.0.0.1:5000/enqueue?task=TestJob1
multipass exec node1 -- curl -s http://127.0.0.1:5000/enqueue?task=TestJob2
Start-Sleep -Seconds 5
multipass exec node2 -- cat /shared/app/worker.log
multipass exec node3 -- cat /shared/app/worker.log
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Windows Host (Multipass)                  │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │    node1      │  │    node2      │  │    node3      │    │
│  │  Ubuntu 24.04 │  │  Ubuntu 24.04 │  │  Ubuntu 24.04 │   │
│  │               │  │               │  │               │    │
│  │  Redis :6379  │  │  Worker.py    │  │  Worker.py    │    │
│  │  Flask :5000  │  │  (systemd)    │  │  (systemd)    │    │
│  │  NFS Server   │  │  NFS Client   │  │  NFS Client   │    │
│  │  Docker       │  │  Docker       │  │  Docker       │    │
│  │               │  │               │  │               │    │
│  │  /shared ◄────┼──┼── /shared     │  │  /shared      │    │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         ▲                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│              Passwordless SSH + /etc/hosts                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Cloud-Init User

- **Username:** `distadmin`
- **Password:** `tera`
- **Groups:** sudo, docker
- **SSH dir:** `/home/distadmin/.ssh/` (pre-created by cloud-init)
