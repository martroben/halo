
#################
# Static inputs #
#################
# Halo API Details
$clientId = ""
$secret = ""
$apiUrl = ""
$authUrl = ""
$tenant = ""

# Other
$dateFormat = "yyyy-MM-ddTHH:mm:ss"   # Date format in Halo API requests
$gmtOffset = 3   # Time zone (e.g. 3 = GMT+3)


###################
# Variable inputs #
###################
# Comment out if not needed

# Ticket date range
$startDate = "2010-05-11 14:00"
$endDate = "2023-05-11 15:00"

# Request types
$requestTypeIds = 1, 4, 29   # 1 - Incident, 4 - Problem, 29 - Task


###########################
# Get authorization token #
###########################

$urlToken = $authUrl + "/token"+ "?tenant=" + $tenant
$headersToken = @{
    "Content-Type" = "application/x-www-form-urlencoded"
    "Accept" = "application/json"
    "halo-app-name" = "halo-web-application"
}
$bodyToken = @{
    "grant_type" = "client_credentials"
    "client_id" = $clientId
    "client_secret" = $secret
    "scope" = "all"
}

$responseToken = Invoke-RestMethod -Method 'POST' -Uri $urlToken -Headers $headersToken -Body $bodyToken
$token = $responseToken.access_token


###############
# Get tickets #
###############

$urlTickets = $apiUrl + "/tickets/"
$headersTickets = @{
    Authorization = "Bearer " + $token
    "halo-app-name" = "halo-web-application"
}

# Only apply filters if variables are defined
if ($startDate -and $endDate) {
    # Convert date range to UTC time and to correct string format for API request
    $startDateString = (Get-Date -Date $startDate).AddHours(-$gmtOffset).ToString($dateFormat)
    $endDateString = (Get-Date -Date $endDate).AddHours(-$gmtOffset).ToString($dateFormat)
} else {
    $startDateString, $endDateString = $null
}

if ($requestTypeIds) {
    $requestTypeString = $requestTypeIds -join ","
} else {
    $requestTypeString = $null
}


$bodyTickets = @{
    startdate = $startDateString
    enddate = $endDateString
    requesttype = $requestTypeString
}

# Remove null values from request parameters
($bodyTickets.GetEnumerator() | ? { -not $_.Value }) | % { $bodyTickets.Remove($_.Name) }

$responseTickets = Invoke-RestMethod -Method 'GET' -Uri $urlTickets -Headers $headersTickets -Body $bodyTickets



## Check each Invoice for External Invoice Number - Start

$unpacked = $jsonTickets | ConvertFrom-Json 


$actionsBaseURL =  $apiurl+"/Actions";
$actionsURL =  $apiurl+"/Actions?excludesys=true";


foreach($obj in $unpacked.tickets)
{
   
        #Write-Host ("Ticket Halo ID = " + $obj.id)
        $actionGet = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $actionGet.Add("Authorization", "Bearer "+$token)
        $actionGet.Add("Content-Type", "application/json") 
        $actionGet.Add("halo-app-name","halo-web-application")       
        
        $oneActionURL = $actionsURL+"&ticket_id="+$obj.id
        ##Write-Host ($oneActionURL)
        $responseActionGet = Invoke-RestMethod $oneActionURL -Method 'GET' -Headers $actionGet 
        $jsonActions = ConvertTo-Json -InputObject $responseActionGet 
        
        $unpackedActions = $jsonActions | ConvertFrom-Json 
        foreach($obj2 in $unpackedActions.actions)
        {
            #Write-Host ("Ticket ID = "+$obj.id+" Action ID = " + $obj2.id)
            #$timetaken = [Float] $obj2.timetaken
            if ($obj2.timetaken -gt 0){
                $actionPost = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $actionPost.Add("Authorization", "Bearer "+$token)
                $actionPost.Add("Content-Type", "application/json")
                $actionPost.Add("halo-app-name","halo-web-application")

                $bodyActionPost = '[{"id":'+$obj2.id+',"ticket_id":"'+$obj.id+'","recalculate_billing":true}]'

                $responseActionRecalc = Invoke-RestMethod $actionsBaseURL -Method 'POST' -Headers $actionPost -Body $bodyActionPost
                $jsonPostResponse = ConvertTo-Json -InputObject $responseActionRecalc 
                $unpackedPostResponse = $jsonPostResponse | ConvertFrom-Json 
                write-host("Ticket ID = "+$obj.id+" Action ID = "+$unpackedPostResponse.id+" - recalculated (for Client = "+$obj.client_name+")") -fore green
            }
            else{
               #write-host("Ticket ID = "+$obj.id+" Action ID = "+$obj2.id+" - not recalculated (for Client = "+$obj.client_name+") as no time entered") -fore red
            }
        }
    
}

## Check each Invoice for External Invoice Number - End 
