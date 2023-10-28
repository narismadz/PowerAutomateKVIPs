## using PowerShell Module 
## Install-Module -Name Az.KeyVault -RequiredVersion 4.10.0
## You can test Az.KeyVault update version as well if you wish

$kvname = "powerautomatetest-champ"
$RG = "PowerPlatform"
$url = "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_"

### need to add this svcprincipal as "Key Vault Contributor" role at Azure Key Vault level ### 
$TenantId = "c73d22fa-fef7-4582-8384-xxxxxxxxxxxx"
$AppId = "720969af-6d01-4e5a-beb8-xxxxxxxxxxxx"
$Secret = "xxxxxxxxxxxxxxxxxxxxx"
$AzureSubscriptionId = "fa123294-49e4-4282-82f2-xxxxxxxxx"

#################################################################################################

<# Get the latest Ip for 2 services tags 
AzureConnectors.EastAsia and AzureConnectors.SouthEastAsia
from Microsoft download site
#>

$last_week = (Get-Date)
while ($last_week.DayOfWeek -ne "Monday") {
$last_week = $last_week.AddDays(-1)
}
$last_week = $last_week.ToString("yyyyMMdd")
$last_week
$url = $url + $last_week + ".json"

########################## Download the service tags for Azure services ##########################

# Check if Microsoft release any new IPs? - If not then we got error: (404) Not Found
try {
    $ip_ranges = Invoke-RestMethod $url -Method "GET"
    Write-Host "Microsoft releases new IPs" -ForegroundColor Yellow 
    Write-Host "Getting IPs for 2 services tags: AzureConnectors.EastAsia and AzureConnectors.SouthEastAsia" -ForegroundColor Yellow
}
catch {
    Write-Host "Got Error: $($_.Exception.Message)" -ForegroundColor Green 
    Write-Host "Microsoft doesn't releases new IPs yet" -ForegroundColor Green 
    exit
}

$IPRangesEa = $ip_ranges.values | Where-Object {$_.name -eq "AzureConnectors.EastAsia"} | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty addressPrefixes
$IPRangesSea = $ip_ranges.values | Where-Object {$_.name -eq "AzureConnectors.SouthEastAsia"} | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty addressPrefixes

########################## Sign in to Azure ##########################

# Connect-AzAccount # Or you can use service princiapl (need app id and secrets)

$SecuredPassword = ConvertTo-SecureString $Secret -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $SecuredPassword
Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential -Subscription $AzureSubscriptionId

########################## Get all existing IPs in Azure Key Vault ##########################

## Get all existing ips
if (
$existingIps = (Get-AzKeyVault -VaultName $kvname).NetworkAcls.IpAddressRanges -eq $null) 
#give a blank array if $null to prevent error
{$existingIps =@()} else 
{$existingIps = (Get-AzKeyVault -VaultName $kvname).NetworkAcls.IpAddressRanges}


########################## Remove non-IPv4 format ###########################

# Define a function to validate IPv4 address format
function Test-IPv4Address {
  param (
    [string]$IPAddress
  )
  try {
    # Use System.Net.IPAddress class to parse the input string
    $ip = [System.Net.IPAddress]::Parse($IPAddress)
    # Check if the address family is InterNetwork (IPv4)
    if ($ip.AddressFamily -eq 'InterNetwork') {
      return $true
    }
    else {
      return $false
    }
  }
  catch {
    # If the input string is not a valid IP address, return $false
    return $false
  }
}

# Define an array of IP ranges with different formats
$IPRangesCheck = $IPRangesEa + $IPRangesSea

# Loop through the array and filter out the elements that are not valid IPv4 addresses
$addedIps = @()

Write-Host "Check and remove non IPv4" -ForegroundColor Yellow

foreach ($IPRange in $IPRangesCheck) {
  # Split the IP range by '/' and get the first part as the IP address
  $IPAddress = $IPRange.Split('/')[0]
  # Use the Test-IPv4Address function to validate the IP address format
  if (Test-IPv4Address -IPAddress $IPAddress) {
    # If the IP address is valid, add it to the output array
    $addedIps += $IPRange
  }
}

$addedIps = $addedIps | Sort-Object -Unique # to make array unique



############ Compared existing azure key vault's ip ranges with the Microsoft latest IPs ##############
############# and then update IPs ##########################

if (Compare-Object  $existingIps $addedIps ) 
{ 
  Write-Host "Update IP ranges" -ForegroundColor Yellow

  #### Removes existing IPs in azure key vault  ####
  Remove-AzKeyVaultNetworkRule -VaultName $kvname -IpAddressRange $existingIps

  #### Add new IPv4 list to azure key vault  ####
  foreach ($item in $addedIps) {
   Add-AzKeyVaultNetworkRule -VaultName $kvname -IpAddressRange $item -ResourceGroupName $RG -PassThru
    }

    Write-Host "Updated complete" -ForegroundColor Green

} 
else { Write-Host "Same range of IPs, nothing to be done" -ForegroundColor Green }
