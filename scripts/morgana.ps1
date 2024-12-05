Param (
    [ValidateSet("shutdown", "restart", IgnoreCase = $true)]
    [string]$Action = "shutdown"  # Default action
)

# Enable strict mode and configure error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Convert parameters to lowercase for consistency
$Action = $Action.ToLower()

# Ensure script is running on PowerShell Core
if ($PSVersionTable.PSEdition -ne "Core") {
    Write-Host "This script requires PowerShell Core to run on all platforms (Windows, macOS, Linux)."
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
                shutdown -h now
                if ($LASTEXITCODE -ne 0) { throw "Failed to perform system $Action." }
            }
            else {
                throw "Platform not supported. This script only works on Windows, macOS, or Linux."
            }
        }
        "restart" {
            if ($IsWindows) {
                Restart-Computer -Force
            }
            elseif ($IsMacOS -or $IsLinux) {
                shutdown -r now
                if ($LASTEXITCODE -ne 0) { throw "Failed to perform system $Action." }
            }
            else {
                throw "Platform not supported. This script only works on Windows, macOS, or Linux."
            }
        }
        default {
            throw "Invalid action. Use 'shutdown' or 'restart'."
        }
    }
}
catch {
    # Show only the error message, not the technical details
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
