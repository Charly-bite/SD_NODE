$ErrorActionPreference = "Stop"

$appDir = "app"
$nfsServer = "node1"
$workers = @("node2", "node3")

Write-Host "Deploying Sample Distributed App..." -ForegroundColor Cyan

# Check if app directory exists locally
if (-Not (Test-Path $appDir)) {
    Write-Error "Local app directory '$appDir' not found."
    exit 1
}

# 1. Copy app files to the shared NFS directory on node1
Write-Host "`n[1/3] Copying app files to /shared on $nfsServer..." -ForegroundColor Cyan
multipass exec $nfsServer -- sudo mkdir -p /shared/app
multipass exec $nfsServer -- sudo chmod 777 /shared/app
# We can't scp easily without ssh setup from host, so we use multipass transfer
$files = Get-ChildItem -Path $appDir -File
foreach ($file in $files) {
    Write-Host " Transferring $($file.Name)..."
    multipass transfer $file.FullName "$nfsServer`:$($file.Name)"
    multipass exec $nfsServer -- sudo cp "$($file.Name)" "/shared/app/$($file.Name)"
}

# 2. Start Redis and Producer on node1
Write-Host "`n[2/3] Starting Redis and Producer on $nfsServer..." -ForegroundColor Cyan
multipass exec $nfsServer -- sudo apt-get install -y redis-server > $null
# Listen on all interfaces
multipass exec $nfsServer -- sudo sed -i "s/bind 127.0.0.1 ::1/bind 0.0.0.0/" /etc/redis/redis.conf
multipass exec $nfsServer -- sudo systemctl restart redis-server

write-host " Installing Python requirements on $nfsServer..."
multipass exec $nfsServer -- bash -c "python3 -m venv /shared/app/venv && /shared/app/venv/bin/pip install -r /shared/app/requirements.txt"

# Kill existing producer if any
multipass exec $nfsServer -- pkill -f "producer.py" > $null 2>&1
# Start Producer
multipass exec $nfsServer -- bash -c "nohup /shared/app/venv/bin/python /shared/app/producer.py > /shared/app/producer.log 2>&1 &"
Write-Host " Producer started on node1:5000" -ForegroundColor Green

# 3. Start Workers on node2 and node3
Write-Host "`n[3/3] Starting Workers on $workers..." -ForegroundColor Cyan
foreach ($worker in $workers) {
    Write-Host " Starting worker on $worker..."
    # Need requirements on workers too (though venv is shared, python path is absolute to venv)
    # The venv is in /shared, so it's accessible.
    
    # Kill existing worker if any
    multipass exec $worker -- pkill -f "worker.py" > $null 2>&1
    # Start Worker
    multipass exec $worker -- bash -c "nohup /shared/app/venv/bin/python /shared/app/worker.py > /shared/app/worker_$worker.log 2>&1 &"
}

Write-Host "`nDeployment Complete!" -ForegroundColor Green
$node1Ip = (multipass info node1 --format csv | ConvertFrom-Csv | Select-Object -ExpandProperty IPv4 -First 1) -split ', ' | Select-Object -First 1
Write-Host "You can test the distributed task queue by running:"
Write-Host "curl http://$node1Ip:5000/enqueue?task=test_job_1"
Write-Host "`Check worker logs in /shared/app/ on any node."
