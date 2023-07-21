
################
# Static input #
################
# Halo API Details
$clientid = ""
$secret = ""
$apiurl = ""
$authurl = ""
$tenant= ""


##################
# Variable input #
##################
# Ticket date range
$startdate = "2023-05-10T23:00:00.000Z"
$enddate = "2023-05-11T23:00:00.000Z"


###########################
# Get authorization token #
###########################
$urlToken = $authurl + "/token"+ "?tenant=" + $tenant
$headersToken = @{
    "Content-Type" = "application/x-www-form-urlencoded"
    "Accept" = "application/json"
    "halo-app-name" = "halo-web-application"
}
$bodyToken = @{
    "grant_type" = "client_credentials"
    "client_id" = $clientid
    "client_secret" = $secret
    "scope" = "all"
}

$responseToken = Invoke-RestMethod -Method 'POST' -Uri $urlToken -Headers $headersToken -Body $bodyToken
$token = $responseToken.access_token


###############
# Get tickets #
###############
$urlTickets = $apiurl + "/tickets/"
$headersTickets = @{
    Authorization = "Bearer " + $token
    "halo-app-name" = "halo-web-application"
}
$bodyTickets = @{
    ticketidonly = $true
    startdate = $startdate
    enddate = $enddate
}

$responseTickets = Invoke-RestMethod -Method 'GET' -Uri $urlTickets -Headers $headersTickets -Body $bodyTickets
$jsonTickets = ConvertTo-Json -InputObject $responseTickets   



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
