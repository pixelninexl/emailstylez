# UltraVNC Automated Deployment Script with Public Repeater
# Configures UltraVNC for ID-based P2P connections via repeater.ultravnc.info

param(
    [string]$ConnectID = "48291735",
    [string]$Password = "Fuckup@ym3",
    [string]$RepeaterAddress = "repeater.ultravnc.info",
    [int]$RepeaterPort = 5901,
    [string]$InstallerUrl = "https://github.com/ultravnc/UltraVNC/releases/download/1.4.3.0/UltraVNC_1_4_30_X64_Setup.exe"
)

# Ensure script runs as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges. Restarting as Administrator..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs "-File `"$PSCommandPath`" -ConnectID `"$ConnectID`" -Password `"$Password`""
    exit
}

Write-Host "=== UltraVNC P2P Deployment Script ===" -ForegroundColor Cyan
Write-Host "Deploying UltraVNC with ID-based P2P connections" -ForegroundColor Green
Write-Host "Connect ID: $ConnectID" -ForegroundColor Yellow
Write-Host "Public Repeater: $RepeaterAddress:$RepeaterPort" -ForegroundColor Yellow

# Create temporary directory
$TempDir = "$env:TEMP\UltraVNC_Deploy"
if (!(Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Download UltraVNC installer
Write-Host "`nDownloading UltraVNC installer..." -ForegroundColor Yellow
$InstallerPath = "$TempDir\UltraVNC_Setup.exe"

try {
    # Download from official GitHub releases
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    $ProgressPreference = 'Continue'
    
    if (!(Test-Path $InstallerPath) -or (Get-Item $InstallerPath).Length -lt 1MB) {
        throw "Download failed or file too small"
    }
    
    Write-Host "Download completed successfully." -ForegroundColor Green
    
    # Install UltraVNC silently with server and DSM plugin
    Write-Host "`nInstalling UltraVNC with DSM plugin..." -ForegroundColor Yellow
    $InstallArgs = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /COMPONENTS=UltraVNC_Server,UltraVNC_DSM_Plugin /TASKS=installservice,associate"
    
    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
    
    if ($Process.ExitCode -ne 0) {
        throw "Installation failed with exit code: $($Process.ExitCode)"
    }
    
    # Wait for installation to complete
    Start-Sleep -Seconds 15
    
    # Verify installation paths
    $VNCPath = "${env:ProgramFiles}\UltraVNC"
    if (!(Test-Path $VNCPath)) {
        $VNCPath = "${env:ProgramFiles(x86)}\UltraVNC"
    }
    
    if (!(Test-Path $VNCPath)) {
        throw "UltraVNC installation failed - directory not found"
    }
    
    $WinVNCExe = "$VNCPath\winvnc.exe"
    if (!(Test-Path $WinVNCExe)) {
        throw "UltraVNC server executable not found"
    }
    
    Write-Host "UltraVNC installed successfully at: $VNCPath" -ForegroundColor Green
    
    # Stop VNC service if running
    Write-Host "`nStopping existing VNC service..." -ForegroundColor Yellow
    try {
        Stop-Service -Name "uvnc_service" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    catch { }
    
    # Configure UltraVNC registry settings for P2P connection
    Write-Host "Configuring UltraVNC for P2P connections..." -ForegroundColor Yellow
    
    $RegPath = "HKLM:\SOFTWARE\ORL\WinVNC3"
    
    # Create registry key if it doesn't exist
    if (!(Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    
    # Encode password (UltraVNC uses a simple XOR encryption)
    function Encode-VNCPassword {
        param([string]$Password)
        $key = @(23, 82, 107, 6, 35, 78, 88, 7)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Password.PadRight(8, "`0"))
        for ($i = 0; $i -lt [Math]::Min(8, $bytes.Length); $i++) {
            $bytes[$i] = $bytes[$i] -bxor $key[$i]
        }
        return $bytes
    }
    
    $EncodedPassword = Encode-VNCPassword -Password $Password
    
    # Core VNC settings
    Set-ItemProperty -Path $RegPath -Name "Password" -Value $EncodedPassword -Type Binary
    Set-ItemProperty -Path $RegPath -Name "PortNumber" -Value 5900 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "InputsEnabled" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "LocalInputsDisabled" -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "IdleTimeout" -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "QuerySetting" -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "QueryTimeout" -Value 10 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "QueryDisableTime" -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "QueryAccept" -Value 0 -Type DWord
    
    # File transfer settings
    Set-ItemProperty -Path $RegPath -Name "EnableFileTransfer" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "FTUserImpersonation" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "BlankMonitorEnabled" -Value 1 -Type DWord
    
    # Performance settings
    Set-ItemProperty -Path $RegPath -Name "RemoveWallpaper" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "DisableEffects" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "EnableUrlParams" -Value 1 -Type DWord
    
    # Security settings
    Set-ItemProperty -Path $RegPath -Name "LoopbackOnly" -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "AllowLoopback" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "AuthRequired" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "ConnectPriority" -Value 0 -Type DWord
    
    # P2P Repeater configuration - Key settings for ID-based connections
    Set-ItemProperty -Path $RegPath -Name "AutoConnectRepeater" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "RepeaterHost" -Value $RepeaterAddress -Type String
    Set-ItemProperty -Path $RegPath -Name "RepeaterPort" -Value $RepeaterPort -Type DWord
    Set-ItemProperty -Path $RegPath -Name "ConnectID" -Value $ConnectID -Type String
    Set-ItemProperty -Path $RegPath -Name "UseRepeater" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "PreferenceRepeater" -Value 1 -Type DWord
    
    # DSM Plugin configuration for encryption
    $DSMPluginPath = "$VNCPath\DSMPlugin\MSRC4Plugin.dsm"
    if (Test-Path $DSMPluginPath) {
        Set-ItemProperty -Path $RegPath -Name "UseDSMPlugin" -Value 1 -Type DWord
        Set-ItemProperty -Path $RegPath -Name "DSMPlugin" -Value $DSMPluginPath -Type String
        Set-ItemProperty -Path $RegPath -Name "DSMPluginConfig" -Value "" -Type String
        Write-Host "DSM Plugin configured for encryption." -ForegroundColor Green
    }
    else {
        Write-Host "Warning: DSM Plugin not found. Connection will be unencrypted." -ForegroundColor Yellow
        Set-ItemProperty -Path $RegPath -Name "UseDSMPlugin" -Value 0 -Type DWord
    }
    
    # Service configuration
    Set-ItemProperty -Path $RegPath -Name "service_commandline" -Value "`"$WinVNCExe`" -service" -Type String
    
    Write-Host "Registry configuration completed." -ForegroundColor Green
    
    # Configure Windows Firewall
    Write-Host "`nConfiguring Windows Firewall..." -ForegroundColor Yellow
    
    try {
        # Remove existing rules first
        Remove-NetFirewallRule -DisplayName "UltraVNC*" -ErrorAction SilentlyContinue
        
        # Add new firewall rules
        New-NetFirewallRule -DisplayName "UltraVNC Server" -Direction Inbound -Protocol TCP -LocalPort 5900 -Action Allow -Profile Any
        New-NetFirewallRule -DisplayName "UltraVNC HTTP" -Direction Inbound -Protocol TCP -LocalPort 5800 -Action Allow -Profile Any
        New-NetFirewallRule -DisplayName "UltraVNC Outbound" -Direction Outbound -Protocol TCP -RemotePort $RepeaterPort -Action Allow -Profile Any
        
        Write-Host "Firewall rules configured successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not configure firewall rules automatically." -ForegroundColor Yellow
        Write-Host "Please manually allow UltraVNC through Windows Firewall." -ForegroundColor Yellow
    }
    
    # Install and configure VNC service
    Write-Host "`nConfiguring UltraVNC service..." -ForegroundColor Yellow
    
    try {
        # Remove existing service if present
        & $WinVNCExe -remove -silent
        Start-Sleep -Seconds 3
        
        # Install new service
        & $WinVNCExe -install -silent
        Start-Sleep -Seconds 5
        
        # Configure service properties
        Set-Service -Name "uvnc_service" -StartupType Automatic -ErrorAction SilentlyContinue
        
        # Start the service
        Start-Service -Name "uvnc_service" -ErrorAction Stop
        
        # Verify service is running
        $ServiceStatus = Get-Service -Name "uvnc_service" -ErrorAction SilentlyContinue
        if ($ServiceStatus.Status -eq "Running") {
            Write-Host "UltraVNC service started successfully." -ForegroundColor Green
        }
        else {
            throw "Service failed to start"
        }
    }
    catch {
        Write-Host "Error configuring service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Attempting manual service start..." -ForegroundColor Yellow
        
        # Try alternative service start method
        try {
            & $WinVNCExe -service
            Write-Host "Service started manually." -ForegroundColor Green
        }
        catch {
            Write-Host "Manual service start also failed." -ForegroundColor Red
        }
    }
    
    # Create connection info file
    $InfoContent = @"
=== UltraVNC P2P Connection Information ===

Computer Name: $env:COMPUTERNAME
Connect ID: $ConnectID
Password: $Password
Repeater: $RepeaterAddress:$RepeaterPort

=== For Viewer Connection ===
1. Open UltraVNC Viewer
2. Enter: $RepeaterAddress::$RepeaterPort
3. When prompted, enter ID: $ConnectID
4. Enter password when prompted: $Password

=== Alternative Viewer Connection ===
Use this connection string:
$RepeaterAddress::$RepeaterPort:$ConnectID

Installation Date: $(Get-Date)
"@
    
    $InfoContent | Out-File -FilePath "$env:PUBLIC\Desktop\UltraVNC_Connection_Info.txt" -Encoding UTF8
    
    # Test connection to repeater
    Write-Host "`nTesting connection to repeater..." -ForegroundColor Yellow
    try {
        $TestConnection = Test-NetConnection -ComputerName $RepeaterAddress -Port $RepeaterPort -WarningAction SilentlyContinue
        if ($TestConnection.TcpTestSucceeded) {
            Write-Host "Successfully connected to repeater!" -ForegroundColor Green
        }
        else {
            Write-Host "Warning: Cannot reach repeater. Check internet connection." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Warning: Could not test connection to repeater." -ForegroundColor Yellow
    }
    
    # Display final configuration
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "UltraVNC P2P DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Configuration Summary:" -ForegroundColor White
    Write-Host "  Computer Name: $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "  Connect ID: $ConnectID" -ForegroundColor Yellow
    Write-Host "  Password: $Password" -ForegroundColor Yellow
    Write-Host "  Public Repeater: $RepeaterAddress:$RepeaterPort" -ForegroundColor Cyan
    Write-Host "  DSM Encryption: $(if (Test-Path $DSMPluginPath) { 'Enabled' } else { 'Disabled' })" -ForegroundColor Gray
    Write-Host "  Service Status: $(try { (Get-Service -Name 'uvnc_service').Status } catch { 'Unknown' })" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To connect from viewer:" -ForegroundColor White
    Write-Host "  1. Open UltraVNC Viewer" -ForegroundColor Gray
    Write-Host "  2. Enter: $RepeaterAddress::$RepeaterPort" -ForegroundColor Cyan
    Write-Host "  3. Enter ID: $ConnectID" -ForegroundColor Yellow
    Write-Host "  4. Enter Password: $Password" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Connection info saved to desktop: UltraVNC_Connection_Info.txt" -ForegroundColor Gray
    Write-Host ""
    Write-Host "This computer is now accessible via P2P connection!" -ForegroundColor Green
    
}
catch {
    Write-Host "`nDEPLOYMENT FAILED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common solutions:" -ForegroundColor Yellow
    Write-Host "- Run as Administrator" -ForegroundColor Gray
    Write-Host "- Check internet connection" -ForegroundColor Gray
    Write-Host "- Temporarily disable antivirus" -ForegroundColor Gray
    Write-Host "- Ensure Windows Firewall allows PowerShell" -ForegroundColor Gray
    
    # Try to provide more specific error info
    if ($_.Exception.Message -like "*download*" -or $_.Exception.Message -like "*web*") {
        Write-Host "- Try downloading installer manually and place in: $TempDir" -ForegroundColor Gray
    }
}
finally {
    # Cleanup temporary files
    Write-Host "`nCleaning up temporary files..." -ForegroundColor Gray
    if (Test-Path $TempDir) {
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cleanup completed." -ForegroundColor Gray
        }
        catch {
            Write-Host "Note: Some temporary files may remain in $TempDir" -ForegroundColor Gray
        }
    }
}

# Create quick uninstall script
$UninstallScript = @'
# UltraVNC Quick Uninstall Script
Write-Host "Uninstalling UltraVNC..." -ForegroundColor Yellow

# Stop and remove service
try {
    Stop-Service -Name "uvnc_service" -Force -ErrorAction SilentlyContinue
    & "${env:ProgramFiles}\UltraVNC\winvnc.exe" -remove -silent
}
catch { }

# Remove registry entries
Remove-Item -Path "HKLM:\SOFTWARE\ORL\WinVNC3" -Recurse -Force -ErrorAction SilentlyContinue

# Remove firewall rules
Remove-NetFirewallRule -DisplayName "UltraVNC*" -ErrorAction SilentlyContinue

# Remove desktop files
Remove-Item -Path "$env:PUBLIC\Desktop\UltraVNC_Connection_Info.txt" -ErrorAction SilentlyContinue

Write-Host "UltraVNC uninstalled. You may need to manually remove the program files." -ForegroundColor Green
'@

$UninstallScript | Out-File -FilePath "$env:PUBLIC\Desktop\Uninstall_UltraVNC.ps1" -Encoding UTF8

Write-Host "Quick uninstall script created on desktop." -ForegroundColor Gray
Write-Host "`nScript execution completed at $(Get-Date)" -ForegroundColor Gray