#region Tool Description
    <#
.SYNOPSIS
Vivox Voice Chat Service Diagnostic Tool for the Demonologist game.

.DESCRIPTION
1. Starts a background job that defines and runs the `Get-FirewallLogs` function to monitor firewall activity.
2. Waits for the Demonologist game process to start and for the user to open a multiplayer lobby using `Wait-ForGameProcess`.
3. Performs multiple diagnostics:
    - Retrieves network connections using `Get-NetworkConnections`.
    - Tests DNS configuration and server availability using `Test-DNSConfiguration`.
    - Tests connectivity to Vivox endpoints using `Test-VivoxEndpoints`.
    - Tests and manages Windows Time service configuration using `Test-TimeConfiguration`.
4. Gathers and displays firewall log entries captured by the background job.
5. Adds necessary firewall rules to allow Vivox traffic if DROP logs are detected.
6. Provides comprehensive diagnostic output to assist in troubleshooting Vivox-related connectivity issues.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 02/03/2025

.EXAMPLE
Test-VivoxDemonologist
#>
#endregion Tool Description

#region Global Configuration
<#
.SYNOPSIS
Global variables used by all functions.
#>
param(
    [string]$Desktop = [Environment]::GetFolderPath("Desktop")
)

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Game process name
$script:processName = "Shivers-Win64-Shipping"

# Color configuration
$script:colorProcess = "Yellow"
$script:colorValues = "Cyan"
$script:colorSuccess = "Green"
$script:colorError   = "Red"
$script:colorWarning = "Red"

# Shared variables
$script:process          = $null
$script:networkInterface = $null
$script:interfaceIP      = $null
#endregion Global Configuration

#region Main Function
<#
.NOTES
This is the main function that orchestrates the diagnostic process for Vivox services in the Demonologist game, ensuring all network, DNS, and time configurations are optimal for seamless voice communication.
#>
function Test-VivoxDemonologist {
    begin {
        Clear-Host
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
        $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Log "Not running as administrator. Relaunching with elevated privileges..."
            Write-Host "Not running as administrator. Relaunching with elevated privileges..."

            $Desktop = [Environment]::GetFolderPath("Desktop")
            $command = "Invoke-Command -ScriptBlock ([scriptblock]::Create([System.Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://demonologist.mannyagre.workers.dev')))) -ArgumentList @('$Desktop')"

            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoExit',
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-Command',
                $command
            )

            exit
        }

        $Password = Read-Host "Enter the password that Manny gave you"

        if ($Password -ne 'manny') {
            Write-Host "`nIncorrect password, please open your own bug report on discord"
            Write-Host "`nExiting in 5 seconds..."
            Start-Sleep 5
            exit
        }

        <#
        .SYNOPSIS
        Retrieves and monitors firewall logs for Vivox-related network traffic.

        .DESCRIPTION
        1. Determines the current network category (Domain, Private, Public) using `Get-NetConnectionProfile`.
        2. Retrieves the corresponding firewall profile using `Get-NetFirewallProfile`.
        3. Configures firewall logging for the identified profile with `Set-NetFirewallProfile`, specifying the log file path and enabling logging for allowed and blocked connections.
        4. Continuously monitors the firewall log file in real-time using `Get-Content -Wait -Tail 1`.
        5. Parses each log entry and filters for Vivox-related IP patterns (`188.42.147`, `188.42.95`, `85.236`).
        6. Outputs relevant firewall log entries as custom PowerShell objects.
        7. Disables firewall logging after monitoring is complete to revert to original settings.
        8. Handles errors related to firewall profile retrieval and log file configuration.

        .NOTES
        Author: manny_agre
        Creation Date: 01/25/2025
        Last Modified: 01/26/2025
        This function monitors firewall logs in real-time to capture and analyze Vivox-related network traffic, aiding in identifying blocked connections that may affect the Demonologist game's voice services.
        #>

        # Start the firewall log job in the background.
        # Embeds the function definition inside the ScriptBlock so it's recognized.
        $fwLogJob = Start-Job -ScriptBlock {
            function Get-FirewallLogs {

                try {
                    $networkCategory = (Get-NetConnectionProfile).NetworkCategory
                    switch ($networkCategory) {
                        "DomainAuthenticated" { $fwProfile = "Domain" }
                        "Private"             { $fwProfile = "Private" }
                        "Public"              { $fwProfile = "Public" }
                        default {
                            Write-Host "Unknown network profile: $networkCategory" -ForegroundColor $script:colorError
                            return
                        }
                    }

                    $currentProfile = Get-NetFirewallProfile -Name $fwProfile
                    if (-not $currentProfile.Enabled) {
                        Write-Host "`nFirewall for profile '$fwProfile' is disabled. Logs will not be configured." -ForegroundColor $script:colorProcess
                        return
                    }

                    $logFile = "$env:SystemRoot\System32\LogFiles\Firewall\$fwProfile`_pfirewall.log"
                    Set-NetFirewallProfile -Profile $fwProfile `
                                        -LogFileName $logFile `
                                        -LogMaxSizeKilobytes 32767 `
                                        -LogAllowed True `
                                        -LogBlocked True

                    Get-Content $logFile -Wait -Tail 1 | ForEach-Object {
                        $line = $_.Trim()
                        if (-not $line) { return }

                        $fields = $line.Split(' ')
                        if ($fields.Count -lt 18) { return }

                        $entry = [PSCustomObject]@{
                            Date      = $fields[0]
                            Time      = $fields[1]
                            Action    = $fields[2]
                            Protocol  = $fields[3]
                            SrcIp     = $fields[4]
                            DstIp     = $fields[5]
                            SrcPort   = $fields[6]
                            DstPort   = $fields[7]
                            Size      = $fields[8]
                            TcpFlags  = $fields[9]
                            TcpSyn    = $fields[10]
                            TcpAck    = $fields[11]
                            TcpWin    = $fields[12]
                            IcmpType  = $fields[13]
                            IcmpCode  = $fields[14]
                            Info      = $fields[15]
                            Path      = $fields[16]
                            Pid       = $fields[17]
                        }

                        $pattern = '^(188\.42\.147|188\.42\.95|85\.236)'
                        if ($entry.SrcIp -match $pattern -or $entry.DstIp -match $pattern) {
                            Write-Output $entry
                        }
                    }
                } catch {
                    Write-Log "[ERROR] $($_.Exception.Message)" 
                    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor $script:colorError
                }
                finally {
                    Set-NetFirewallProfile -Profile $fwProfile `
                                            -LogAllowed False `
                                            -LogBlocked False
                }
            }

            # Execute the function in this job
            Get-FirewallLogs
        }
    }

    process {
        try {
            Wait-ForProcess
            Get-NetworkConnections
            Test-DNSConfiguration
            Test-VivoxEndpoints
            Test-TimeConfiguration

            # Once done, gather what the firewall log job output so far
            $fwLogEntries = Receive-Job -Job $fwLogJob -Keep

            # Stop the job to end the indefinite -Wait tail
            Stop-Job -Job $fwLogJob

            # Show what was captured
            if ($fwLogEntries) {
                Write-Log "`n`n======= FIREWALL LOG ANALYSIS =======" 
                Write-Host "`n`n======= FIREWALL LOG ANALYSIS =======" -ForegroundColor $script:colorProcess
                $fwLogEntries | Format-Table Time, Action, Protocol, SrcIp, SrcPort, DstIp, DstPort, Pid -AutoSize
            }

            if ($fwLogEntries -and ($fwLogEntries | Where-Object { $_.Action -eq 'DROP' })) {
                Write-Log "`n[CRITICAL ERROR] DROP logs detected in the firewall." 
                Write-Host "`n[CRITICAL ERROR] DROP logs detected in the firewall." -ForegroundColor $script:colorError
                Write-Log "`n[INFO] Trying to add firewall rules to allow Vivox..." 
                Write-Host "`n[INFO] Trying to add firewall rules to allow Vivox..." -ForegroundColor $script:colorProcess
                $cidrs = @('85.236.96.0/21','188.42.95.0/24','188.42.147.0/24')
                foreach ($cidr in $cidrs) {
                    try {
                        # TCP 443 INBOUND
                        New-NetFirewallRule -DisplayName "VivoxTCP443_Allow_In_$cidr" -Protocol TCP -LocalPort 443 `
                                            -RemoteAddress $cidr -Direction Inbound -Action Allow -ErrorAction SilentlyContinue > $null 2>&1
                        # TCP 443 OUTBOUND
                        New-NetFirewallRule -DisplayName "VivoxTCP443_Allow_Out_$cidr" -Protocol TCP -LocalPort 443 `
                                            -RemoteAddress $cidr -Direction Outbound -Action Allow -ErrorAction SilentlyContinue > $null 2>&1
                        
                        # UDP range 12000-65535 INBOUND (Vivox said that they use 12000-52000 but I've seen that is not true)
                        New-NetFirewallRule -DisplayName "VivoxUDP_Allow_In_$cidr" -Protocol UDP -LocalPort 12000-65535 `
                                            -RemoteAddress $cidr -Direction Inbound -Action Allow -ErrorAction SilentlyContinue > $null 2>&1
                        # UDP range 12000-65535 OUTBOUND (Vivox said that they use 12000-52000 but I've seen that is not true)
                        New-NetFirewallRule -DisplayName "VivoxUDP_Allow_Out_$cidr" -Protocol UDP -LocalPort 12000-65535 `
                                            -RemoteAddress $cidr -Direction Outbound -Action Allow -ErrorAction SilentlyContinue > $null 2>&1
                        Write-Log "Successfully added firewall rules for CIDR $cidr." 
                        Write-Host "Successfully added firewall rules for CIDR $cidr." -ForegroundColor $script:colorSuccess
                    } catch {
                        Write-Log "Failed to add firewall rules for CIDR $cidr" 
                        Write-Host "Failed to add firewall rules for CIDR $cidr" -ForegroundColor $script:colorError
                        Write-Log "$($_.Exception.Message)" 
                        Write-Host "$($_.Exception.Message)" -ForegroundColor $script:colorError
                    }       
                }
                Write-Log "`nFirewall rules added for Vivox segments" 
                Write-Host "`nFirewall rules added for Vivox segments" -ForegroundColor $script:colorSuccess
            }
            Get-InstallationAndHardwareInfo
            Write-Log "`n======= DIAGNOSTICS COMPLETE =======" 
            Write-Host "`n======= DIAGNOSTICS COMPLETE =======" -ForegroundColor $script:colorSuccess
        }
        catch {
            Write-Log "`n[CRITICAL ERROR] $($_.Exception.Message)" 
            Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor $script:colorError
            return
        }
    }
}
#endregion Main Function

