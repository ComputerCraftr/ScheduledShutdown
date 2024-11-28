Param (
    [ValidateSet("install", "reinstall", "uninstall", IgnoreCase = $true)]
    [string]$Action, # No default action
    [ValidateSet("shutdown", "restart", IgnoreCase = $true)]
    [string]$ScheduleType, # No default schedule type
    [string]$Time  # No default time
)

# Display help information
function Show-Help {
    Write-Output @"
Scheduled Shutdown/Restart Installer

Usage:
    pwsh installer.ps1 -Action <install|reinstall|uninstall> -ScheduleType <shutdown|restart> -Time <HH:mm>

Options:
    -Action         The action to perform: install, reinstall, or uninstall.
    -ScheduleType   The schedule type: shutdown or restart.
    -Time           The time to schedule the action in 24-hour format (HH:mm).
    -? or -Help     Display this help message.

Examples:
    Install with shutdown at 22:00:
        pwsh installer.ps1 -Action install -ScheduleType shutdown -Time 22:00

    Reinstall with restart at 08:30:
        pwsh installer.ps1 -Action reinstall -ScheduleType restart -Time 08:30

    Uninstall:
        pwsh installer.ps1 -Action uninstall
"@
}

# Helper function to detect the platform
function Get-Platform {
    if ($IsWindows) { return "Windows" }
    elseif ($IsMacOS) { return "macOS" }
    elseif ($IsLinux) { return "Linux" }
    else { return "Unsupported" }
}

# If no arguments are passed or help is requested, show help
if ($PSBoundParameters.Count -eq 0 -or $Action -eq "?" -or $Action -eq "-help") {
    Show-Help
    exit 0
}

# Validate missing parameters and provide defaults interactively
if (-not $Action) {
    $Action = Read-Host "Enter action (install, reinstall, uninstall)"
    if ($Action -notin @("install", "reinstall", "uninstall")) {
        Write-Output "Invalid action. Use 'install', 'reinstall', or 'uninstall'."
        exit 1
    }
}

# Convert parameters to lowercase for consistency
$Action = $Action.ToLower()

if ($Action -ne "uninstall") {
    if (-not $ScheduleType) {
        $ScheduleType = Read-Host "Enter schedule type (shutdown, restart)"
        if ($ScheduleType -notin @("shutdown", "restart")) {
            Write-Output "Invalid schedule type. Use 'shutdown' or 'restart'."
            exit 1
        }
    }

    # Convert parameters to lowercase for consistency
    $ScheduleType = $ScheduleType.ToLower()

    if (-not $Time) {
        $Time = Read-Host "Enter schedule time in HH:mm format (24-hour)"
    }

    # Validate time format and range (00:00 to 23:59)
    if ($Time -notmatch "^\d{2}:\d{2}$") {
        Write-Output "Invalid time format. Use HH:mm (e.g., 22:00)."
        exit 1
    }

    $Hour, $Minute = $Time.Split(":")

    if (-not ($Hour -as [int] -ge 0 -and $Hour -as [int] -lt 24)) {
        Write-Output "Invalid hour. Hour must be between 00 and 23."
        exit 1
    }

    if (-not ($Minute -as [int] -ge 0 -and $Minute -as [int] -lt 60)) {
        Write-Output "Invalid minute. Minute must be between 00 and 59."
        exit 1
    }
}

# Proceed with action logic
Write-Output "Action: $Action"
if ($Action -ne "uninstall") {
    Write-Output "Schedule Type: $ScheduleType"
    Write-Output "Time: $Time"
}

# Resolve script root path
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Resolve-Path "." }

# Define centrally managed script path and configuration files
$Platform = Get-Platform
switch ($Platform) {
    "Windows" {
        $ScriptPath = "C:\Program Files\Morgana\morgana.ps1"
        $ConfigPath = Join-Path $ScriptRoot "..\configs\windows.xml"
        $TaskName = "Morgana"
    }
    "macOS" {
        $ScriptPath = "/usr/local/bin/morgana.ps1"
        $ConfigPath = Join-Path $ScriptRoot "..\configs\macos.plist"
        $DaemonPath = "/Library/LaunchDaemons/com.user.morgana.plist"
    }
    "Linux" {
        $ScriptPath = "/usr/local/bin/morgana.ps1"
        $ConfigPath = Join-Path $ScriptRoot "..\configs"
        $SystemdService = "/etc/systemd/system/morgana.service"
        $SystemdTimer = "/etc/systemd/system/morgana.timer"
    }
    default {
        Write-Output "Unsupported platform."
        exit 1
    }
}

# Install the script to the appropriate location
function InstallScript {
    Write-Output "Installing script to $ScriptPath..."
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
    }
}

