#######################################################################################################
##                                                                                                   ##
##  Script name: HaloRecalculateBilling.ps1                                                          ##
##  Purpose of script: Re-calculate billing for tickets that have already been "billing batched".    ##
##                     Workaround for when the same action in Halo portal results in an error.       ##
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
$clientId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$tenant = "<your_company>"
$apiUrl = "https://<your_company>.halopsa.com/api"
$authUrl = "https://<your_company>.halopsa.com/auth"

# Time zone (e.g. 3 = GMT+3). If in doubt, use 0
$gmtOffset = 3 

# Ticket date range (comment out if not needed)
$dateStart = "2010-05-11 14:00"
$dateEnd = "2023-05-11 15:00"

# Request types (comment out if not needed)
$requestTypeIds = 1, 4, 29   # 1 - Incident, 4 - Problem, 29 - Task

# Process tickets with ids starting from... (comment out if not needed)
$ticketIdStart = 2500


###########################################
# Format / handle missing input variables #
###########################################

if ( -not $ticketIdStart) { $ticketIdStart = 0 }

if ($dateStart -and $dateEnd) {
    # Convert date range to UTC time and to correct string format for API request
    $dateFormat = "yyyy-MM-ddTHH:mm:ss"   # Date format in Halo API requests
    $dateStartString = (Get-Date -Date $dateStart).AddHours(-$gmtOffset).ToString($dateFormat)
    $dateEndString = (Get-Date -Date $dateEnd).AddHours(-$gmtOffset).ToString($dateFormat)
} else {
    $dateStartString = $null
    $dateEndString = $null
}

if ($requestTypeIds) {
    $requestTypeString = $requestTypeIds -join ","
} else {
    $requestTypeString = $null
}


###########################
# Get authorization token #
###########################

$tokenUrl = $authUrl + "/token"+ "?tenant=" + $tenant
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

# POST request - authorization token
Write-Host "Getting authorization token"
$tokenResponse = Invoke-RestMethod -Method 'POST' -Uri $tokenUrl -Headers $tokenHeaders -Body $tokenBody
$token = $tokenResponse.access_token


###############
# Get tickets #
###############

$ticketsUrl = $apiUrl + "/tickets/"
$ticketsHeaders = @{
    "Authorization" = "Bearer " + $token
    "halo-app-name" = "halo-web-application"
}

$ticketsBody = @{
    ticketidonly = $true
    dateStart = $dateStartString
    dateEnd = $dateEndString
    requesttype = $requestTypeString
}

# Remove null values from ticket request GET parameters
($ticketsBody.GetEnumerator() | Where-Object { -not $_.Value }) | ForEach-Object { $ticketsBody.Remove($_.Name) }

# GET request - tickets
Write-Host "Getting tickets"
$ticketsResponse = Invoke-RestMethod -Method 'GET' -Uri $ticketsUrl -Headers $ticketsHeaders -Body $ticketsBody

# Sort tickets ascendingly to be able to restart process if it crashes
$tickets = $ticketsResponse.tickets | Sort-Object id | Where-Object { $_.id -ge $ticketIdStart}
Write-Host $tickets.Count "tickets found that match input criteria"


#######################
# Recalculate billing #
#######################

$actionsUrl =  $apiUrl + "/actions/"
$actionsHeaders = @{
    "Authorization" = "Bearer " + $token
    # "Content-Type" = "application/json"
    "halo-app-name" = "halo-web-application"
}

foreach ($ticket in $tickets) {
   
    $ticketIndex = [array]::IndexOf($tickets, $ticket) + 1
    $actionBody = @{
        excludesys = $true
        ticket_id = $ticket.id
    }
    # GET request - ticket actions
    $actionResponse = Invoke-RestMethod -Method 'GET' -Uri $actionsUrl -Headers $actionsHeaders -Body $actionBody

    # Recalculate billing for each action
    foreach ($action in $actionResponse.actions) {
        # Action identification string for log
        $actionString = "($ticketIndex/$($tickets.Count)) ticket $($ticket.id) $($ticket.client_name): action id $($action.id)"

        if ($action.timetaken -gt 0) {
            $recalculateBillingBody = @()   # Initialize as an array, because Halo POST request takes only arrayed json
            $recalculateBillingBody += @{
                id = $action.id
                ticket_id = $ticket.id
                recalculate_billing = $true
            }
            $recalculateBillingBodyJson = ConvertTo-Json $recalculateBillingBody

            # POST request - recalculate billing on action
            $recalculateBillingResponse = Invoke-RestMethod -Method 'POST' -Uri $actionsUrl -Headers $actionsHeaders -Body $recalculateBillingBodyJson -ContentType "application/json"
            Write-Host $actionString "- recalculated" -fore green
        }
        else {
            Write-Host $actionString "- not recalculated, because no time entered on action" -fore red
        }
    }
}