function Write-Log {
    param(
        [string]$Message
    )

    $logFile = Join-Path $Desktop "demonologist.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entryL = "[{0}] {1}" -f $timestamp, $Message
    Add-Content -Path $logFile -Value $entryL
}

#region Wait-ForProcess
<#
.SYNOPSIS
Waits for the Demonologist game process to start, displays process information,
activates DNS client logging, and monitors DNS events until the first "vivox.com" query is detected.

.DESCRIPTION
1. Continuously checks for the "Shivers-Win64-Shipping" process every second.
2. Displays key process details when found (Name, PID, Start Time, Path).
3. Activates DNS client logging using `wevtutil`.
4. Monitors DNS events in real-time for the first "vivox.com" query.
5. Stops monitoring once the "vivox.com" DNS query is detected.
6. Notifies the user to open a multiplayer lobby in the game.
7. Cleans up event handlers and disables DNS client logging after detection.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 01/26/2025
It ensures that the game process is running and that DNS queries related to Vivox are monitored effectively.
Uses a global temporary variable to bridge event handler scope limitations.
Cleanup is handled automatically by the function.
#>
function Wait-ForProcess {
    Write-Log "`n======= WAITING FOR DEMONOLOGIST PROCESS =======" 
    Write-Host "`n======= WAITING FOR DEMONOLOGIST PROCESS =======" -ForegroundColor $script:colorProcess
    Write-Log "`nPlease open the game..." 
    Write-Host "`nPlease open the game..." -ForegroundColor $script:colorProcess
    while (-not $script:process) {
        $script:process = Get-Process -Name $script:processName -ErrorAction SilentlyContinue
        if (-not $script:process) {
            Start-Sleep -Seconds 1
        }
    }

    Write-Log "`n[SUCCESS] Game process detected!" 
    Write-Host "`n[SUCCESS] Game process detected!" -ForegroundColor $script:colorSuccess

    Write-Log "`n[PROCESS DETAILS]`n" 
    Write-Host "`n[PROCESS DETAILS]`n" -ForegroundColor $script:colorProcess
    $processInfo = $script:process | Format-List `
        @{ Label = "Name";       Expression = { $_.Name } }, `
        @{ Label = "PID";        Expression = { $_.Id } }, `
        @{ Label = "Start Time"; Expression = { $_.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } }, `
        @{ Label = "Path";       Expression = { $_.Path } } | Out-String

    Write-Log $processInfo.Trim() 
    Write-Host $processInfo.Trim() -ForegroundColor $script:colorValues

    Write-Log "`nPlease open a multiplayer lobby in the game..." 
    Write-Host "`nPlease open a multiplayer lobby in the game..." -ForegroundColor $script:colorProcess

    $global:VivoxQueryDetected = $null

    try {
        wevtutil set-log "Microsoft-Windows-DNS-Client/Operational" /enabled:true | Out-Null

        $logName = "Microsoft-Windows-DNS-Client/Operational"
        $query = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new(
            $logName,
            [System.Diagnostics.Eventing.Reader.PathType]::LogName,
            "*"
        )

        $watcher = [System.Diagnostics.Eventing.Reader.EventLogWatcher]::new($query)
        $watcher.Enabled = $true

        $eventParams = @{
            InputObject = $watcher
            EventName   = "EventRecordWritten"
            Action      = {
                $record = $EventArgs.EventRecord
                if ($record) {
                    $message = $record.FormatDescription()
                    if ($message -like "*vivox.com*") {
                        $global:VivoxQueryDetected = @{
                            TimeCreated = $record.TimeCreated
                            LogName     = $record.LogName
                            EventID     = $record.Id
                            Provider    = $record.ProviderName
                            Message     = $message
                        }
                    }
                }
            }
        }

        $handler = Register-ObjectEvent @eventParams -SourceIdentifier "VivoxWatcher"

        while (-not $global:VivoxQueryDetected) {
            Start-Sleep -Milliseconds 100
        }
    }
    finally {
        if ($watcher) {
            $watcher.Enabled = $false
            $watcher.Dispose()
        }

        if ($handler) {
            Unregister-Event -SourceIdentifier "VivoxWatcher" -ErrorAction SilentlyContinue
            Remove-Job -Name "VivoxWatcher" -ErrorAction SilentlyContinue
        }

        wevtutil set-log "Microsoft-Windows-DNS-Client/Operational" /enabled:false | Out-Null
        $global:VivoxQueryDetected = $null
        Write-Log "`n[SUCCESS] Multiplayer lobby detected!" 
        Write-Host "`n[SUCCESS] Multiplayer lobby detected!" -ForegroundColor $script:colorSuccess
        Write-Log "`nStarting diagnostics..." 
        Write-Host "`nStarting diagnostics..." -ForegroundColor $script:colorProcess
    }
}
#endregion Wait-ForProcess

