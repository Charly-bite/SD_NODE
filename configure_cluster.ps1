$ErrorActionPreference = "Stop"

$nodes = @("node1", "node2", "node3")
$nfsServer = "node1"
$nfsClients = @("node2", "node3")

Write-Host "Configuring Services on the Multipass Cluster..." -ForegroundColor Cyan

# 1. Setup NFS Server on node1
Write-Host "`n[1/3] Configuring NFS Server on $nfsServer..." -ForegroundColor Cyan
# Add /shared to /etc/exports
multipass exec $nfsServer -- sudo bash -c "echo '/shared *(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports"
multipass exec $nfsServer -- sudo exportfs -arv
multipass exec $nfsServer -- sudo systemctl restart nfs-kernel-server

# 2. Setup NFS Clients on node2 and node3
Write-Host "`n[2/3] Configuring NFS Clients..." -ForegroundColor Cyan
foreach ($client in $nfsClients) {
    Write-Host " Mounting /shared on $client..."
    # Add to fstab to persist across reboots
    multipass exec $client -- sudo bash -c "echo '${nfsServer}:/shared /shared nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0' >> /etc/fstab"
    multipass exec $client -- sudo mount -a
}

# 3. Verify Docker on all nodes
Write-Host "`n[3/3] Verifying Docker Installation..." -ForegroundColor Cyan
foreach ($node in $nodes) {
    $dockerCheck = multipass exec $node -- docker --version
    if ($dockerCheck -match "Docker version") {
        Write-Host " ${node}: Docker is ready ($dockerCheck)" -ForegroundColor Green
    } else {
        Write-Host " ${node}: Docker check failed" -ForegroundColor Red
    }
}

Write-Host "`nConfiguration Complete!" -ForegroundColor Green
Write-Host "The directory /shared is now synced across all nodes."
Write-Host "You can verify by creating a file on node1: multipass exec node1 -- touch /shared/test.txt"
Write-Host "And checking it on node2: multipass exec node2 -- ls /shared"
