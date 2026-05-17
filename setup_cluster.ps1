$ErrorActionPreference = "Stop"

$nodes = @("node1", "node2", "node3")
$image = "24.04"
$cpus = 2
$memory = "2G"
$disk = "10G"
$cloudInit = "multipass-init.yaml"

Write-Host "Starting Distributed Systems Cluster Setup..." -ForegroundColor Cyan
Write-Host "Creating $image nodes with $cpus CPUs, $memory RAM, and $disk Disk each.`n"

# 1. Launch Nodes
foreach ($node in $nodes) {
    $check = multipass list --format csv | ConvertFrom-Csv | Where-Object { $_.Name -eq $node }
    if ($check) {
        Write-Host "$node already exists. Skipping launch." -ForegroundColor Yellow
    } else {
        Write-Host "Launching $node..." -ForegroundColor Green
        multipass launch $image --name $node --cpus $cpus --memory $memory --disk $disk --cloud-init $cloudInit
    }
}

Write-Host "`nWaiting for cloud-init to finish on all nodes (this might take a few minutes)..." -ForegroundColor Cyan
foreach ($node in $nodes) {
    Write-Host " Waiting for $node..."
    multipass exec $node -- cloud-init status --wait > $null
}

# 2. Get IP Addresses
Write-Host "`nGathering IP addresses..." -ForegroundColor Cyan
$ips = @{}
foreach ($node in $nodes) {
    $ipInfo = multipass info $node --format csv | ConvertFrom-Csv
    # Handling potential multiple IPs (IPv4/IPv6), taking the first valid IPv4 starting with 1
    $ip = ($ipInfo.IPv4 -split ', ' | Where-Object { $_ -match "^1" })[0]
    $ips[$node] = $ip
    Write-Host " $node : $ip"
}

# 3. Setup /etc/hosts on all nodes
Write-Host "`nConfiguring inter-node networking (/etc/hosts)..." -ForegroundColor Cyan
$hostsEntries = "`n# Multipass Cluster`n"
foreach ($node in $nodes) {
    if ($ips[$node]) {
        $hostsEntries += "$($ips[$node]) $node`n"
    }
}

foreach ($node in $nodes) {
    Write-Host " Updating $node /etc/hosts..."
    $escapedEntries = $hostsEntries -replace "`n", "\n"
    multipass exec $node -- sudo bash -c "echo -e `"$escapedEntries`" >> /etc/hosts"
}

# 4. Setup passwordless SSH between nodes
Write-Host "`nConfiguring passwordless SSH between nodes..." -ForegroundColor Cyan
# Generate a temporary SSH key locally
$keyDir = Join-Path $env:TEMP "multipass_keys"
if (!(Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir | Out-Null }
$keyFile = Join-Path $keyDir "id_rsa"
if (Test-Path $keyFile) { Remove-Item $keyFile }
if (Test-Path "$keyFile.pub") { Remove-Item "$keyFile.pub" }

Write-Host " Generating shared SSH key..."
ssh-keygen -t rsa -b 4096 -f $keyFile -N '""' -q

$privKey = Get-Content $keyFile -Raw
$pubKey = Get-Content "$keyFile.pub" -Raw

# Distribute to all nodes
foreach ($node in $nodes) {
    Write-Host " Installing SSH keys on $node..."
    # Inject private key
    multipass exec $node -- bash -c "echo `"$privKey`" > /home/distadmin/.ssh/id_rsa"
    multipass exec $node -- chmod 600 /home/distadmin/.ssh/id_rsa
    multipass exec $node -- chown distadmin:distadmin /home/distadmin/.ssh/id_rsa
    
    # Inject public key to id_rsa.pub
    multipass exec $node -- bash -c "echo `"$pubKey`" > /home/distadmin/.ssh/id_rsa.pub"
    multipass exec $node -- chmod 644 /home/distadmin/.ssh/id_rsa.pub
    multipass exec $node -- chown distadmin:distadmin /home/distadmin/.ssh/id_rsa.pub
    
    # Add to authorized_keys
    multipass exec $node -- bash -c "echo `"$pubKey`" >> /home/distadmin/.ssh/authorized_keys"
    multipass exec $node -- chmod 600 /home/distadmin/.ssh/authorized_keys
    multipass exec $node -- chown distadmin:distadmin /home/distadmin/.ssh/authorized_keys
    
    # Pre-add to known_hosts to avoid the initial prompt
    foreach ($targetNode in $nodes) {
        multipass exec $node -- sudo -u distadmin bash -c "ssh-keyscan -H $targetNode >> /home/distadmin/.ssh/known_hosts 2>/dev/null"
    }
}

# Clean up temp keys
Remove-Item -Recurse -Force $keyDir

Write-Host "`nCluster Setup Complete!" -ForegroundColor Green
Write-Host "Run .\configure_cluster.ps1 to setup shared storage (NFS) and verify Docker.`n"

multipass list