#region Get-NetworkConnections
<#
.SYNOPSIS
Retrieves and displays active network connections of the Demonologist game process.

.DESCRIPTION
1. Retrieves active TCP connections associated with the Demonologist process using `Get-NetTCPConnection`.
2. Displays the connections with details such as LocalAddress, LocalPort, RemoteAddress, RemotePort, State, and AppliedSetting.
3. Provides a warning if no active connections are found.
4. Waits for 5 seconds before displaying the connections to ensure accurate data retrieval.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 01/26/2025
This function analyzes the network connections used by the Demonologist game process to identify active communication endpoints.
#>
function Get-NetworkConnections {
    Write-Log "`n`n======= NETWORK ANALYSIS =======" 
    Write-Host "`n`n======= NETWORK ANALYSIS =======" -ForegroundColor $script:colorProcess
    
    try {
        $connections = Get-NetTCPConnection -OwningProcess $script:process.Id -ErrorAction Stop |
                        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, AppliedSetting
        Start-Sleep -Seconds 5
        Write-Log "`n[ACTIVE CONNECTIONS]`n" 
        Write-Host "`n[ACTIVE CONNECTIONS]`n" -ForegroundColor $script:colorProcess
        if ($connections) {
            $connectionTable = $connections | Format-Table -AutoSize | Out-String
            Write-Log $connectionTable.Trim() 
            Write-Host $connectionTable.Trim() -ForegroundColor $script:colorValues
        }
        else {
            Write-Log "[WARNING] No active connections found" 
            Write-Host "[WARNING] No active connections found" -ForegroundColor $script:colorWarning
        }
    }
    catch {
        Write-Log "[WARNING] No active connections found" 
        Write-Host "[WARNING] No active connections found" -ForegroundColor $script:colorWarning
    }
}
#endregion Get-NetworkConnections

#region Test-DNSConfiguration
<#
.SYNOPSIS
Tests Vivox-related DNS entries and DNS server availability for the Demonologist game.

