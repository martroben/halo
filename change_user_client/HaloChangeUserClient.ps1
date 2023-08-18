#######################################################################################################
##                                                                                                   ##
##  Script name: HaloChangeUserClient.ps1                                                            ##
##  Purpose of script: Batch change assigned client of many users, based on input xlsx.              ##
##                                                                                                   ##
##  Notes: See included input_sample.xlsx for input format & column names.                           ##
##                                                                                                   ##
##  Author: Mart Roben                                                                               ##
##  Date Created: 18. Aug 2023                                                                       ##
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
# Necessary permissions: read:customers, edit:customers. Login type: Agent
$clientId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$tenant = "<your_company>"
$apiUrl = "https://<your_company>.halopsa.com/api"
$authUrl = "https://<your_company>.halopsa.com/auth"
$inputXlsxPath = "changes.xlsx"


##########################
# Install/import modules #
##########################

$requiredModules = @(
    "ImportExcel"
)
$missingModules = $requiredModules | Where-Object { !($_ -in (Get-Module -ListAvailable).Name) }

if ( $missingModules ) {
    Write-Error "The following required modules are not installed: $($missingModules -join ', ').`r`nYou can install them by 'Install-Module <module name>' command"
} else {
    Import-Module ImportExcel
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


#############
# Get users #
#############

$usersUrl = $apiUrl + "/users/"

Write-Host "Getting user id list"
$continue = $true
$i_page = 1
while ($continue) {
    $usersBody = @{
        pageinate = $true
        page_size = 50
        page_no = $i_page
    }

    # GET request - users
    $usersResponse = Invoke-RestMethod -Method 'GET' -Uri $usersUrl -Headers $headers -Body $usersBody
    $users += $usersResponse.users
    $i_page += 1
    $continue = $usersResponse.users.Count
}
Write-Host "Found $($users.Count) users"
Remove-Variable continue, i_page


###############
# Get clients #
###############

$clientsUrl = $apiUrl + "/client/"

Write-Host "Getting client id list"
$continue = $true
$i_page = 1
while ($continue) {
    $clientsBody = @{
        pageinate = $true
        page_size = 50
        page_no = $i_page
    }

    # GET request - users
    $clientsResponse = Invoke-RestMethod -Method 'GET' -Uri $clientsUrl -Headers $headers -Body $clientsBody
    $clients += $clientsResponse.clients
    $i_page += 1
    $continue = $usersResponse.clients.Count
}
Write-Host "Found $($clients.Count) clients"
Remove-Variable continue, i_page


###################
# Read input xlsx #
###################

$changesRaw = Import-Excel -Path $inputXlsxPath


##############################
# Join user id and client id #
##############################

# Get user id and client id references
$userIds = @{}
$users | Where-Object {$_.emailaddress} | ForEach-Object { $userIds[$_.emailaddress] = $_.id }

$clientIds = @{}
$clients | ForEach-Object { $clientIds[$_.name] = $_.id }

$changes = @()
$changesRaw | ForEach-Object { 
    $changes += [pscustomobject]@{ 
        user_email = $_.email
        client_name = $_.client
        site_name = $_.site
        user_id = $userIds[$_.email]
        client_id = $clientIds[$_.client]
        site_id = $null
    }
}

# Discard entried with missing user ids and client ids
$missingUserid = ($changes | Where-Object { !$_.user_id }).user_email | Get-Unique
$missingClientid = ($changes | Where-Object { !$_.client_id }).client_name | Get-Unique

if ($missingUserid) { Write-Warning "Skipping the following input e-mails (no matches found in Halo): $($missingUserid -join ', ')" }
if ($missingClientid) { Write-Warning "Skipping the following input clients (no matches found in Halo): $($missingClientid -join ', ')" }

$changesExistingUsersClients = $changes | Where-Object { $_.user_id -and $_.client_id }

# Change site name to Main for entries that don't have a site name specified
$changesExistingUsersClients | ForEach-Object { if ($_.site_name -eq $null ) {$_.site_name = "Main"} }


#############
# Get sites #
#############

$inputClients = $changesExistingUsersClients | Select-Object client_name, client_id -Unique
$sitesUrl = $apiUrl + "/site/"

$sites = @()
foreach ($client in $inputClients) {
    $sitesBody = @{
        client_id = $client.client_id
    }
    Write-Host "Getting site id list for client $($client.client_name)"
    # GET request - sites
    $sitesResponse = Invoke-RestMethod -Method 'GET' -Uri $sitesUrl -Headers $headers -Body $sitesBody
    Write-Host "-- found $($sitesResponse.sites.Count) sites"
    $sites += $sitesResponse.sites
}


#######################
# Join target site id #
#######################

foreach ($change in $changesExistingUsersClients) {
    $change.site_id = ($sites | Where-Object { $_.client_id  -eq $change.client_id -and $_.name -eq $change.site_name }).id
}

# Discard entried with missing site ids
$missingSiteid = $changesExistingUsersClients |
    Where-Object { !$_.site_id } |
    ForEach-Object { $_.client_name, $_.site_name -join "/" } |
    Sort-Object |
    Get-Unique

if ($missingSiteid) { Write-Warning "Skipping the following input client/site combinations (no matches found in Halo): $($missingSiteid -join ', ')" }

$changesToApply = $changesExistingUsersClients | Where-Object { $_.site_id }


#########################
# Execute modifications #
#########################

$usersUrl =  $apiUrl + "/users/"
foreach ($operation in $changesToApply) {
    $operationIndex = [array]::IndexOf($changesToApply, $operation) + 1   # Post request counter
    # Change identification string for log
    $operationString = "($operationIndex/$($changesToApply.Count)) Assigning user $($operation.user_email) (id: $($operation.user_id)) to $($operation.client_name)/$($operation.site_name) (id: $($operation.client_id)/$($operation.site_id))"

    $operationBody = @{
        id = $operation.user_id
        site_id = $operation.site_id
    }

    $operationBodyJson = ConvertTo-Json @($operationBody)   # Convert as array, because Halo POST takes only arrayed json
    
    # POST request - modify client on user
    $operationResponse = Invoke-WebRequest -Method 'POST' -Uri $usersUrl -Headers $headers -Body $operationBodyJson -ContentType "application/json"
    if ( $operationResponse.StatusCode -eq 201 ) { 
        Write-Host "$operationString - success" -fore green
    } else { 
        Write-Warning "$operationString - fail: $($operationResponse.StatusDescription)"
    }
}
