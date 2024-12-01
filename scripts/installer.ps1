Param (
    [ValidateSet("install", "reinstall", "uninstall", IgnoreCase = $true)]
    [string]$Action, # No default action
    [ValidateSet("shutdown", "restart", IgnoreCase = $true)]
    [string]$ScheduleType, # No default schedule type
    [string]$Time, # No default time
    [switch]$Help # Show help
)

# Enable strict mode and configure error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Display help information
function Show-Help {
    Write-Host @"
Scheduled Shutdown/Restart Installer

Usage:
    pwsh installer.ps1 -Action <install|reinstall|uninstall> -ScheduleType <shutdown|restart> -Time <HH:mm>

Options:
    -Action         The action to perform: install, reinstall, or uninstall.
    -ScheduleType   The schedule type: shutdown or restart.
    -Time           The time to schedule the action in 24-hour format (HH:mm).
    -Help           Display this help message.

Examples:
    Install with shutdown at 22:00:
        pwsh installer.ps1 -Action install -ScheduleType shutdown -Time 22:00

    Reinstall with restart at 08:30:
        pwsh installer.ps1 -Action reinstall -ScheduleType restart -Time 08:30

    Uninstall:
        pwsh installer.ps1 -Action uninstall
"@
    exit 0
}

# Helper function to detect the platform
function Get-Platform {
    if ($IsWindows) { return "Windows" }
    elseif ($IsMacOS) { return "macOS" }
    elseif ($IsLinux) { return "Linux" }
    else { throw "Unsupported platform." }
}

# Validate or prompt for missing parameters
function Test-Parameters {
    try {
        # Display help if the -Help switch is used
        if ($Help) {
            Show-Help
        }

        # Prompt for missing parameters interactively
        if (-not $Action) {
            $Action = Read-Host "Enter action (install, reinstall, uninstall)"
            if ($Action -notin @("install", "reinstall", "uninstall")) {
                throw "Invalid action. Use 'install', 'reinstall', or 'uninstall'."
            }
        }

        # Convert parameters to lowercase for consistency
        $Action = $Action.ToLower()

        # If Action is not uninstall, validate ScheduleType and Time
        if ($Action -ne "uninstall") {
            if (-not $ScheduleType) {
                $ScheduleType = Read-Host "Enter schedule type (shutdown, restart)"
                if ($ScheduleType -notin @("shutdown", "restart")) {
                    throw "Invalid schedule type. Use 'shutdown' or 'restart'."
                }
            }

            # Convert parameters to lowercase for consistency
            $ScheduleType = $ScheduleType.ToLower()

            if (-not $Time) {
                $Time = Read-Host "Enter schedule time in HH:mm format (24-hour)"
            }

            # Validate time format and range (00:00 to 23:59)
            if ($Time -notmatch "^\d{2}:\d{2}$") {
                throw "Invalid time format. Use HH:mm (e.g., 22:00)."
            }

            $Hour, $Minute = $Time.Split(":")
            if (-not ($Hour -as [int] -ge 0 -and $Hour -as [int] -lt 24)) {
                throw "Invalid hour. Hour must be between 00 and 23."
            }

            if (-not ($Minute -as [int] -ge 0 -and $Minute -as [int] -lt 60)) {
                throw "Invalid minute. Minute must be between 00 and 59."
            }
        }
        else {
            # Set ScheduleType and Time to null for uninstall action
            $ScheduleType = $null
            $Time = $null
        }
    }
    catch {
        throw "Parameter validation failed: $_"
    }
}