.DESCRIPTION
1. Checks the DNS cache for entries related to Vivox using `Get-CimInstance`.
2. Displays Vivox-related DNS entries if found.
3. Retrieves the active network interface and its IP address using `Test-NetConnection`.
4. Verifies DNS server reachability for each DNS server configured on the active interface.
5. Tests domain resolution for known hosts like `google.com` and Vivox subdomains using `Resolve-DnsName`.
6. Attempts to configure alternative DNS servers (Google DNS and Cloudflare DNS) if issues are detected.
7. Restores the original DNS configuration if troubleshooting attempts fail.
8. Provides detailed output on DNS server reachability and domain resolution status.
9. Retries up to three times if issues persist, attempting to re-validate and repair configuration.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 01/28/2025
This function ensures that DNS configurations are optimal for Vivox services used by Demonologist by verifying and troubleshooting DNS-related issues.
#>
function Test-DNSConfiguration {
    $script:dnsIssues = $false
    $testDomains = @('google.com', 'mtu1xp-mim.vivox.com', 'unity.vivox.com', 'cdp.vivox.com')
    $retryCount = 0
    $maxRetries = 2

    while ($retryCount -lt $maxRetries) {
        $retryCount++

        try {
            $vivoxDNS = Get-CimInstance -Namespace "root/StandardCimv2" -ClassName "MSFT_DNSClientCache" -ErrorAction Stop |
                        Where-Object { $_.Entry -like "*vivox*" -or $_.Name -like "*vivox*" }

            if ($vivoxDNS) {
                Write-Log "`n[RELATED DNS ENTRIES]`n" 
                Write-Host "`n[RELATED DNS ENTRIES]`n" -ForegroundColor $script:colorProcess
                $dnsTable = $vivoxDNS | Format-Table Entry, Name, Data -AutoSize | Out-String
                Write-Log $dnsTable.Trim() 
                Write-Host $dnsTable.Trim() -ForegroundColor $script:colorValues
            } else {
                Write-Log "`n[WARNING] No Vivox-related DNS entries" 
                Write-Host "`n[WARNING] No Vivox-related DNS entries" -ForegroundColor $script:colorWarning
            }
        } catch {
            Write-Log "`n[ERROR] DNS cache analysis failed" 
            Write-Host "`n[ERROR] DNS cache analysis failed" -ForegroundColor $script:colorError
            continue
        }

        if ($retryCount -ge 2) {
            Write-Log "`n[INFO] Retrying validation and repair of configuration..." 
            Write-Host "`n[INFO] Retrying validation and repair of configuration..." -ForegroundColor $script:colorProcess
        }


        $findingNIC = Test-NetConnection -ComputerName 8.8.8.8 -WarningAction SilentlyContinue
        $script:networkInterface = $findingNIC.InterfaceAlias
        $script:interfaceIP = $findingNIC.SourceAddress.IPAddress

        if ($script:networkInterface) {
            Write-Log "`n[INTERFACE DNS SERVERS]" 
            Write-Host "`n[INTERFACE DNS SERVERS]" -ForegroundColor $script:colorProcess
            Write-Log "`nActive Interface: " 
            Write-Host "`nActive Interface: " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log $script:networkInterface 
            Write-Host $script:networkInterface -ForegroundColor $script:colorValues
            Write-Log "Interface IP: " 
            Write-Host "Interface IP: " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log $script:interfaceIP 
            Write-Host $script:interfaceIP -ForegroundColor $script:colorValues

            try {
                $dnsServers = Get-DnsClientServerAddress -InterfaceAlias $script:networkInterface -AddressFamily IPv4 -ErrorAction Stop |
                                Select-Object -ExpandProperty ServerAddresses -Unique
                $originalDns = $dnsServers

                if (-not $dnsServers) {
                    Write-Log "[WARNING] No DNS servers configured" 
                    Write-Host "[WARNING] No DNS servers configured" -ForegroundColor $script:colorWarning
                    continue
                }

                # Test original DNS configuration
                foreach ($server in $dnsServers) {
                    Write-Log "`nTesting DNS: " 
                    Write-Host "`nTesting DNS: " -NoNewline -ForegroundColor $script:colorProcess
                    Write-Log $server 
                    Write-Host $server -ForegroundColor $script:colorValues

                    try {
                        $pingTest = Test-NetConnection -ComputerName $server -InformationLevel Detailed -WarningAction SilentlyContinue

                        Write-Log "Reachable:  " 
                        Write-Host "Reachable:  " -NoNewline -ForegroundColor $script:colorProcess
                        if ($pingTest.PingSucceeded) {
                            Write-Log "Yes" 
                            Write-Host "Yes" -ForegroundColor $script:colorSuccess
                            Write-Log "Latency:    " 
                            Write-Host "Latency:    " -NoNewline -ForegroundColor $script:colorProcess
                            Write-Log "$($pingTest.PingReplyDetails.RoundtripTime)ms" 
                            Write-Host "$($pingTest.PingReplyDetails.RoundtripTime)ms" -ForegroundColor $script:colorValues
                        } else {
                            Write-Log "No" 
                            Write-Host "No" -ForegroundColor $script:colorError
                            Write-Log "Status:     " 
                            Write-Host "Status:     " -NoNewline -ForegroundColor $script:colorProcess
                            Write-Log "ICMP blocked/unreachable" 
                            Write-Host "ICMP blocked/unreachable" -ForegroundColor $script:colorWarning
                            $script:dnsIssues = $true
                        }
                    } catch {
                        Write-Log "[ERROR] Connectivity test failed" 
                        Write-Host "[ERROR] Connectivity test failed" -ForegroundColor $script:colorError
                        $script:dnsIssues = $true
                    }
                }

                Write-Log "`n`n[DOMAIN RESOLUTION TESTS]" 
                Write-Host "`n`n[DOMAIN RESOLUTION TESTS]" -ForegroundColor $script:colorProcess
                foreach ($domain in $testDomains) {
                    Write-Log "`nTesting Domain: " 
                    Write-Host "`nTesting Domain: " -NoNewline -ForegroundColor $script:colorProcess
                    Write-Log $domain 
                    Write-Host $domain -ForegroundColor $script:colorValues

                    try {
                        $dnsTest = Resolve-DnsName $domain -QuickTimeout -ErrorAction Stop
                        $resolutionStatus = "Resolved to $($dnsTest.IPAddress -join ', ')"
                        Write-Log "Results:  " 
                        Write-Host "Results:  " -NoNewline -ForegroundColor $script:colorProcess
                        Write-Log $resolutionStatus 
                        Write-Host $resolutionStatus -ForegroundColor $script:colorSuccess
                    } catch {
                        Write-Log "Results:  " 
                        Write-Host "Results:  " -NoNewline -ForegroundColor $script:colorProcess
                        Write-Log "Unexpected error" 
                        Write-Host "Unexpected error" -ForegroundColor $script:colorError
                        Write-Log "Detail:      " 
                        Write-Host "Detail:      " -NoNewline -ForegroundColor $script:colorProcess
                        Write-Log $_.Exception.Message 
                        Write-Host $_.Exception.Message -ForegroundColor $script:colorValues
                        $script:dnsIssues = $true
                    }
                }

                # DNS troubleshooting logic
                if ($script:dnsIssues) {
                    Write-Log "`n`n[ATTEMPTING DNS TROUBLESHOOTING]" 
                    Write-Host "`n`n[ATTEMPTING DNS TROUBLESHOOTING]" -ForegroundColor $script:colorWarning

                    $alternativeConfigs = @(
                        @{ Name = "Google DNS"; Servers = @('8.8.8.8', '8.8.4.4') },
                        @{ Name = "Cloudflare DNS"; Servers = @('1.1.1.1', '1.0.0.1') }
                    )

                    foreach ($config in $alternativeConfigs) {
                        Write-Log "`nTrying $($config.Name)..." 
                        Write-Host "`nTrying $($config.Name)..." -ForegroundColor $script:colorProcess

                        try {
                            # Apply new DNS
                            Set-DnsClientServerAddress -InterfaceAlias $script:networkInterface -ServerAddresses $config.Servers -ErrorAction Stop

                            # Retest configuration
                            $tempIssues = $false
                            Write-Log "`n[RE-TESTING CONNECTIVITY]" 
                            Write-Host "`n[RE-TESTING CONNECTIVITY]" -ForegroundColor $script:colorProcess

                            foreach ($server in $config.Servers) {
                                Write-Log "Testing DNS: " 
                                Write-Host "Testing DNS: " -NoNewline -ForegroundColor $script:colorProcess
                                Write-Log $server 
                                Write-Host $server -ForegroundColor $script:colorValues

                                $pingTest = Test-NetConnection -ComputerName $server -InformationLevel Detailed -WarningAction SilentlyContinue
                                if (-not $pingTest.PingSucceeded) {
                                    $tempIssues = $true
                                    Write-Log "Reachable:  No" 
                                    Write-Host "Reachable:  No" -ForegroundColor $script:colorError
                                } else {
                                    Write-Log "Reachable:  Yes ($($pingTest.PingReplyDetails.RoundtripTime)ms)" 
                                    Write-Host "Reachable:  Yes ($($pingTest.PingReplyDetails.RoundtripTime)ms)" -ForegroundColor $script:colorSuccess
                                }
                            }

                            Write-Log "`n[RE-TESTING DOMAIN RESOLUTION]" 
                            Write-Host "`n[RE-TESTING DOMAIN RESOLUTION]" -ForegroundColor $script:colorProcess
                            foreach ($domain in $testDomains) {
                                try {
                                    $null = Resolve-DnsName $domain -QuickTimeout -ErrorAction Stop
                                    Write-Log "$domain resolution: Success" 
                                    Write-Host "$domain resolution: Success" -ForegroundColor $script:colorSuccess
                                } catch {
                                    $tempIssues = $true
                                    Write-Log "$domain resolution: Failed" 
                                    Write-Host "$domain resolution: Failed" -ForegroundColor $script:colorError
                                }
                            }

                            if (-not $tempIssues) {
                                Write-Log "`n[SUCCESS] DNS configuration updated successfully using $($config.Name)" 
                                Write-Host "`n[SUCCESS] DNS configuration updated successfully using $($config.Name)" -ForegroundColor $script:colorSuccess
                                return
                            }
                        } catch {
                            Write-Log "[ERROR] Failed to apply $($config.Name): $($_.Exception.Message)" 
                            Write-Host "[ERROR] Failed to apply $($config.Name): $($_.Exception.Message)" -ForegroundColor $script:colorError
                        }

                        # Revert to original DNS if issues persist
                        try {
                            Set-DnsClientServerAddress -InterfaceAlias $script:networkInterface -ServerAddresses $originalDns -ErrorAction Stop
                        } catch {
                            Write-Log "[CRITICAL] Failed to restore original DNS configuration!" 
                            Write-Host "[CRITICAL] Failed to restore original DNS configuration!" -ForegroundColor $script:colorError
                            return
                        }
                    }

                    Write-Log "`n[WARNING] All DNS troubleshooting attempts failed. Restored original configuration." 
                    Write-Host "`n[WARNING] All DNS troubleshooting attempts failed. Restored original configuration." -ForegroundColor $script:colorWarning
                }
            } catch {
                Write-Log "`n[ERROR] Failed to retrieve DNS configuration" 
                Write-Host "`n[ERROR] Failed to retrieve DNS configuration" -ForegroundColor $script:colorError
            }
        } else {
            Write-Log "`n[WARNING] Network interface not detected - skipping DNS server tests" 
            Write-Host "`n[WARNING] Network interface not detected - skipping DNS server tests" -ForegroundColor $script:colorWarning
        }

        if (-not $script:dnsIssues) {
            Write-Log "`n[INFO] DNS configuration validated successfully." 
            Write-Host "`n[INFO] DNS configuration validated successfully." -ForegroundColor $script:colorSuccess
            break
        }
    }

    if ($script:dnsIssues) {
        Write-Log "`n[ERROR] DNS configuration could not be validated after $maxRetries attempts." 
        Write-Host "`n[ERROR] DNS configuration could not be validated after $maxRetries attempts." -ForegroundColor $script:colorError
    }
}
#endregion Test-DNSConfiguration

