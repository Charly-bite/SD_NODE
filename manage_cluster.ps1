param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("status", "start", "stop", "restart", "shell", "destroy")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$Node = "node1"
)

$nodes = @("node1", "node2", "node3")

switch ($Action) {
    "status" {
        Write-Host "Cluster Status:" -ForegroundColor Cyan
        multipass list
    }
    "start" {
        Write-Host "Starting all nodes..." -ForegroundColor Cyan
        foreach ($n in $nodes) { multipass start $n }
    }
    "stop" {
        Write-Host "Stopping all nodes..." -ForegroundColor Cyan
        foreach ($n in $nodes) { multipass stop $n }
    }
    "restart" {
        Write-Host "Restarting all nodes..." -ForegroundColor Cyan
        foreach ($n in $nodes) { multipass restart $n }
    }
    "shell" {
        Write-Host "Opening shell on $Node..." -ForegroundColor Cyan
        multipass shell $Node
    }
    "destroy" {
        $confirm = Read-Host "Are you sure you want to destroy the entire cluster? (y/n)"
        if ($confirm -eq 'y') {
            Write-Host "Destroying and purging all nodes..." -ForegroundColor Red
            foreach ($n in $nodes) { multipass delete $n }
            multipass purge
            Write-Host "Cluster destroyed." -ForegroundColor Green
        } else {
            Write-Host "Aborted." -ForegroundColor Yellow
        }
    }
}