# Resolve platform-specific paths
function Resolve-Paths {
    try {
        Write-Host "Resolving paths for platform-specific configurations..."

        # Determine script root path
        $ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Resolve-Path "." }

        # Initialize platform-specific variables
        switch ($Platform) {
            "Windows" {
                $ScriptPath = "C:\Program Files\Morgana\morgana.ps1"
                $ConfigPath = Join-Path $ScriptRoot "..\configs\windows.xml"
                $TaskName = "Morgana"
                $DaemonPath = $null
                $SystemdService = $null
                $SystemdTimer = $null
            }
            "macOS" {
                $ScriptPath = "/usr/local/bin/morgana.ps1"
                $ConfigPath = Join-Path $ScriptRoot "..\configs\macos.plist"
                $DaemonPath = "/Library/LaunchDaemons/com.user.morgana.plist"
                $TaskName = $null
                $SystemdService = $null
                $SystemdTimer = $null
            }
            "Linux" {
                $ScriptPath = "/usr/local/bin/morgana.ps1"
                $ConfigPath = Join-Path $ScriptRoot "..\configs"
                $SystemdService = "/etc/systemd/system/morgana.service"
                $SystemdTimer = "/etc/systemd/system/morgana.timer"
                $TaskName = $null
                $DaemonPath = $null
            }
            default {
                throw "Unsupported platform."
            }
        }

        # Return the resolved paths as a Hashtable
        return @{
            ScriptRoot     = $ScriptRoot
            ScriptPath     = $ScriptPath
            ConfigPath     = $ConfigPath
            TaskName       = $TaskName
            DaemonPath     = $DaemonPath
            SystemdService = $SystemdService
            SystemdTimer   = $SystemdTimer
        }
    }
    catch {
        throw "Failed to resolve paths: $_"
    }
}

