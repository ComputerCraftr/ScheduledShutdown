Param (
    [ValidateSet("shutdown", "restart", IgnoreCase = $true)]
    [string]$Action = "shutdown"  # Default action
)

# Convert parameters to lowercase for consistency
$Action = $Action.ToLower()

if ($PSVersionTable.PSEdition -ne "Core") {
    Write-Output "This script requires PowerShell Core to run on macOS and Linux."
    exit
}

switch ($Action) {
    "shutdown" {
        if ($IsWindows) {
            Stop-Computer -Force
        }
        elseif ($IsMacOS -or $IsLinux) {
            sudo shutdown -h now
        }
        else {
            Write-Output "Unsupported platform for shutdown."
        }
    }
    "restart" {
        if ($IsWindows) {
            Restart-Computer -Force
        }
        elseif ($IsMacOS -or $IsLinux) {
            sudo shutdown -r now
        }
        else {
            Write-Output "Unsupported platform for restart."
        }
    }
    default {
        Write-Output "Invalid action. Use 'shutdown' or 'restart'."
    }
}
