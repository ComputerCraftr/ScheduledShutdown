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

        # Return updated parameters
        return @{
            ProgAction       = $Action
            ProgScheduleType = $ScheduleType
            ProgTime         = $Time
        }
    }
    catch {
        throw "Parameter validation failed: $_"
    }
}

# Resolve platform-specific paths
function Resolve-Paths {
    try {
        # Validate the script name
        if ([string]::IsNullOrWhiteSpace($ScriptName) -or $ScriptName -notmatch "^[a-z0-9_-]+$") {
            throw "Invalid script name. It must not be empty or null, contain spaces, and only include lowercase letters, numbers, underscores, or hyphens (e.g., 'morgana')."
        }

        Write-Host "Resolving paths for platform-specific configurations..."

        # Determine script root path
        $ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Resolve-Path "." }

        # Common paths for pwsh
        $PossiblePaths = @(
            "/usr/bin/pwsh",
            "/usr/local/bin/pwsh",
            "/snap/bin/pwsh"
        )

        # Attempt to resolve pwsh path
        $PwshPath = $null
        foreach ($Path in $PossiblePaths) {
            if (Test-Path $Path) {
                $PwshPath = $Path
                break
            }
        }

        # Fallback to Get-Command
        if (-not $PwshPath) {
            $PwshPath = (Get-Command pwsh).Source
        }

        # Define common values
        $BaseName = $ScriptName
        $BaseNameUpper = $BaseName.Substring(0, 1).ToUpper() + $BaseName.Substring(1)
        $ScriptFileName = "$BaseName.ps1"

        # Resolve platform-specific paths
        $Paths = switch ($Platform) {
            "Windows" {
                @{
                    ScriptRoot     = $ScriptRoot
                    ScriptPath     = "C:\Program Files\$BaseNameUpper\$ScriptFileName"
                    ConfigPath     = Join-Path $ScriptRoot "..\configs\windows.xml"
                    PwshPath       = $PwshPath
                    TaskName       = $BaseNameUpper
                    DaemonPath     = $null
                    SystemdService = $null
                    SystemdTimer   = $null
                }
            }
            "macOS" {
                @{
                    ScriptRoot     = $ScriptRoot
                    ScriptPath     = "/usr/local/bin/$ScriptFileName"
                    ConfigPath     = Join-Path $ScriptRoot "..\configs\macos.plist"
                    PwshPath       = $PwshPath
                    DaemonPath     = "/Library/LaunchDaemons/com.user.$BaseName.plist"
                    TaskName       = $null
                    SystemdService = $null
                    SystemdTimer   = $null
                }
            }
            "Linux" {
                @{
                    ScriptRoot     = $ScriptRoot
                    ScriptPath     = "/usr/local/bin/$ScriptFileName"
                    ConfigPath     = Join-Path $ScriptRoot "..\configs"
                    PwshPath       = $PwshPath
                    SystemdService = "/etc/systemd/system/$BaseName.service"
                    SystemdTimer   = "/etc/systemd/system/$BaseName.timer"
                    TaskName       = $null
                    DaemonPath     = $null
                }
            }
            default { throw "Unsupported platform." }
        }

        # Return the resolved paths as a Hashtable
        return $Paths
    }
    catch {
        throw "Failed to resolve paths: $_"
    }
}