# Install the script to the appropriate location
function Install-Script {
    try {
        Write-Host "Installing script to $ScriptPath..."
        switch ($Platform) {
            "Windows" {
                $InstallPath = Split-Path -Parent $ScriptPath
                if (-not (Test-Path $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath -Force }
                Copy-Item (Join-Path $ScriptRoot "morgana.ps1") -Destination $ScriptPath -Force
            }
            "macOS" {
                sudo cp (Join-Path $ScriptRoot "morgana.ps1") $ScriptPath
                sudo chmod 755 $ScriptPath
            }
            "Linux" {
                sudo cp (Join-Path $ScriptRoot "morgana.ps1") $ScriptPath
                sudo chmod 755 $ScriptPath
            }
            default {
                throw "Unsupported platform."
            }
        }
    }
    catch {
        throw "Failed to install script: $_"
    }
}

function Update-Config {
    try {
        Write-Host "Updating configuration files for $Platform..."

        switch ($Platform) {
            "Windows" {
                try {
                    Write-Host "Updating Windows Task Scheduler XML configuration..."
                    $TaskXml = New-Object System.Xml.XmlDocument
                    $TaskXml.Load($ConfigPath)

                    # Update StartBoundary for scheduling
                    $StartBoundaryNode = $TaskXml.SelectSingleNode("//StartBoundary")
                    if ($StartBoundaryNode) {
                        $StartBoundaryNode.InnerText = "2024-11-24T$Time:00"
                        Write-Host "Updated StartBoundary: $StartBoundaryNode.InnerText"
                    }

                    # Update the -Action parameter in Arguments
                    $ArgumentsNode = $TaskXml.SelectSingleNode("//Actions/Exec/Arguments")
                    if ($ArgumentsNode) {
                        $ArgumentsNode.InnerText = $ArgumentsNode.InnerText -replace "-Action \w+", "-Action $ScheduleType"
                        Write-Host "Updated Arguments: $ArgumentsNode.InnerText"
                    }

                    # Save updated XML
                    $Settings = New-Object System.Xml.XmlWriterSettings
                    $Settings.Indent = $true
                    $Settings.OmitXmlDeclaration = $false
                    $Settings.NewLineChars = "`n"
                    $Settings.CloseOutput = $true

                    $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $Settings)
                    $TaskXml.WriteTo($XmlWriter)
                    $XmlWriter.Close()

                    Write-Host "Windows Task Scheduler configuration updated successfully."
                }
                catch {
                    throw "Failed to update Windows Task Scheduler configuration: $_"
                }
            }
            "macOS" {
                try {
                    Write-Host "Updating macOS plist configuration..."
                    $Hour, $Minute = $Time.Split(":")
                    $PlistXml = New-Object System.Xml.XmlDocument
                    $PlistXml.Load($ConfigPath)

                    # Update ProgramArguments for the -Action parameter
                    $ProgramArguments = $PlistXml.SelectNodes("//key[normalize-space(text())='ProgramArguments']")
                    if ($ProgramArguments.Count -gt 0) {
                        $ArgumentsArray = $ProgramArguments[0].NextSibling
                        foreach ($Item in $ArgumentsArray.ChildNodes) {
                            if ($Item.InnerText -eq "-Action") {
                                $Item.NextSibling.InnerText = $ScheduleType
                                Write-Host "Updated ProgramArguments: $ScheduleType"
                            }
                        }
                    }

                    # Update StartCalendarInterval
                    $Keys = $PlistXml.SelectNodes("//key[normalize-space(text())='StartCalendarInterval']")
                    if ($Keys.Count -gt 0) {
                        $StartCalendarDict = $Keys[0].NextSibling
                        foreach ($Key in $StartCalendarDict.ChildNodes) {
                            if ($Key.InnerText -eq "Hour") {
                                $Key.NextSibling.InnerText = $Hour
                                Write-Host "Updated Hour: $Hour"
                            }
                            elseif ($Key.InnerText -eq "Minute") {
                                $Key.NextSibling.InnerText = $Minute
                                Write-Host "Updated Minute: $Minute"
                            }
                        }
                    }

                    # Save plist changes
                    $Settings = New-Object System.Xml.XmlWriterSettings
                    $Settings.Indent = $true
                    $Settings.OmitXmlDeclaration = $false
                    $Settings.NewLineChars = "`n"
                    $Settings.CloseOutput = $true

                    $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $Settings)
                    $PlistXml.WriteTo($XmlWriter)
                    $XmlWriter.Close()

                    # Remove invalid brackets in plist (if any)
                    $(Get-Content $ConfigPath) `
                        -replace '\[\]', '' |
                    Set-Content $ConfigPath

                    Write-Host "macOS plist configuration updated successfully."
                }
                catch {
                    throw "Failed to update macOS plist configuration: $_"
                }
            }
            "Linux" {
                try {
                    Write-Host "Updating Linux systemd service and timer files..."
                    $ServicePath = Join-Path $ConfigPath "linux.service"
                    $TimerPath = Join-Path $ConfigPath "linux.timer"

                    # Update systemd service file
                    $(Get-Content $ServicePath) `
                        -replace "ExecStart=.*", "ExecStart=/usr/bin/pwsh $ScriptPath -Action $ScheduleType" |
                    Set-Content $ServicePath
                    Write-Host "Updated systemd service ExecStart."

                    # Update systemd timer file
                    $(Get-Content $TimerPath) `
                        -replace "OnCalendar=.*", "OnCalendar=*-*-* $Time:00" |
                    Set-Content $TimerPath
                    Write-Host "Updated systemd timer OnCalendar."

                    Write-Host "Linux systemd service and timer files updated successfully."
                }
                catch {
                    throw "Failed to update Linux systemd configuration files: $_"
                }
            }
            default {
                throw "Unsupported platform for configuration updates."
            }
        }
    }
    catch {
        throw "An error occurred while updating platform-specific configuration files: $_"
    }
}

# Clean up files during uninstallation
function Remove-Files {
    try {
        Write-Host "Cleaning up files..."
        switch ($Platform) {
            "Windows" {
                if (Test-Path $ScriptPath) { Remove-Item $ScriptPath -Force }
                if (Test-Path $ConfigPath) { Remove-Item $ConfigPath -Force }
            }
            "macOS" {
                if (Test-Path $ScriptPath) { sudo rm $ScriptPath }
                if (Test-Path $DaemonPath) { sudo rm $DaemonPath }
            }
            "Linux" {
                if (Test-Path $ScriptPath) { sudo rm $ScriptPath }
                if (Test-Path $SystemdService) { sudo rm $SystemdService }
                if (Test-Path $SystemdTimer) { sudo rm $SystemdTimer }
                sudo systemctl daemon-reload
            }
            default {
                throw "Unsupported platform."
            }
        }
    }
    catch {
        throw "Failed to clean up files: $_"
    }
}

# Manage the task/service/daemon
function Set-Task {
    Param ([string]$Action)

    try {
        Write-Host "$Action task/service/daemon for $Platform..."

        switch ($Platform) {
            "Windows" {
                if ($Action -eq "install" -or $Action -eq "reinstall") {
                    if ($Action -eq "reinstall") {
                        Write-Host "Removing existing task..."
                        schtasks /Delete /TN $TaskName /F
                    }
                    Write-Host "Creating new task..."
                    schtasks /Create /TN $TaskName /XML $ConfigPath /F
                }
                elseif ($Action -eq "uninstall") {
                    Write-Host "Deleting task..."
                    schtasks /Delete /TN $TaskName /F
                }
            }
            "macOS" {
                if ($Action -eq "install" -or $Action -eq "reinstall") {
                    if ($Action -eq "reinstall") {
                        Write-Host "Unloading existing daemon..."
                        sudo launchctl unload $DaemonPath
                    }
                    Write-Host "Installing and loading new daemon..."
                    sudo cp $ConfigPath $DaemonPath
                    sudo chmod 644 $DaemonPath
                    sudo launchctl load $DaemonPath
                }
                elseif ($Action -eq "uninstall") {
                    Write-Host "Unloading and removing daemon..."
                    sudo launchctl unload $DaemonPath
                    sudo rm $DaemonPath
                }
            }
            "Linux" {
                if ($Action -eq "install" -or $Action -eq "reinstall") {
                    Write-Host "Setting up systemd service and timer..."
                    sudo cp (Join-Path $ConfigPath "linux.service") $SystemdService
                    sudo chmod 644 $SystemdService
                    sudo cp (Join-Path $ConfigPath "linux.timer") $SystemdTimer
                    sudo chmod 644 $SystemdTimer
                    sudo systemctl daemon-reload
                    sudo systemctl enable morgana.timer
                    sudo systemctl start morgana.timer
                }
                elseif ($Action -eq "uninstall") {
                    Write-Host "Stopping and disabling systemd timer..."
                    sudo systemctl stop morgana.timer
                    sudo systemctl disable morgana.timer
                    Write-Host "Removing service and timer files..."
                    sudo rm $SystemdService $SystemdTimer
                    sudo systemctl daemon-reload
                }
            }
            default {
                throw "Unsupported platform."
            }
        }
    }
    catch {
        throw "Failed to manage task/service/daemon: $_"
    }
}

# Main logic
try {
    Test-Parameters

    Set-Variable -Name "Platform" -Value $(Get-Platform) -Option Constant
    $Paths = Resolve-Paths

    # Access individual entries from the Hashtable
    Set-Variable -Name "ScriptRoot" -Value $Paths["ScriptRoot"] -Option Constant
    Set-Variable -Name "ScriptPath" -Value $Paths["ScriptPath"] -Option Constant
    Set-Variable -Name "ConfigPath" -Value $Paths["ConfigPath"] -Option Constant
    Set-Variable -Name "TaskName" -Value $Paths["TaskName"] -Option Constant
    Set-Variable -Name "DaemonPath" -Value $Paths["DaemonPath"] -Option Constant
    Set-Variable -Name "SystemdService" -Value $Paths["SystemdService"] -Option Constant
    Set-Variable -Name "SystemdTimer" -Value $Paths["SystemdTimer"] -Option Constant

    Write-Host "Action: $Action"
    if ($Action -ne "uninstall") {
        Write-Host "Schedule Type: $ScheduleType"
        Write-Host "Time: $Time"
    }

    if ($Action -ne "uninstall") {
        Install-Script
        Update-Config
        Set-Task -Action $Action
    }
    else {
        Set-Task -Action $Action
        Remove-Files
    }
}
catch {
    # Show only the error message, not the technical details
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
