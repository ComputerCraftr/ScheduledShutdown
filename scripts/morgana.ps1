Param (
    [ValidateSet("shutdown", "restart", IgnoreCase = $true)]
    [string]$Action = "shutdown"  # Default action
)

# Enable strict mode for safer scripting
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Convert parameters to lowercase for consistency
$Action = $Action.ToLower()

# Ensure script is running on PowerShell Core
if ($PSVersionTable.PSEdition -ne "Core") {
    Write-Output "This script requires PowerShell Core to run on all platforms (Windows, macOS, Linux)."
    exit 1
}

# Perform the action based on platform and input
try {
    switch ($Action) {
        "shutdown" {
            if ($IsWindows) {
                Stop-Computer -Force
            }
            elseif ($IsMacOS -or $IsLinux) {
                sudo shutdown -h now
            }
            else {
                Write-Output "Platform not supported. This script only works on Windows, macOS, or Linux."
                exit 1
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
                Write-Output "Platform not supported. This script only works on Windows, macOS, or Linux."
                exit 1
            }
        }
        default {
            Write-Output "Invalid action. Use 'shutdown' or 'restart'."
            exit 1
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
