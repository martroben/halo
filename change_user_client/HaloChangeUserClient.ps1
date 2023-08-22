#######################################################################################################
##                                                                                                   ##
##  Script name: HaloChangeUserClient.ps1                                                            ##
##  Purpose of script: Batch change assigned client of many users, based on input xlsx.              ##
##                                                                                                   ##
##  Notes: See included input_sample.xlsx for input format & column names.                           ##
##         Uses site name 'Main' as default.                                                         ##
##         If several users have the same username and site, changes all of them.                    ##
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
$inputXlsxPath = "sample_input.xlsx"


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
    Import-Module -Name $requiredModules
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

Write-Host "Getting User list from Halo API"
$continue = $true
$i_page = 1
while ($continue) {
    $usersBody = @{
        pageinate = $true
        page_size = 50
        page_no = $i_page }
    # GET request - users
    $usersResponse = Invoke-RestMethod -Method 'GET' -Uri $usersUrl -Headers $headers -Body $usersBody
    $usersRaw += $usersResponse.users
    $i_page += 1
    $continue = $usersResponse.users.Count
}
Write-Host "Users found: $($usersRaw.Count)"
Remove-Variable continue, i_page


###############
# Get clients #
###############

$clientsUrl = $apiUrl + "/client/"

Write-Host "Getting Client list from Halo API"
$continue = $true
$i_page = 1
while ($continue) {
    $clientsBody = @{
        pageinate = $true
        page_size = 50
        page_no = $i_page
    }

    # GET request - clients
    $clientsResponse = Invoke-RestMethod -Method 'GET' -Uri $clientsUrl -Headers $headers -Body $clientsBody
    $clients += $clientsResponse.clients
    $i_page += 1
    $continue = $clientsResponse.clients.Count
}
Write-Host "Clients found: $($clients.Count)"
Remove-Variable continue, i_page


#############
# Get sites #
#############

$sitesUrl = $apiUrl + "/site/"

Write-Host "Getting Site list from Halo API"
$continue = $true
$i_page = 1
while ($continue) {
    $sitesBody = @{
        pageinate = $true
        page_size = 50
        page_no = $i_page
    }

    # GET request - sites
    $sitesResponse = Invoke-RestMethod -Method 'GET' -Uri $sitesUrl -Headers $headers -Body $sitesBody
    $sites += $sitesResponse.sites
    $i_page += 1
    $continue = $sitesResponse.sites.Count
}
Write-Host "Sites found: $($sites.Count)"
Remove-Variable continue, i_page


###################
# Read input xlsx #
###################

Write-Host "Reading input xlsx"
$inputXlsx = Import-Excel -Path $inputXlsxPath
Write-Host "Input lines read: $($inputXlsx.Count)"

$defaultProperties = @(
    'username'
    'client_name'
    'site_name'
    'new_client_name'
    'new_site_name'
    'user_id'
    'site_id'
    'new_site_id'
)
$defaultSite = 'Main'

foreach ($inputLine in $inputXlsx) {
    # Add default properties
    foreach ( $propertyName in $defaultProperties ) {
        if ( !($propertyName -in $inputLine.PSobject.Properties.Name) ) {
            $inputLine | Add-Member -Name $propertyName -Type NoteProperty -Value $null } }
    # Fill missing sites with default site
    if ( !$inputLine.site_name ) { $inputLine.site_name = $defaultSite }
    if ( !$inputLine.new_site_name ) { $inputLine.new_site_name = $defaultSite }
    $inputLine = $inputLine | Select-Object $defaultProperties
}

##########################
# Add user info to input #
##########################

# Select necessary fields from raw user data
$users = @()
foreach ( $user in $usersRaw ) {
    $users += [PSCustomObject]@{
        username = $user.name
        client_name = $user.client_name
        site_name = $user.site_name
        user_id = $user.id }
}
# Match user info with input xlsx info
$operations = @()
foreach ( $inputLine in $inputXlsx ) {
    $matchingUsers = $users | Where-Object {
        # Find users with matching username, client and site
        $_.username -eq $inputLine.username -and
        $_.client_name -eq $inputLine.client_name -and
        $_.site_name -eq $inputLine.site_name
    }
    # Include all users with matching username, client and site
    foreach ( $match in $matchingUsers ) {
        # Add default properties
        foreach ( $propertyName in $defaultProperties ) {
            if ( !($propertyName -in $match.PSObject.Properties.Name) ) {
                $match | Add-Member -Name $propertyName -Type NoteProperty -Value $null
            } }
        # Copy target client and site to all matching users
        $match.new_client_name = $inputLine.new_client_name
        $match.new_site_name = $inputLine.new_site_name
    }
    if ( !$matchingUsers ) {
        # If no matching users are found, return the input line with empty user_id property 
        $matchingUsers = $inputLine
    }
    $operations += $matchingUsers
}

##########################
# Add site info to input #
##########################

foreach ( $operation in $operations ) {
    $matchingCurrentSite = $sites | Where-Object {
        $_.client_name -eq $operation.client_name -and
        $_.name -eq $operation.site_name}

    $matchingNewSite = $sites | Where-Object {
        $_.client_name -eq $operation.new_client_name -and
        $_.name -eq $operation.new_site_name}
    
    $operation.site_id = $matchingCurrentSite.id
    $operation.new_site_id = $matchingNewSite.id
}

#########################
# Handle invalid inputs #
#########################

# Check for missing user_id and new_site_id
$unknownUsers = $operations | Where-Object { !$_.user_id }
$unknownUsersNames = $unknownUsers | ForEach-Object { "$($_.username)@$($_.client_name)/$($_.site_name)" }
$unknownNewSites = $operations | Where-Object { !$_.new_site_id }
$unknownNewSitesNames = $unknownNewSites | ForEach-Object { "$($_.new_client_name)/$($_.new_site_name)" } | Get-Unique

if ( $unknownUsers ) { Write-Warning "Skipping the following Users. No matches found in Halo: $($unknownUsersNames-join ', ')" }
if ( $unknownNewSites ) { Write-Warning "Skipping the following target Sites. No matches found in Halo: $($unknownNewSitesNames -join ', ')" }

# Discard operations with invalid user_id or new_site_id
$operationsToApply = $operations | Where-Object { $_.user_id -and $_.new_site_id }


#########################
# Execute modifications #
#########################

$usersUrl =  $apiUrl + "/users/"
foreach ($operation in $operationsToApply) {
    $operationIndex = [array]::IndexOf($operationsToApply, $operation) + 1
    # ^ Post request counter
    # Change identification string for log
    $operationString = "($operationIndex/$($operationsToApply.Count)) Ressigning user $($operation.username) (user_id: $($operation.user_id)): $($operation.client_name)/$($operation.site_name) --> $($operation.new_client_name)/$($operation.new_site_name) (site_id: $($operation.new_site_id))"

    $operationBody = @{
        id = $operation.user_id
        site_id = $operation.new_site_id
        _isnew = $false
    }
    $operationBodyJson = ConvertTo-Json @($operationBody)
    # Convert as array because Halo POST^ takes only arrayed json
    
    try {
        # POST request - modify client/site on user
        $operationResponse = Invoke-WebRequest -Method 'POST' -Uri $usersUrl -Headers $headers -Body $operationBodyJson -ContentType "application/json"
    } catch {
        $errorCode = "$($_.Exception.Response.StatusCode.Value__) ($($_.Exception.Response.StatusCode))"
        write-Warning "$operationString - fail: $($errorCode)"
    }
    if ( $operationResponse.StatusCode -eq 201 ) { 
        Write-Host "$operationString - success" -fore green
    }
}
