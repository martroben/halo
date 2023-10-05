#######################################################################################################
##                                                                                                   ##
##  Script name: HaloReassignBillingTemplates.ps1                                                    ##
##  Purpose of script: Cycle through all Billing Templates and re-assign them to Clients             ##
##                     Simulates the "Update Customers" button in Configuration > Billing >          ##
##                     > Billing templates. If that is not done, any update in Billing Templates     ##
##                     would only apply to Clients to which templates are newly assigned.            ##
##                                                                                                   ##
##  Author: Mart Roben                                                                               ##
##  Date Created: 28. Aug 2023                                                                       ##
##                                                                                                   ##
##  Copyright: MIT License                                                                           ##
##  https://github.com/martroben/halo/                                                               ##
##                                                                                                   ##
##  Contact: mart@altacom.eu                                                                         ##
##                                                                                                   ##
#######################################################################################################

# DEV NOTES
# Script uses the undocumented Halo API endpoint /BillingTemplate/

# Principle:
# 1. Get a list of all Billing Templates
# 2. Get a list of Clients for each Billing Template
# 3. Cycle through each Client under each Billing Template and apply the _apply_billingtemplate payload

# It seems that Actions that are inserted within minutes before applying the script sometimes get
# billed by the updated template and sometimes not. It's probably a good idea to use it together with the
# recalculate billing script to update all previous Actions to the new Billing Template.


##########
# Inputs #
##########

# Halo API credentials
# Necessary permissions: read:customers, edit:customers. Login type: Agent
$clientId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$tenant = "<your_company>"
$apiUrl = "https://<your_company>.halopsa.com/api"
$authUrl = "https://<your_company>.halopsa.com/auth"


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
$tokenResponse = Invoke-RestMethod -Method "POST" -Uri $tokenUrl -Headers $tokenHeaders -Body $tokenBody

$token = $tokenResponse.access_token
$headers = @{
    "Authorization" = "Bearer " + $token
    "halo-app-name" = "halo-web-application"
}

# Timer to check for token timeout
$tokenTimer = [Diagnostics.Stopwatch]::StartNew()
$tokenExpiry = $tokenResponse.expires_in


#############################
# Get all Billing Templates #
#############################

$billingTemplateUrl = $apiUrl + "/BillingTemplate/"
$billingTemplateBody = @{
    showall = $true
}

Write-Host "Getting the list of Billing Templates from Halo API"
# GET request - billing templates
$billingTemplateResponse = Invoke-RestMethod -Method "GET" -Uri $billingTemplateUrl -Headers $headers -Body $billingTemplateBody
Write-Host "Billing Templates found: $($billingTemplateResponse.Count)"


################################
# Get Billing Template details #
################################

$billingTemplatesRaw = @()
Write-Host "Getting details for each Billing Template from Halo API"
foreach ($billingTemplate in $billingTemplateResponse) {
    $billingTemplateDetailsUrl = $billingTemplateUrl + "$($billingTemplate.id)/"
    $billingTemplateDetailsBody = @{
        includedetails = $true
    }
    # GET request - billing template details
    $billingTemplateDetailsResponse = Invoke-RestMethod -Method "GET" -Uri $billingTemplateDetailsUrl -Headers $headers -Body $billingTemplateDetailsBody
    $billingTemplatesRaw += $billingTemplateDetailsResponse
}

$billingTemplates = $billingTemplatesRaw | Select-Object id, name, clients | Where-Object { $_.clients }
Write-Host "Billing Templates that are actually used on Clients: $($billingTemplates.Count)"


#########################################
# Re-apply Billing Templates to Clients #
#########################################

$clientsUrl = $apiUrl + "/Client/"
$nTotalOperations = ($billingTemplates | Foreach-Object {$_.clients.Count} | measure-Object -sum).Sum

Write-Host "Re-applying Billing Templates to Clients"
foreach ($billingTemplate in $billingTemplates) {
    foreach ($clientId in $billingTemplate.clients) {
        # Operation identification string for log
        $OperationIndex += 1
        $operationString = "($operationIndex/$nTotalOperations) Re-applying Billing Template $($billingTemplate.name) (id: $($billingTemplate.id)) to Client"

        $applyBillingTemplateBody = @{
            id = $clientId
            billingtemplate_id = $billingTemplate.id
            _apply_billingtemplate = $true
            # parameters _forcereassign and _appointment01_ok are used in Halo portal web request,
            # but I don't know what they're for
            _forcereassign = $true
            _appointment01_ok = $true
        }
        $applyBillingTemplateBodyJson = ConvertTo-Json @($applyBillingTemplateBody)
        
        try {
            # POST request - re-apply billing template to client
            $applyBillingTemplateResponse = Invoke-WebRequest -Method 'POST' -Uri $clientsUrl -Headers $headers -Body $applyBillingTemplateBodyJson -ContentType "application/json"
        } catch {
            $errorCode = "$($_.Exception.Response.StatusCode.Value__) ($($_.Exception.Response.StatusCode))"
            write-Warning "$operationString (client id: $clientId) - fail: $($errorCode)"
        }
        if ( $applyBillingTemplateResponse.StatusCode -eq 201 ) { 
            $clientName = ($applyBillingTemplateResponse.Content | ConvertFrom-Json).name
            Write-Host "$operationString $clientName (client id: $clientId) - success" -fore green
        }

        # Refresh token if time to expiry is less than 5 minutes
        if ($tokenExpiry - $tokenTimer.Elapsed.TotalSeconds -le 300) {
            Write-Host "Refreshing authorization token"
            # POST request - authorization token
            $tokenResponse = Invoke-RestMethod -Method 'POST' -Uri $tokenUrl -Headers $tokenHeaders -Body $tokenBody
            $tokenTimer = [Diagnostics.Stopwatch]::StartNew()
            $token = $tokenResponse.access_token
            $tokenExpiry = $tokenResponse.expires_in
            $headers = @{
                "Authorization" = "Bearer " + $token
                "halo-app-name" = "halo-web-application"
            }
        }
    }
}
