```powershell
# --- Custom Logging Function (reused and slightly modified) ---
function Write-Log {
    param (
        [string]$Message,
        [string]$LogFile # This parameter is now mandatory for clarity
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"

    # Ensure the log directory exists for this specific log file
    $LogDirectory = Split-Path $LogFile
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force
    }

    # Append the log entry to the file
    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8

    # Also output to the console for real-time viewing
    Write-Host $LogEntry
}

# --- Main Script ---

# Define the log file paths
$GeneralScriptLogFile = "C:\Logs\MyScript_GeneralLog.txt"
$MachineOnlineLogFile = "C:\Logs\MyScript_MachineStatus.txt"

# --- 1. Check if Machine is Online and Log Separately ---
$TargetMachine = "localhost" # Or an IP address like "192.168.1.1" or a hostname "MyServer"

Write-Host "Checking if '$TargetMachine' is online..."

try {
    # Test-Connection sends an ICMP echo request (ping)
    $PingResult = Test-Connection -ComputerName $TargetMachine -Count 1 -ErrorAction SilentlyContinue

    if ($PingResult) {
        $OnlineStatus = "ONLINE"
        $OnlineMessage = "Machine '$TargetMachine' is $OnlineStatus. Response time: $($PingResult.ResponseTime)ms"
        Write-Log -Message $OnlineMessage -LogFile $MachineOnlineLogFile
        Write-Log -Message "Successfully pinged $TargetMachine." -LogFile $GeneralScriptLogFile # Log to general too
    } else {
        $OnlineStatus = "OFFLINE"
        $OfflineMessage = "Machine '$TargetMachine' is $OnlineStatus. Cannot be reached."
        Write-Log -Message $OfflineMessage -LogFile $MachineOnlineLogFile
        Write-Log -Message "WARNING: Failed to ping $TargetMachine." -LogFile $GeneralScriptLogFile # Log to general too
    }
}
catch {
    $ErrorMessage = "ERROR: Could not perform ping check on '$TargetMachine'. Exception: $($_.Exception.Message)"
    Write-Log -Message $ErrorMessage -LogFile $MachineOnlineLogFile
    Write-Log -Message $ErrorMessage -LogFile $GeneralScriptLogFile # Log to general too
}

# --- 2. General Script Operations and Logging ---

Write-Log -Message "Script started general operations." -LogFile $GeneralScriptLogFile
Write-Log -Message "Performing Task A..." -LogFile $GeneralScriptLogFile

# Simulate some work
Start-Sleep -Seconds 1

Write-Log -Message "Task A completed." -LogFile $GeneralScriptLogFile

# Simulate another task with a potential issue
try {
    # Example: Trying to access a non-existent file
    Get-Content -Path "C:\NonExistentFile.txt" -ErrorAction Stop
}
catch {
    Write-Log -Message "ERROR: Failed to process file. Exception: $($_.Exception.Message)" -LogFile $GeneralScriptLogFile
}

Write-Log -Message "Script finished general operations." -LogFile $GeneralScriptLogFile
```