# Install the script to the appropriate location
function Install-Script {
    try {
        # Validate the script name
        if ([string]::IsNullOrWhiteSpace($ScriptName) -or $ScriptName -notmatch "^[a-z0-9_-]+$") {
            throw "Invalid script name. It must not be empty or null, contain spaces, and only include lowercase letters, numbers, underscores, or hyphens (e.g., 'morgana')."
        }

        # Determine script file and destination path
        $ScriptFileName = "$ScriptName.ps1"
        $SourcePath = Join-Path $ScriptRoot $ScriptFileName
        if (-not (Test-Path $SourcePath)) {
            throw "Source script not found: $SourcePath"
        }

        Write-Host "Installing script to $ScriptPath..."

        # Installation logic
        switch ($Platform) {
            "Windows" {
                # Create the target directory if it doesn't exist
                $InstallPath = Split-Path -Parent $ScriptPath
                if (-not (Test-Path $InstallPath)) {
                    Write-Host "Creating directory: $InstallPath"
                    New-Item -ItemType Directory -Path $InstallPath -Force
                }

                # Copy the script
                Copy-Item -Path $SourcePath -Destination $ScriptPath -Force

                # Resolve SIDs to localized group names
                $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
                $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount]).Value

                $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
                $userGroup = $userSID.Translate([System.Security.Principal.NTAccount]).Value

                # Set ownership to Administrators
                $acl = Get-Acl $ScriptPath
                $acl.SetOwner([System.Security.Principal.NTAccount]$adminGroup)
                Set-Acl -Path $ScriptPath -AclObject $acl

                # Define permissions as a hashtable
                $permissions = @{
                    Admin = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $adminGroup,
                        [System.Security.AccessControl.FileSystemRights]::FullControl,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                    User  = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $userGroup,
                        [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }

                # Apply permissions
                foreach ($key in $permissions.Keys) {
                    $permission = $permissions[$key]
                    Write-Host "Applying permission for $($key): $($permission.IdentityReference)"
                    $acl.AddAccessRule($permission)
                }

                # Apply the updated ACL to the file
                Set-Acl -Path $ScriptPath -AclObject $acl

                Write-Host "Set permissions for: $ScriptPath"
            }
            "macOS" {
                # Copy the script
                Copy-Item -Path $SourcePath -Destination $ScriptPath -Force
                if (-not (Test-Path $ScriptPath)) { throw "Failed to copy script to: $ScriptPath" }

                # Set ownership and permissions
                chown root $ScriptPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set owner for: $ScriptPath" }
                chmod 755 $ScriptPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set permissions for: $ScriptPath" }

                # Copy and configure daemon
                Copy-Item -Path $ConfigPath -Destination $DaemonPath -Force
                if (-not (Test-Path $DaemonPath)) { throw "Failed to copy daemon to: $DaemonPath" }
                chown root $DaemonPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set owner for: $DaemonPath" }
                chmod 644 $DaemonPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set permissions for: $DaemonPath" }
            }
            "Linux" {
                # Copy the script
                Copy-Item -Path $SourcePath -Destination $ScriptPath -Force
                if (-not (Test-Path $ScriptPath)) { throw "Failed to copy script to: $ScriptPath" }

                # Set ownership and permissions
                chown root $ScriptPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set owner for: $ScriptPath" }
                chmod 755 $ScriptPath
                if ($LASTEXITCODE -ne 0) { throw "Failed to set permissions for: $ScriptPath" }

                # Copy and configure systemd service and timer
                Copy-Item -Path (Join-Path $ConfigPath "linux.service") -Destination $SystemdService -Force
                if (-not (Test-Path $SystemdService)) { throw "Failed to copy service to: $SystemdService" }
                chown root $SystemdService
                if ($LASTEXITCODE -ne 0) { throw "Failed to set owner for: $SystemdService" }
                chmod 644 $SystemdService
                if ($LASTEXITCODE -ne 0) { throw "Failed to set permissions for: $SystemdService" }

                Copy-Item -Path (Join-Path $ConfigPath "linux.timer") -Destination $SystemdTimer -Force
                if (-not (Test-Path $SystemdTimer)) { throw "Failed to copy timer to: $SystemdTimer" }
                chown root $SystemdTimer
                if ($LASTEXITCODE -ne 0) { throw "Failed to set owner for: $SystemdTimer" }
                chmod 644 $SystemdTimer
                if ($LASTEXITCODE -ne 0) { throw "Failed to set permissions for: $SystemdTimer" }

                # Reload systemd daemon
                systemctl daemon-reload
                if ($LASTEXITCODE -ne 0) { throw "Failed to reload systemd daemon" }
            }
            default {
                throw "Unsupported platform."
            }
        }

        Write-Host "Script installed successfully to $ScriptPath."
    }
    catch {
        throw "Failed to install script: $_"
    }
}

