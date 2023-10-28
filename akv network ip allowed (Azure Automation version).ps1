## using PowerShell Module 
## Install-Module -Name Az.KeyVault -RequiredVersion 4.10.0
### need to add this managed identity as "Key Vault Contributor" role at Azure Key Vault level ### 
### this cod will update IPs in Dataverse environment in Asia (AzureConnectors.EastAsia, AzureConnectors.SouthEastAsia) 
### for other please see https://learn.microsoft.com/en-us/connectors/common/outbound-ip-addresses#power-platform
### and then modified or add variables at line 42 and 43 and sum up in line 84

$kvname = Get-AutomationVariable -Name 'kvname'
$RG = Get-AutomationVariable -Name 'resourceGroup'
$url = Get-AutomationVariable -Name 'MicrosoftIpURL'

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
$url = $url + $last_week + ".json"

########################## Download the service tags for Azure services ##########################

# Check if Microsoft release any new IPs? - If not then we got error: (404) Not Found
try {
    $ip_ranges = Invoke-RestMethod $url -Method "GET"
    Write-Output "Microsoft releases new IPs" 
    Write-Output "Getting IPs for 2 services tags: AzureConnectors.EastAsia and AzureConnectors.SouthEastAsia" 
}
catch {
   Write-Output "Got Error: $($_.Exception.Message)" 
    Write-Output "Microsoft doesn't releases new IPs yet" 
    exit
}

### For this case, I've do dataverse environment in Asia so I've got 2 variables below
### For other's region, please see https://learn.microsoft.com/en-us/connectors/common/outbound-ip-addresses#power-platform
$IPRangesEa = $ip_ranges.values | Where-Object {$_.name -eq "AzureConnectors.EastAsia"} | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty addressPrefixes
$IPRangesSea = $ip_ranges.values | Where-Object {$_.name -eq "AzureConnectors.SouthEastAsia"} | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty addressPrefixes

########################## Sign in to Azure ##########################

Connect-AzAccount -Identity # Or you can use service princiapl (need app id and secrets)

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

Write-Output "Check and remove non IPv4" 

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
  Write-Output "Update IP ranges" 

  #### Removes existing IPs in azure key vault  ####
  Remove-AzKeyVaultNetworkRule -VaultName $kvname -IpAddressRange $existingIps

  #### Add new IPv4 list to azure key vault  ####
  foreach ($item in $addedIps) {
   Add-AzKeyVaultNetworkRule -VaultName $kvname -IpAddressRange $item -ResourceGroupName $RG -PassThru
    }

    Write-Output "Updated complete" 

} 
else { Write-Output "Same range of IPs, nothing to be done"  }