<#
.SYNOPSIS
Tests connectivity to known Vivox endpoints for the Demonologist game.

.DESCRIPTION
1. Checks latency to each Vivox endpoint using ICMP (if allowed) with `Test-NetConnection`.
2. Tests TCP port 443 connectivity to each Vivox endpoint.
3. Notifies the user if ICMP is blocked or if port 443 is unreachable, indicating possible firewall restrictions.
4. Provides detailed results on latency and port reachability for each endpoint.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 01/26/2025
This function verifies the network connectivity to Vivox endpoints, ensuring that necessary ports are open and reachable for optimal voice service performance in Demonologist.
#>
function Test-VivoxEndpoints {
    Write-Log "`n[VIVOX ENDPOINT VALIDATION]" 
    Write-Host "`n[VIVOX ENDPOINT VALIDATION]" -ForegroundColor $script:colorProcess

    $vivoxEndpoints = @('188.42.147.158','85.236.98.214')
    foreach ($endpoint in $vivoxEndpoints) {
        Write-Log "`nEndpoint: " 
        Write-Host "`nEndpoint: " -NoNewline -ForegroundColor $script:colorProcess
        Write-Log $endpoint 
        Write-Host $endpoint -ForegroundColor $script:colorValues
        
        try {
            $pingTest = Test-NetConnection -ComputerName $endpoint -InformationLevel Detailed -WarningAction SilentlyContinue
            Write-Log "Latency:    " 
            Write-Host "Latency:    " -NoNewline -ForegroundColor $script:colorProcess
            if ($pingTest.PingSucceeded) {
                Write-Log "$($pingTest.PingReplyDetails.RoundtripTime)ms" 
                Write-Host "$($pingTest.PingReplyDetails.RoundtripTime)ms" -ForegroundColor $script:colorValues
            }
            else {
                Write-Log "N/A (ICMP blocked)" 
                Write-Host "N/A (ICMP blocked)" -ForegroundColor $script:colorWarning
            }
        }
        catch {
            Write-Log "Latency:    " 
            Write-Host "Latency:    " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log "Measurement failed" 
            Write-Host "Measurement failed" -ForegroundColor $script:colorError
        }

        try {
            $portTest = Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue
            
            Write-Log "Port 443:   " 
            Write-Host "Port 443:   " -NoNewline -ForegroundColor $script:colorProcess
            if ($portTest.TcpTestSucceeded) {
                Write-Log "Reachable" 
                Write-Host "Reachable" -ForegroundColor $script:colorSuccess
            }
            else {
                Write-Log "Blocked" 
                Write-Host "Blocked" -ForegroundColor $script:colorError
                Write-Log "Diagnosis:  " 
                Write-Host "Diagnosis:  " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "Firewall restriction or service unresponsive" 
                Write-Host "Firewall restriction or service unresponsive" -ForegroundColor $script:colorWarning
            }
        }
        catch {
            Write-Log "Port 443:   " 
            Write-Host "Port 443:   " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log "Test error" 
            Write-Host "Test error" -ForegroundColor $script:colorError
            Write-Log "Detail:     " 
            Write-Host "Detail:     " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log $_.Exception.Message 
            Write-Host $_.Exception.Message -ForegroundColor $script:colorValues
        }
    }
}
#endregion Test-VivoxEndpoints