# Update platform-specific configuration files
function UpdateConfig {
    Write-Output "Updating configuration files..."
    switch ($Platform) {
        "Windows" {
            # Parse and modify the Task Scheduler XML file
            try {
                $TaskXml = New-Object System.Xml.XmlDocument
                $TaskXml.Load($ConfigPath)

                # Update the StartBoundary element
                $StartBoundaryNode = $TaskXml.SelectSingleNode("//StartBoundary")
                if ($StartBoundaryNode) {
                    $StartBoundaryNode.InnerText = "2024-11-24T$Time:00"
                }

                # Update the -Action parameter in Arguments
                $ArgumentsNode = $TaskXml.SelectSingleNode("//Actions/Exec/Arguments")
                if ($ArgumentsNode) {
                    $ArgumentsNode.InnerText = $ArgumentsNode.InnerText -replace "-Action \w+", "-Action $ScheduleType"
                }

                # Save the updated XML back to the file
                $Settings = New-Object System.Xml.XmlWriterSettings
                $Settings.Indent = $true
                $Settings.OmitXmlDeclaration = $false
                $Settings.NewLineChars = "`n"
                $Settings.CloseOutput = $true

                $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $Settings)
                $TaskXml.WriteTo($XmlWriter)
                $XmlWriter.Close()

                Write-Output "Updated Windows Task Scheduler configuration."
            }
            catch {
                Write-Error "Failed to parse or update Windows Task Scheduler XML: $_"
            }
        }
        "macOS" {
            # Parse and modify plist file as XML
            try {
                $PlistXml = New-Object System.Xml.XmlDocument
                $PlistXml.Load($ConfigPath)

                # Locate and update the ProgramArguments for the -Action parameter
                $ProgramArguments = $PlistXml.SelectNodes("//key[normalize-space(text())='ProgramArguments']")
                if ($ProgramArguments.Count -gt 0) {
                    $ArgumentsArray = $ProgramArguments[0].NextSibling
                    foreach ($Item in $ArgumentsArray.ChildNodes) {
                        if ($Item.InnerText -eq "-Action") {
                            $Item.NextSibling.InnerText = $ScheduleType
                        }
                    }
                }

                # Locate and update the StartCalendarInterval section
                $Keys = $PlistXml.SelectNodes("//key[normalize-space(text())='StartCalendarInterval']")
                if ($Keys.Count -gt 0) {
                    $StartCalendarDict = $Keys[0].NextSibling
                    foreach ($Key in $StartCalendarDict.ChildNodes) {
                        if ($Key.InnerText -eq "Hour") {
                            $Key.NextSibling.InnerText = $Hour
                        }
                        elseif ($Key.InnerText -eq "Minute") {
                            $Key.NextSibling.InnerText = $Minute
                        }
                    }
                }

                # Save changes back to the file, preserving original formatting
                $Settings = New-Object System.Xml.XmlWriterSettings
                $Settings.Indent = $true
                $Settings.OmitXmlDeclaration = $false
                $Settings.NewLineChars = "`n"
                $Settings.CloseOutput = $true

                $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $Settings)
                $PlistXml.WriteTo($XmlWriter)
                $XmlWriter.Close()

                # Remove invalid brackets from DOCTYPE
                (Get-Content $ConfigPath) `
                    -replace "\[\]", "" |
                Set-Content $ConfigPath

                Write-Output "Updated macOS plist configuration."
            }
            catch {
                Write-Error "Failed to parse or update macOS plist configuration: $_"
            }
        }
        "Linux" {
            # Replace in Linux systemd service and timer files
            $ServicePath = Join-Path $ConfigPath "linux.service"
            $TimerPath = Join-Path $ConfigPath "linux.timer"

            try {
                (Get-Content $ServicePath) `
                    -replace "ExecStart=.*", "ExecStart=/usr/bin/pwsh $ScriptPath -Action $ScheduleType" |
                Set-Content $ServicePath

                (Get-Content $TimerPath) `
                    -replace "OnCalendar=.*", "OnCalendar=*-*-* $Time:00" |
                Set-Content $TimerPath
                Write-Output "Updated Linux systemd service and timer files."
            }
            catch {
                Write-Error "Failed to parse or update Linux configuration files: $_"
            }
        }
    }
}

# Clean up files during uninstallation
function CleanupFiles {
    Write-Output "Cleaning up files..."
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
    }
}

# Manage the task/service/daemon
function ManageTask {
    Param ([string]$Action)
    Write-Output "$Action task/service/daemon for $Platform..."

    switch ($Platform) {
        "Windows" {
            if ($Action -eq "install" -or $Action -eq "reinstall") {
                if ($Action -eq "reinstall") {
                    schtasks /Delete /TN $TaskName /F
                }
                schtasks /Create /TN $TaskName /XML $ConfigPath /F
            }
            elseif ($Action -eq "uninstall") {
                schtasks /Delete /TN $TaskName /F
            }
        }
        "macOS" {
            if ($Action -eq "install" -or $Action -eq "reinstall") {
                if ($Action -eq "reinstall") {
                    sudo launchctl unload $DaemonPath
                }
                sudo cp $ConfigPath $DaemonPath
                sudo chmod 644 $DaemonPath
                sudo launchctl load $DaemonPath
            }
            elseif ($Action -eq "uninstall") {
                sudo launchctl unload $DaemonPath
            }
        }
        "Linux" {
            if ($Action -eq "install" -or $Action -eq "reinstall") {
                sudo cp (Join-Path $ConfigPath "linux.service") $SystemdService
                sudo chmod 644 $SystemdService
                sudo cp (Join-Path $ConfigPath "linux.timer") $SystemdTimer
                sudo chmod 644 $SystemdTimer
                sudo systemctl daemon-reload
                sudo systemctl enable morgana.timer
                sudo systemctl start morgana.timer
            }
            elseif ($Action -eq "uninstall") {
                sudo systemctl stop morgana.timer
                sudo systemctl disable morgana.timer
            }
        }
    }
}

# Execute the action
if ($Action -ne "uninstall") {
    InstallScript
    UpdateConfig
    ManageTask -Action $Action
}
elseif ($Action -eq "uninstall") {
    ManageTask -Action $Action
    CleanupFiles
}
