#######################################################################################################
##                                                                                                   ##
##  Script name: HaloRecalculateBilling.ps1                                                          ##
##  Purpose of script: Re-calculate billing for tickets that have already been "billing batched".    ##
##                     Workaround for when the re-calculation errors out in Halo portal.             ##
##                                                                                                   ##
##  Notes: Re-factored version of a script provided by Halo.                                         ##
##         Should work with PS 5.1 and newer.                                                        ##
##                                                                                                   ##
##  Author: Mart Roben                                                                               ##
##  Date Created: 24. Jul 2023                                                                       ##
##                                                                                                   ##
##  Copyright: MIT License                                                                           ##
##  https://github.com/martroben/halo/                                                               ##
##                                                                                                   ##
##  Contact: mart@altacom.eu                                                                         ##
##                                                                                                   ##
#######################################################################################################


##########
# Inputs #
##########

# Halo API credentials
# Necessary permission: read:tickets, edit:tickets. Login type: Agent
$clientId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$tenant = "<your_company>"
$apiUrl = "https://<your_company>.halopsa.com/api"
$authUrl = "https://<your_company>.halopsa.com/auth"

# Time zone - e.g. 3 = GMT+3 (comment out if not needed)
$gmtOffset = 3 

# Ticket date range (comment out if not needed)
$dateStart = "2023-05-01 14:00"
$dateEnd = "2023-01-01 15:00"

# Request types (comment out if not needed)
$requestTypeIds = 1, 4, 29   # 1 - Incident, 4 - Problem, 29 - Task

# Process tickets with ids starting from... (comment out if not needed)
# Intersects (doesn't override) date range
$ticketIdStart = 2500


##################################################
# Format input variables / handle missing values #
##################################################

if ( -not $gmtOffset) { $gmtOffset = 0 }
if ( -not $ticketIdStart) { $ticketIdStart = 0 }
if ( -not $requestTypeIds) { $requestTypeIds = $null }

$dateFormat = "yyyy-MM-ddTHH:mm:ss"   # Date format in Halo API requests
if ($dateStart -or $dateEnd) {
    # Fun fact: time starts on 1753-01-01 for Halo API
    if ( -not $dateStart) { $dateStart = (Get-Date -Date "1800-01-01").AddHours($gmtOffset) }
    if ( -not $dateEnd) { $dateEnd = Get-Date }
    # Convert date range to UTC time and to correct string format for API request
    $dateStartString = (Get-Date -Date $dateStart).AddHours(-$gmtOffset).ToString($dateFormat)
    $dateEndString = (Get-Date -Date $dateEnd).AddHours(-$gmtOffset).ToString($dateFormat)
} else {
    $dateStartString = $null
    $dateEndString = $null
}


###########################
# Get authorization token #
###########################

$tokenUrl = $authUrl + "/token" + "?tenant=" + $tenant
$tokenHeaders = @{
    "Content-Type" = "application/x-www-form-urlencoded"
    "Accept" = "application/json"
    "halo-app-name" = "halo-web-application"
}
$tokenBody = @{
    grant_type = "client_credentials"
    client_id = $clientId
    client_secret = $secret
    scope = "all"
}

Write-Host "Getting authorization token"
# POST request - authorization token
$tokenResponse = Invoke-RestMethod -Method 'POST' -Uri $tokenUrl -Headers $tokenHeaders -Body $tokenBody

$token = $tokenResponse.access_token
$headers = @{
    "Authorization" = "Bearer " + $token
    "halo-app-name" = "halo-web-application"
}


###############
# Get tickets #
###############

$ticketsUrl = $apiUrl + "/tickets/"
$ticketsBody = @{
    ticketidonly = $true
    startdate = $dateStartString
    enddate = $dateEndString
    requesttype = $requestTypeIds -join ","
}
# Remove null values from parameters
($ticketsBody.GetEnumerator() | Where-Object { -not $_.Value }) | ForEach-Object { $ticketsBody.Remove($_.Name) }

# GET request - tickets
Write-Host "Getting tickets"
$ticketsResponse = Invoke-RestMethod -Method 'GET' -Uri $ticketsUrl -Headers $headers -Body $ticketsBody

# Sort ticket ids in ascending order to be able to restart the process if it crashes
# Filter ticket ids by input criteria
$tickets = $ticketsResponse.tickets | Sort-Object id | Where-Object { $_.id -ge $ticketIdStart}
Write-Host "Found $($tickets.Count) tickets that match input criteria"


#######################
# Recalculate billing #
#######################

$ticketsPerLap = 20
$lapTimes = @()
$timer = [Diagnostics.Stopwatch]::StartNew()
foreach ($ticket in $tickets) {
    $ticketIndex = [array]::IndexOf($tickets, $ticket) + 1   # Ticket counter
    $actionsUrl =  $apiUrl + "/actions/"
    $actionsBody = @{
        excludesys = $true
        ticket_id = $ticket.id
    }
    
    # GET request - ticket actions
    $actionsResponse = Invoke-RestMethod -Method 'GET' -Uri $actionsUrl -Headers $headers -Body $actionsBody

    # Recalculate billing for each action
    foreach ($action in $actionsResponse.actions) {
        # Action identification string for log
        $actionString = "($ticketIndex/$($tickets.Count)) ticket $($ticket.id) $($ticket.client_name): action id $($action.id)"

        if ($action.timetaken -gt 0) {
            $recalculateBillingBody = @{
                id = $action.id
                ticket_id = $ticket.id
                recalculate_billing = $true
            }
            $recalculateBillingBodyJson = ConvertTo-Json @($recalculateBillingBody)   # Convert as array, because Halo POST takes only arrayed json
            
            # POST request - recalculate billing on action
            $recalculateBillingResponse = Invoke-RestMethod -Method 'POST' -Uri $actionsUrl -Headers $headers -Body $recalculateBillingBodyJson -ContentType "application/json"
            Write-Host "$actionString - recalculated" -fore green
        } else {
            Write-Host "$actionString - not recalculated, because no time entered on action" -fore red
        }
    }
    # Time stats 4shiz&giggles
    if ($ticketIndex % $ticketsPerLap -eq 0) {
        $runtimeMinutes = [Math]::Round($timer.ElapsedMilliseconds / 60e3, 2)
        $lapTimes += $runtimeMinutes - ($lapTimes | Measure-Object -Sum).Sum
        $lapAverageMinutes = ($lapTimes | Select -Last 10 | Measure-Object -Average).Average
        $ticketsPerMinute = [Math]::Round($ticketsPerLap / $lapAverageMinutes, 0)
        $timeRemainingMinutes = [Math]::Round(($tickets.Count - $ticketIndex) / $ticketsPerMinute, 2)
    	Write-Host "Run time: $runtimeMinutes minutes, average tempo: $ticketsPerMinute tickets per minute, estimated time remaining: $timeRemainingMinutes minutes"
    }
}

$timer.Stop()