function Update-Config {
    Write-Host "Updating configuration files for $Platform..."

    switch ($Platform) {
        "Windows" {
            try {
                Write-Host "Updating Windows Task Scheduler XML configuration..."

                # Load the XML document
                $TaskXml = New-Object System.Xml.XmlDocument
                $TaskXml.Load($ConfigPath)

                # Define namespace manager
                $NamespaceManager = New-Object System.Xml.XmlNamespaceManager($TaskXml.NameTable)
                $NamespaceManager.AddNamespace("task", "http://schemas.microsoft.com/windows/2004/02/mit/task")

                # Update StartBoundary for scheduling
                $StartBoundaryNode = $TaskXml.SelectSingleNode("//task:StartBoundary", $NamespaceManager)
                if (-not $StartBoundaryNode) {
                    throw "StartBoundary node not found in XML."
                }
                $StartBoundaryNode.InnerText = "2024-11-24T$($ProgTime):00"
                Write-Host "Updated StartBoundary: $($StartBoundaryNode.InnerText)"

                # Update the -Action parameter in Arguments
                $ArgumentsNode = $TaskXml.SelectSingleNode("//task:Actions/task:Exec/task:Arguments", $NamespaceManager)
                if (-not $ArgumentsNode) {
                    throw "Arguments node not found in XML."
                }
                $ArgumentsNode.InnerText = $ArgumentsNode.InnerText -replace "-Action \S+", "-Action $ProgScheduleType"
                Write-Host "Updated Arguments: $($ArgumentsNode.InnerText)"

                # Save updated XML with correct encoding
                $Settings = New-Object System.Xml.XmlWriterSettings
                $Settings.Indent = $true
                $Settings.OmitXmlDeclaration = $false
                $Settings.NewLineChars = "`n"
                $Settings.Encoding = [System.Text.Encoding]::Unicode  # Ensure UTF-16 LE with BOM
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
                $Hour, $Minute = $ProgTime.Split(":")
                $PlistXml = New-Object System.Xml.XmlDocument
                $PlistXml.Load($ConfigPath)

                # Update ProgramArguments for the -Action parameter
                $ProgramArguments = $PlistXml.SelectNodes("//key[normalize-space(text())='ProgramArguments']")
                if ($ProgramArguments.Count -gt 0) {
                    $ArgumentsArray = $ProgramArguments[0].NextSibling
                    $ArgumentsArray.FirstChild.InnerText = $PwshPath
                    foreach ($Item in $ArgumentsArray.ChildNodes) {
                        if ($Item.InnerText -eq "-File") {
                            $Item.NextSibling.InnerText = $ScriptPath
                            Write-Host "Updated ProgramArguments: $ScriptPath"
                        }
                        if ($Item.InnerText -eq "-Action") {
                            $Item.NextSibling.InnerText = $ProgScheduleType
                            Write-Host "Updated ProgramArguments: $ProgScheduleType"
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

                # Save plist changes with correct encoding
                $Settings = New-Object System.Xml.XmlWriterSettings
                $Settings.Indent = $true
                $Settings.OmitXmlDeclaration = $false
                $Settings.NewLineChars = "`n"
                $Settings.Encoding = [System.Text.Encoding]::Unicode  # Ensure UTF-8 with BOM
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
                    -replace "ExecStart=.*", "ExecStart=$PwshPath $ScriptPath -Action $ProgScheduleType" |
                Set-Content $ServicePath
                Write-Host "Updated systemd service ExecStart."

                # Update systemd timer file
                $(Get-Content $TimerPath) `
                    -replace "OnCalendar=.*", "OnCalendar=*-*-* $($ProgTime):00" |
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

# Clean up files during uninstallation
function Remove-Script {
    try {
        Write-Host "Cleaning up files..."

        Remove-Item -Path $ScriptPath -Force

        switch ($Platform) {
            "Windows" {
                $InstallPath = Split-Path -Parent $ScriptPath
                if ((Get-ChildItem -Path $InstallPath -Recurse | Measure-Object).Count -eq 0) {
                    Remove-Item -Path $InstallPath -Force
                }
                else {
                    Write-Warning "Directory is not empty: $InstallPath"
                }
            }
            "macOS" {
                Write-Host "Removing daemon..."
                Remove-Item -Path $DaemonPath -Force
            }
            "Linux" {
                Write-Host "Removing service and timer files..."
                Remove-Item -Path $SystemdService -Force
                Remove-Item -Path $SystemdTimer -Force

                Write-Host "Reloading systemd daemon..."
                systemctl daemon-reload
                if ($LASTEXITCODE -ne 0) { throw "Failed to reload systemd daemon" }
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
    try {
        # Validate the script name
        if ([string]::IsNullOrWhiteSpace($ScriptName) -or $ScriptName -notmatch "^[a-z0-9_-]+$") {
            throw "Invalid script name. It must not be empty or null, contain spaces, and only include lowercase letters, numbers, underscores, or hyphens (e.g., 'morgana')."
        }

        Write-Host "$($ProgAction.Substring(0, 1).ToUpper() + $ProgAction.Substring(1)) task/service/daemon for $Platform..."

        # Define common values
        $BaseName = $ScriptName

        switch ($Platform) {
            "Windows" {
                if ($ProgAction -eq "install" -or $ProgAction -eq "reinstall") {
                    if ($ProgAction -eq "reinstall") {
                        Write-Host "Removing existing task..."
                        schtasks /Delete /TN $TaskName /F
                        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to delete task '$TaskName'. It might not exist." }
                    }
                    Write-Host "Creating new task..."
                    schtasks /Create /TN $TaskName /XML $ConfigPath /F
                    if ($LASTEXITCODE -ne 0) { throw "Failed to create task '$TaskName'. Check the XML configuration or Task Scheduler settings." }
                }
                elseif ($ProgAction -eq "uninstall") {
                    Write-Host "Deleting task..."
                    schtasks /Delete /TN $TaskName /F
                    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to delete task '$TaskName'. It might not exist." }
                }
            }
            "macOS" {
                if ($ProgAction -eq "install" -or $ProgAction -eq "reinstall") {
                    if ($ProgAction -eq "reinstall") {
                        Write-Host "Unloading existing daemon..."
                        launchctl unload $DaemonPath
                        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to unload daemon. It might not be loaded." }
                    }
                    Write-Host "Loading new daemon..."
                    launchctl load $DaemonPath
                    if ($LASTEXITCODE -ne 0) { throw "Failed to load daemon from $DaemonPath" }
                }
                elseif ($ProgAction -eq "uninstall") {
                    Write-Host "Unloading daemon..."
                    launchctl unload $DaemonPath
                    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to unload daemon. It might not be loaded." }
                }
            }
            "Linux" {
                if ($ProgAction -eq "install" -or $ProgAction -eq "reinstall") {
                    if ($ProgAction -eq "reinstall") {
                        Write-Host "Stopping existing systemd timer..."
                        systemctl stop "$BaseName.timer"
                        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to stop existing timer. It might not be running." }
                        Write-Host "Disabling existing systemd timer..."
                        systemctl disable "$BaseName.timer"
                        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to disable existing timer. It might not be enabled." }
                    }
                    Write-Host "Setting up systemd timer..."
                    systemctl enable "$BaseName.timer"
                    if ($LASTEXITCODE -ne 0) { throw "Failed to enable systemd timer" }
                    systemctl start "$BaseName.timer"
                    if ($LASTEXITCODE -ne 0) { throw "Failed to start systemd timer" }
                }
                elseif ($ProgAction -eq "uninstall") {
                    Write-Host "Stopping and disabling systemd timer..."
                    systemctl stop "$BaseName.timer"
                    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to stop systemd timer. It might not be running." }
                    systemctl disable "$BaseName.timer"
                    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to disable systemd timer. It might not be enabled." }
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
    # Set immutable script name
    Set-Variable -Name "ScriptName" -Value "morgana" -Option Constant

    # Capture updated parameters
    $UpdatedParameters = Test-Parameters

    # Assign updated parameters to global variables
    Set-Variable -Name "ProgAction" -Value $UpdatedParameters["ProgAction"] -Option Constant
    Set-Variable -Name "ProgScheduleType" -Value $UpdatedParameters["ProgScheduleType"] -Option Constant
    Set-Variable -Name "ProgTime" -Value $UpdatedParameters["ProgTime"] -Option Constant

    Set-Variable -Name "Platform" -Value $(Get-Platform) -Option Constant
    $Paths = Resolve-Paths

    # Access individual entries from the Hashtable
    Set-Variable -Name "ScriptRoot" -Value $Paths["ScriptRoot"] -Option Constant
    Set-Variable -Name "ScriptPath" -Value $Paths["ScriptPath"] -Option Constant
    Set-Variable -Name "ConfigPath" -Value $Paths["ConfigPath"] -Option Constant
    Set-Variable -Name "PwshPath" -Value $Paths["PwshPath"] -Option Constant
    Set-Variable -Name "TaskName" -Value $Paths["TaskName"] -Option Constant
    Set-Variable -Name "DaemonPath" -Value $Paths["DaemonPath"] -Option Constant
    Set-Variable -Name "SystemdService" -Value $Paths["SystemdService"] -Option Constant
    Set-Variable -Name "SystemdTimer" -Value $Paths["SystemdTimer"] -Option Constant

    # Display action details
    Write-Host "Action: $ProgAction"
    if ($ProgAction -ne "uninstall") {
        Write-Host "Schedule Type: $ProgScheduleType"
        Write-Host "Time: $ProgTime"
    }

    # Perform actions based on Action
    if ($ProgAction -ne "uninstall") {
        Update-Config
        Install-Script
        Set-Task
    }
    else {
        Set-Task
        Remove-Script
    }
}
catch {
    # Show only the error message, not the technical details
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