#region Test-TimeConfiguration
<#
.SYNOPSIS
Tests and manages Windows Time service configuration for accurate time synchronization.

.DESCRIPTION
1. Checks if the Windows Time service (`w32time`) is set to Automatic startup type.
2. Starts the Windows Time service if it is not running.
3. Validates and repairs automatic time synchronization settings.
4. Retrieves and displays configured NTP servers.
5. Tests reachability of each NTP server using `Test-Connection`.
6. Forces a manual time synchronization using `w32tm /resync`.
7. Displays before and after timestamps to confirm successful synchronization.
8. Handles errors related to service management and NTP configuration.
9. Retries up to three times if errors occur, ensuring the configuration is correct.

.NOTES
Author: manny_agre
Creation Date: 01/25/2025
Last Modified: 01/26/2025
This function ensures that the Windows Time service is properly configured and synchronized, which is essential for network operations and services used by Demonologist.
#>
function Test-TimeConfiguration {
    Write-Log "`n`n======= TIME SERVICE ANALYSIS =======" 
    Write-Host "`n`n======= TIME SERVICE ANALYSIS =======" -ForegroundColor $script:colorProcess
    $retryCount = 0
    $maxRetries = 3
    $success = $false

    while (-not $success -and $retryCount -lt $maxRetries) {
        $retryCount++

        if ($retryCount -ge 2) {
            Write-Log "`n[INFO] Retrying validation and repair of configuration..." 
            Write-Host "`n[INFO] Retrying validation and repair of configuration..." -ForegroundColor $script:colorProcess
        }

        try {
            $w32time = Get-Service w32time -ErrorAction Stop

            Write-Log "`n[SERVICE STATUS]" 
            Write-Host "`n[SERVICE STATUS]" -ForegroundColor $script:colorProcess
            Write-Log "Service State:  " 
            Write-Host "Service State:  " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log $w32time.Status 
            Write-Host $w32time.Status -ForegroundColor $script:colorValues

            Write-Log "Startup Type:   " 
            Write-Host "Startup Type:   " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log $w32time.StartType 
            Write-Host $w32time.StartType -ForegroundColor $script:colorValues

            if ($w32time.StartType -ne 'Automatic') {
                Write-Log "`n[CONFIGURING SERVICE]" 
                Write-Host "`n[CONFIGURING SERVICE]" -ForegroundColor $script:colorProcess
                Set-Service -Name w32time -StartupType Automatic -ErrorAction Stop
                Write-Log "Startup type changed to: " 
                Write-Host "Startup type changed to: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "Automatic" 
                Write-Host "Automatic" -ForegroundColor $script:colorSuccess
            }

            if ($w32time.Status -ne 'Running') {
                Write-Log "`n[STARTING SERVICE]" 
                Write-Host "`n[STARTING SERVICE]" -ForegroundColor $script:colorProcess
                Start-Service w32time -ErrorAction Stop
                Write-Log "Service state changed to: " 
                Write-Host "Service state changed to: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "Running" 
                Write-Host "Running" -ForegroundColor $script:colorSuccess
            }

            Write-Log "`n[VALIDATING AUTOMATIC TIME SYNC]" 
            Write-Host "`n[VALIDATING AUTOMATIC TIME SYNC]" -ForegroundColor $script:colorProcess
            try {
                $currentSyncType = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -ErrorAction Stop).Type
                Write-Log "Sync Type: " 
                Write-Host "Sync Type: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log $currentSyncType 
                Write-Host $currentSyncType -ForegroundColor $script:colorValues

                if ($currentSyncType -ne "NTP") {
                    Write-Log "`n[REPAIRING SYNC CONFIGURATION]" 
                    Write-Host "`n[REPAIRING SYNC CONFIGURATION]" -ForegroundColor $script:colorProcess
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -Value "NTP" -ErrorAction Stop
                    Write-Log "Sync Type set to: " 
                    Write-Host "Sync Type set to: " -NoNewline -ForegroundColor $script:colorProcess
                    Write-Log "NTP" 
                    Write-Host "NTP" -ForegroundColor $script:colorSuccess
                    Write-Log "Windows Time service restarted successfully." Restart-Service w32time -ErrorAction Stop
                    Write-Host "Windows Time service restarted successfully." -ForegroundColor $script:colorSuccess
                }

            }
            catch {
                Write-Log "`n[ERROR] Automatic sync validation failed: $($_.Exception.Message)" 
                Write-Host "`n[ERROR] Automatic sync validation failed: $($_.Exception.Message)" -ForegroundColor $script:colorError
                continue
            }

            Write-Log "`n[NTP SERVER]" 
            Write-Host "`n[NTP SERVER]" -ForegroundColor $script:colorProcess
            $ntpConfig = w32tm /query /configuration 2>&1
            if ($LASTEXITCODE -ne 0) { throw "NTP configuration query failed" }

            $ntpServers = ($ntpConfig | Select-String 'NtpServer: ([^,]+)').Matches.Groups[1].Value
            if ($ntpServers) {
                $ntpServers | ForEach-Object {
                    Write-Log "Server:     " 
                    Write-Host "Server:     " -NoNewline -ForegroundColor $script:colorProcess
                    Write-Log $_ 
                    Write-Host $_ -ForegroundColor $script:colorValues

                    Write-Log "Reachable:  " 
                    Write-Host "Reachable:  " -NoNewline -ForegroundColor $script:colorProcess
                    $reachable = Test-Connection $_ -Count 2 -Quiet
                    Write-Log $(if ($reachable) {"Yes"} else {"No"}) 
                    Write-Host $(if ($reachable) {"Yes"} else {"No"}) -ForegroundColor $(if ($reachable) {$script:colorSuccess} else {$script:colorError})
                }
            }
            else {
                Write-Log "`n[ERROR] No NTP servers configured" 
                Write-Host "`n[ERROR] No NTP servers configured" -ForegroundColor $script:colorError
            }

            Write-Log "`n[TIME SYNCHRONIZATION]" 
            Write-Host "`n[TIME SYNCHRONIZATION]" -ForegroundColor $script:colorProcess
            $originalTime = Get-Date

            try {
                $timeZone = Get-TimeZone -ErrorAction Stop
                Write-Log "Time zone: " 
                Write-Host "Time zone: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($timeZone.Id) (UTC$($timeZone.BaseUtcOffset))" 
                Write-Host "$($timeZone.Id) (UTC$($timeZone.BaseUtcOffset))" -ForegroundColor $script:colorValues
            }
            catch {
                Write-Log "`n[ERROR] Failed to retrieve time zone" 
                Write-Host "`n[ERROR] Failed to retrieve time zone" -ForegroundColor $script:colorError
            }

            $syncResult = w32tm /resync 2>&1
            if ($LASTEXITCODE -eq 0) {
                $newTime = Get-Date
                Write-Log "Syncronization: " 
                Write-Host "Syncronization: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "Successful" 
                Write-Host "Successful" -ForegroundColor $script:colorSuccess
                Write-Log "Original time: " 
                Write-Host "Original time: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log $($originalTime.ToString("yyyy-MM-dd HH:mm:ss")) 
                Write-Host $($originalTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor $script:colorValues
                Write-Log "Updated time: " 
                Write-Host "Updated time: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log $($newTime.ToString("yyyy-MM-dd HH:mm:ss")) 
                Write-Host $($newTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor $script:colorSuccess
                $success = $true
            }
            else {
                Write-Log "`n[ERROR] Sync failed:n$($syncResult.ToString())" 
                Write-Host "`n[ERROR] Sync failed:n$($syncResult.ToString())" -ForegroundColor $script:colorError
            }
        }
        catch {
            Write-Log "`n[ERROR] Time service management failed" 
            Write-Host "`n[ERROR] Time service management failed" -ForegroundColor $script:colorError
            Write-Log "Details: $($_.Exception.Message)" 
            Write-Host "Details: $($_.Exception.Message)" -ForegroundColor $script:colorValues
        }
    }

    if (-not $success) {
        Write-Log "`n[ERROR] Failed to configure time synchronization after $maxRetries attempts." 
        Write-Host "`n[ERROR] Failed to configure time synchronization after $maxRetries attempts." -ForegroundColor $script:colorError
    } else {
        Write-Log "`n[INFO] Time synchronization configured successfully." 
        Write-Host "`n[INFO] Time synchronization configured successfully." -ForegroundColor $script:colorSuccess
    }
}
#endregion Test-TimeConfiguration

#region Get-InstallationAndHardwareInfo
<#
.SYNOPSIS
Retrieves system hardware information and determines the installation drive type.

.DESCRIPTION
1. Identifies the installation drive of the Demonologist game using the process path.
2. Determines the media type (SSD or HDD) of the installation drive.
3. Retrieves detailed GPU information including VRAM.
4. Retrieves detailed RAM module specifications and speeds.
5. Retrieves CPU model and core configuration.
6. Detects connected audio input/output devices.
7. Displays information in a structured, color-coded format.

.NOTES
Author: manny_agre
Creation Date: 01/26/2025
Last Modified: 01/26/2025
Provides comprehensive hardware insights for performance troubleshooting.
#>
function Get-InstallationAndHardwareInfo {
    try {
        Write-Log "`n`n======= HARDWARE INFORMATION =======" 
        Write-Host "`n`n======= HARDWARE INFORMATION =======" -ForegroundColor $script:colorProcess

        # Get installation drive details
        $processPath = $script:process.Path
        $driveLetter = (Get-Item $processPath).PSDrive.Root
        $partition = Get-Partition -DriveLetter $driveLetter.TrimEnd(':\') -ErrorAction Stop
        $disk = Get-Disk | Where-Object { $_.Number -eq $partition.DiskNumber } | Get-PhysicalDisk

        # Display storage information
        if ($disk) {
            Write-Log "`n[STORAGE DEVICE]" 
            Write-Host "`n[STORAGE DEVICE]" -ForegroundColor $script:colorProcess
            Write-Log "Model: " 
            Write-Host "Model: " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log "$($disk.FriendlyName)" 
            Write-Host "$($disk.FriendlyName)" -ForegroundColor $script:colorValues
            Write-Log "Media Type: " 
            Write-Host "Media Type: " -NoNewline -ForegroundColor $script:colorProcess
            Write-Log "$($disk.MediaType)" 
            Write-Host "$($disk.MediaType)" -ForegroundColor $script:colorValues

            # Check and warn if the media type is HDD
            if ($disk.MediaType -eq 'HDD') {
                Write-Log "`n[WARNING] The game is installed on an HDD. For optimal performance, it is recommended to install the game on an SSD." 
                Write-Host "`n[WARNING] The game is installed on an HDD. For optimal performance, it is recommended to install the game on an SSD." -ForegroundColor $script:colorError
            }
        }

        else {
            Write-Log "`n[ERROR] Failed to determine storage media type" 
            Write-Host "`n[ERROR] Failed to determine storage media type" -ForegroundColor $script:colorError
        }

        # Enhanced GPU information retrieval
        $gpuInfo = Get-WmiObject Win32_VideoController | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                VRAM = if ($_.AdapterRAM -gt 0) { 
                    [math]::Round($_.AdapterRAM / 1GB, 2) 
                } else { 
                    "Not reported" 
                }
            }
        }

        if ($gpuInfo) {
            Write-Log "`n[GRAPHICS CARD]" 
            Write-Host "`n[GRAPHICS CARD]" -ForegroundColor $script:colorProcess
            foreach ($gpu in $gpuInfo) {
                Write-Log "Model: " 
                Write-Host "Model: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($gpu.Name)" 
                Write-Host "$($gpu.Name)" -ForegroundColor $script:colorValues
                Write-Log "VRAM: " 
                Write-Host "VRAM: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($gpu.VRAM) GB`n" 
                Write-Host "$($gpu.VRAM) GB`n" -ForegroundColor $script:colorValues
            }
        }
        else {
            Write-Log "`n[ERROR] GPU details unavailable`n" 
            Write-Host "`n[ERROR] GPU details unavailable`n" -ForegroundColor $script:colorError
        }

        # Comprehensive RAM module analysis
        $ramModules = Get-CimInstance Win32_PhysicalMemory | Select-Object @(
            'Manufacturer',
            'PartNumber',
            @{Name = "CapacityGB"; Expression = { [math]::Round($_.Capacity / 1GB, 2) }},
            @{Name = "BaseSpeedMHz"; Expression = { $_.Speed }},
            @{Name = "ConfiguredSpeedMHz"; Expression = { $_.ConfiguredClockSpeed }}
        )

        if ($ramModules) {
            Write-Log "[MEMORY MODULES]" 
            Write-Host "[MEMORY MODULES]" -ForegroundColor $script:colorProcess
            foreach ($ram in $ramModules) {
                Write-Log "Manufacturer: " 
                Write-Host "Manufacturer: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($ram.Manufacturer)" 
                Write-Host "$($ram.Manufacturer)" -ForegroundColor $script:colorValues
                Write-Log "Part Number: " 
                Write-Host "Part Number: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($ram.PartNumber)" 
                Write-Host "$($ram.PartNumber)" -ForegroundColor $script:colorValues
                Write-Log "Capacity: " 
                Write-Host "Capacity: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($ram.CapacityGB) GB" 
                Write-Host "$($ram.CapacityGB) GB" -ForegroundColor $script:colorValues
                Write-Log "JEDEC Speed: " 
                Write-Host "JEDEC Speed: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($ram.BaseSpeedMHz) MHz" 
                Write-Host "$($ram.BaseSpeedMHz) MHz" -ForegroundColor $script:colorValues
                Write-Log "XMP Profile: " 
                Write-Host "XMP Profile: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($ram.ConfiguredSpeedMHz) MHz`n" 
                Write-Host "$($ram.ConfiguredSpeedMHz) MHz`n" -ForegroundColor $script:colorValues
            }
        }
        else {
            Write-Log "`n[ERROR] RAM specifications unavailable`n" 
            Write-Host "`n[ERROR] RAM specifications unavailable`n" -ForegroundColor $script:colorError
        }

        # Processor details
        $cpuInfo = Get-CimInstance Win32_Processor | Select-Object Name, 
            NumberOfCores, 
            NumberOfLogicalProcessors

        if ($cpuInfo) {
            Write-Log "[PROCESSOR]" 
            Write-Host "[PROCESSOR]" -ForegroundColor $script:colorProcess
            foreach ($cpu in $cpuInfo) {
                Write-Log "Model: " 
                Write-Host "Model: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($cpu.Name)" 
                Write-Host "$($cpu.Name)" -ForegroundColor $script:colorValues
                Write-Log "Physical Cores: " 
                Write-Host "Physical Cores: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($cpu.NumberOfCores)" 
                Write-Host "$($cpu.NumberOfCores)" -ForegroundColor $script:colorValues
                Write-Log "Logical Processors: " 
                Write-Host "Logical Processors: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($cpu.NumberOfLogicalProcessors)" 
                Write-Host "$($cpu.NumberOfLogicalProcessors)" -ForegroundColor $script:colorValues
            }
        }
        else {
            Write-Log "`n[ERROR] Processor information unavailable" 
            Write-Host "`n[ERROR] Processor information unavailable" -ForegroundColor $script:colorError
        }

        # Audio output devices (Speakers/Headphones)
        $audioOutput = Get-PnpDevice -Class AudioEndpoint -Status OK | 
            Where-Object { $_.FriendlyName -match 'speaker|headphone' } |
            Select-Object FriendlyName

        if ($audioOutput) {
            Write-Log "`n[AUDIO OUTPUT]" 
            Write-Host "`n[AUDIO OUTPUT]" -ForegroundColor $script:colorProcess
            foreach ($device in $audioOutput) {
                Write-Log "Device: " 
                Write-Host "Device: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($device.FriendlyName)" 
                Write-Host "$($device.FriendlyName)" -ForegroundColor $script:colorValues
            }
        }
        else {
            Write-Log "`n[ERROR] No audio output devices detected" 
            Write-Host "`n[ERROR] No audio output devices detected" -ForegroundColor $script:colorError
        }

        # Audio input devices (Microphones)
        $audioInput = Get-PnpDevice -Class AudioEndpoint -Status OK | 
            Where-Object { $_.FriendlyName -match 'microphone' } |
            Select-Object FriendlyName

        if ($audioInput) {
            Write-Log "`n[AUDIO INPUT]" 
            Write-Host "`n[AUDIO INPUT]" -ForegroundColor $script:colorProcess
            foreach ($device in $audioInput) {
                Write-Log "Device: " 
                Write-Host "Device: " -NoNewline -ForegroundColor $script:colorProcess
                Write-Log "$($device.FriendlyName)" 
                Write-Host "$($device.FriendlyName)" -ForegroundColor $script:colorValues
            }
        }
        else {
            Write-Log "`n[ERROR] No audio input devices detected" 
            Write-Host "`n[ERROR] No audio input devices detected" -ForegroundColor $script:colorError
        }
    }
    catch {
        Write-Log "`n[ERROR] Hardware information retrieval failed: $($_.Exception.Message)" 
        Write-Host "`n[ERROR] Hardware information retrieval failed: $($_.Exception.Message)" -ForegroundColor $script:colorError
    }
}
#endregion Get-InstallationAndHardwareInfo

Test-VivoxDemonologist