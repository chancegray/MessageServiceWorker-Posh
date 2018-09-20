<#
.SYNOPSIS
    Powershell module for maintaining Active Directory accounts in forest.usf.edu.
.DESCRIPTION
    **Quest.ActiveRoles.ADManagement Snap-In**
#>

$SCRIPT:LogName = "UsfAccountProvisioner"
$SCRIPT:LogSource = "ProvisionerScript"
$SCRIPT:Verbose = $false

function Intialize-Logging() {
	$logList = Get-EventLog -List
	
	if(-not ($logList.log -match $SCRIPT:LogName)) {
	#	New-EventLog -LogName $SCRIPT:LogName -Source $SCRIPT:LogSource
	#	Write-EventLog -LogName $SCRIPT:LogName -Source $SCRIPT:LogSource -Message "Starting new log file" -EntryType Information -EventId 0
	}
}

function Write-LogEntry {
	param(
        [Parameter(Mandatory=$true,Position=0)] [int]$EventId,
        [Parameter(Mandatory=$true,Position=1)] [System.Diagnostics.EventLogEntryType]$LogLevel,
        [Parameter(Mandatory=$true,Position=2)] [System.String]$LogMessage
	)
		
		#Write-EventLog -LogName $SCRIPT:LogName -Source $SCRIPT:LogSource -EventId $EventId -EntryType $LogLevel -Message $LogMessage
    
}

function Compare-Attributes { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$CurrentAttributes,
        [Parameter(Mandatory=$true)] [hashtable]$NewAttributes
    )
 	
	$result = @{}
	$ref = $CurrentAttributes
	$dif = $NewAttributes
   
    # Hold on to keys from the other object that are not in the reference.
    $nonrefKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    $dif.Keys | foreach { [void]$nonrefKeys.Add( $_ ) }
	
    # Test each key in the reference with that in the other object.
    foreach( $key in $ref.keys ) {
      [void]$nonrefKeys.Remove( $key )
      $refValue = $ref.$key
      $difValue = $dif.$key
	  
	  #MultiValue Attributes need to be converted to Arrays
	  if($refValue -is [System.DirectoryServices.ResultPropertyValueCollection] ){
	  	$refValue = [System.Array]$refValue
	  }
	  	  
	  if( $refValue -is [System.Array] -and $difValue -is [System.Array] ) {
			$diff = @(Compare-Object $refValue $difValue -SyncWindow 1000).length -eq 0
			if ( -not $diff){
				Write-LogEntry 1 Information "Compare-Attributes: $key is different (array)"
				#$tempArray = New-Object System.Collections.ArrayList($null)
				#$tempArray.AddRange($difValue)
				#$tempArray.Remove("")
				$result.$key = $difValue
			}
	  }
      elseif( $refValue -cne $difValue -and $dif.$key ) {
		#Replace DELETE_ATTRIBUTE with an empty String
		if ($difValue -eq "DELETE_ATTRIBUTE") {
			$difValue = ''
			$message = "Compare-Attributes: Removing value [$refValue] from $key."
		} else {
			$message = "Compare-Attributes: Modifying $key. Old Value: ["+$refValue.gettype()+"]  New Value: ["+$difValue.gettype()+"]"		
		}
		Write-LogEntry 1 Information $message
      	$result.$key = $difValue
      }
    }

    # Add all attributes not in the current entry
    $refValue = $null
	
    foreach( $key in $nonrefKeys ) {
		if (-not $ref.ContainsKey($key) -and $dif.$key -ne "DELETE_ATTRIBUTE" ) {
			$result.$key = $dif.$key
			Write-LogEntry 1 Information "Compare-Attributes: Adding new attribute: $key"
	  		
		}
    }
  return $result
}

#######################################
function Get-UserDetails {
    [CmdletBinding()]
    param(
        [Parameter(
			Position=0, 
			Mandatory=$true,
			ValueFromPipeline = $true)]
        [System.String]$UserPrincipalName
    )

	Write-Verbose "Getting AD account for $UserPrincipalName"
	$result = Get-QADUser -Identity $UserPrincipalName -DontUseDefaultIncludedProperties -IncludedProperties 'USFeduAffiliation',
				'USFeduCampus',
				'USFeduCollege',
				'USFeduDepartment',
				'USFeduGooglePassword',
				'USFeduNAMSid',
				'USFeduNetid',
				'USFeduNotifyGroup',
				'USFeduPrimaryAffiliation',
				'USFeduPrimaryCollege',
				'USFeduPrimaryDepartment',
				'USFeduPrivacy',
				'USFeduRequester',
				'USFeduUnumber',
				'accountExpires',
				'badPasswordTime',
				'badPwdCount',
				'cn',
				'company',
				'createTimeStamp',
				'department',
				'departmentNumber',
				'description',
				'displayName',
				'distinguishedName',
				'division',
				'eduPersonAffiliation',
				'eduPersonAssurance',
				'eduPersonEntitlement',
				'eduPersonNickname',
				'eduPersonOrgDN',
				'eduPersonOrgUnitDN',
				'eduPersonPrimaryAffiliation',
				'eduPersonPrimaryOrgUnitDN',
				'eduPersonPrincipalName',
				'eduPersonScopedAffiliation',
				'eduPersonTargetedID',
				'employeeID',
				'employeeNumber',
				'employeeType',
				'expirationTime',
				'extensionAttribute1',
				'extensionAttribute10',
				'extensionAttribute11',
				'extensionAttribute12',
				'extensionAttribute13',
				'extensionAttribute14',
				'extensionAttribute15',
				'extensionAttribute2',
				'extensionAttribute3',
				'extensionAttribute4',
				'extensionAttribute5',
				'extensionAttribute6',
				'extensionAttribute7',
				'extensionAttribute8',
				'extensionAttribute9',
				'facsimileTelephoneNumber',
				'generationQualifier',
				'gidNumber',
				'givenName',
				'groupPriority',
				'groupsToIgnore',
				'homeDirectory',
				'homeDrive',
				'homeMDB',
				'homeMTA',
				'homePhone',
				'homePostalAddress',
				'initials',
				'ipPhone',
				'jpegPhoto',
				'l',
				'labeledURI',
				'language',
				'languageCode',
				'lastKnownParent',
				'lastLogoff',
				'lastLogon',
				'lastLogonTimestamp',
				'legacyExchangeDN',
				'lockoutTime',
				'loginShell',
				'logonCount',
				'logonHours',
				'logonWorkstation',
				'mail',
				'mailNickname',
				'manager',
				'memberOf',
				'middleName',
				'mobile',
				'modifyTimeStamp',
				'name',
				'objectCategory',
				'objectClass',
				'objectGUID',
				'objectSid',
				'pager',
				'personalTitle',
				'photo',
				'physicalDeliveryOfficeName',
				'postOfficeBox',
				'postalAddress',
				'postalCode',
				'primaryGroupID',
				'proxyAddresses',
				'pwdLastSet',
				'roomNumber',
				'sAMAccountName',
				'sAMAccountType',
				'sIDHistory',
				'seeAlso',
				'showInAddressBook',
				'sn',
				'st',
				'street',
				'streetAddress',
				'targetAddress',
				'telephoneNumber',
				'title',
				'uid',
				'uidNumber',
				'unixHomeDirectory',
				'url',
				'userAccountControl',
				'userCert',
				'userCertificate',
				'userPKCS12',
				'userParameters',
				'userPrincipalName',
				'userSMIMECertificate',
				'wWWHomePage',
				'whenChanged',
				'whenCreated'
			
	return $result
}

function Get-UserExists {
    param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName,
		[Parameter(Mandatory=$true)] [System.String]$SearchRoot
    )

	$count = Get-QADUser -DontUseDefaultIncludedProperties -Identity $UserPrincipalName -SearchRoot $SearchRoot | Measure-Object | Select-Object -expand count
	
	if ($count -gt 0){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the Windows Azure server #>
function Get-MsolUserExists {
    param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )

	$count = Get-MsolUser -UserPrincipalName $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
	
	if ($count -gt 0){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the Windows Azure server #>
function Get-MsolUserLicenses {
    param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )

	$LicenseList = @()

	$RawList = (Get-MsolUser -UserPrincipalName $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Select-Object Licenses).Licenses
	
		foreach ($license in $RawList) {
			$LicenseList = $LicenseList + $license.AccountSkuId
		}
	
	return $LicenseList
}

<#Requires a PowerShell session with the Windows Azure server #>
function Set-MsolUserLicenses {
    param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )

    $err=@()

	#Usage location must be 'US'
	Set-MsolUser -UserPrincipalName $UserPrincipalName -UsageLocation US -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable +err -WarningVariable +err

    #Remove the student license if it is already there
    $GetStu = Get-MsolUser -UserPrincipalName $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Where-Object {$_.IsLicensed -eq $true}
    if ($GetStu.licenses.accountskuid -eq "usfedu:STANDARDWOFFPACK_IW_STUDENT") { 
		Set-MsolUserLicense -UserPrincipalName $UserPrincipalName -RemoveLicenses "usfedu:STANDARDWOFFPACK_IW_STUDENT" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable +err -WarningVariable +err
	}

    ### Set O365 licensing
    $STANDARDWOFFPACK_IW_FACULTY = New-MsolLicenseOptions -AccountSkuId usfedu:STANDARDWOFFPACK_IW_FACULTY -DisabledPlans SHAREPOINTSTANDARD_EDU
    $PROJECTONLINE_PLAN_1_FACULTY = New-MsolLicenseOptions -AccountSkuId usfedu:PROJECTONLINE_PLAN_1_FACULTY -DisabledPlans SHAREPOINTWAC_EDU

    Set-MsolUserLicense -UserPrincipalName $UserPrincipalName -LicenseOptions $PROJECTONLINE_PLAN_1_FACULTY -AddLicenses usfedu:PROJECTONLINE_PLAN_1_FACULTY -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable +err -WarningVariable +err | Out-Null
    Set-MsolUserLicense -UserPrincipalName $UserPrincipalName -LicenseOptions $STANDARDWOFFPACK_IW_FACULTY -AddLicenses usfedu:STANDARDWOFFPACK_IW_FACULTY -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable +err -WarningVariable +err | Out-Null

    return $err
}

<#Requires a PowerShell session with the Windows Azure server #>
function Get-MsolUserIsLicensed {
    param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )

	$IsLicensed = (Get-MsolUser -UserPrincipalName $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue).IsLicensed

	if ($IsLicensed -eq $true){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Get-OnPremMailboxExists {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )
	
	# Switch to this when/if we upgrade to Exchange 2013
	#$count = Get-OnPremMailbox -Identity $EmailAddress -IncludeInactiveMailbox -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
	$count = Get-OnPremMailbox -Identity $EmailAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
	
	if ($count -gt 0){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the Office365 Exchange server with '-Prefix Azure' #>
function Get-AzureMailboxExists {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )

	$count = Get-AzureMailbox -Identity $EmailAddress -IncludeInactiveMailbox -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
	
	if ($count -gt 0){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Disable-OnPremMailboxAccess {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )
	
	return Disable-OnPremMailbox $EmailAddress
}

<#Requires a PowerShell session with the Office365 Exchange server with '-Prefix Azure' #>
function Disable-AzureMailboxAccess {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )

	#Disable access according to http://help.outlook.com/en-us/140/ee423638.aspx
	return Set-AzureCASMailbox $EmailAddress -OWAEnabled $false -PopEnabled $false -ImapEnabled $false -MAPIEnabled $false -ActiveSyncEnabled $false -EwsEnabled $false 
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Enable-OnPremMailboxAccess {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )
	
	return Enable-OnPremMailbox $EmailAddress
}

<#Requires a PowerShell session with the Office365 Exchange server with '-Prefix Azure' #>
function Enable-AzureMailboxAccess {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )

	#Enable access according to http://help.outlook.com/en-us/140/ee423638.aspx
	return Set-AzureCASMailbox $EmailAddress -OWAEnabled $true -PopEnabled $true -ImapEnabled $true -MAPIEnabled $true -ActiveSyncEnabled $true -EwsEnabled $true 
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Get-OnPremGalAddressExists {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )

	$count = Get-OnPremMailUser -Identity $EmailAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
	
	if ($count -gt 0){
		return $true
	} else {
		$count = Get-OnPremContact -Identity $EmailAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand count
		if ($count -gt 0){
			return $true
		} else {
			return $false
		}
	}
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Get-OnPremGalAddressHidden {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress
    )

	$AccountHidden = (Get-OnPremMailUser -Identity $EmailAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue).HiddenFromAddressListsEnabled 
	
	if ($AccountHidden -eq $true){
		return $true
	} else {
		return $false
	}
}

<#Requires a PowerShell session with the On-Prem Exchange server with '-Prefix OnPrem'#>
function Set-OnPremGalAddressHidden {
    param(
        [Parameter(Mandatory=$true)] [System.String]$EmailAddress,
		[Parameter(Mandatory=$true)] [Bool]$Value
    )

	Get-OnPremMailUser -Identity $EmailAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Set-OnPremMailUser -HiddenFromAddressListsEnabled $Value -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

}

function New-Account {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$Username,
		[Parameter(Mandatory=$true)] [System.String]$ParentContainer,
		[Parameter(Mandatory=$true)] [System.String]$GivenName,
		[Parameter(Mandatory=$true)] [System.String]$FamilyName,
		[Parameter(Mandatory=$false)] [System.String]$Password,
		[Parameter(Mandatory=$false)] [System.String]$Domain = 'usf.edu'
    )
	$CommonName = $FamilyName + ', ' + $GivenName + ' [' + $Username + ']'
	$DisplayName = $FamilyName + ', ' + $GivenName
	$UserPrincipalName = $Username + '@' + $Domain
	
	if( -not($Password)){
		Write-LogEntry 1 Information "New-Account: Generating Random Password for $UserPrincipalName"
		$Password = [System.Web.Security.Membership]::GeneratePassword(32,3)
	}

	Write-LogEntry 1 Information "New-Account: Creating account $Username in $ParentContainer"
	$user = New-QADUser -Name $CommonName -ParentContainer $ParentContainer -SamAccountName $Username -UserPrincipalName $UserPrincipalName -FirstName $GivenName -LastName $FamilyName -DisplayName $DisplayName -UserPassword $Password
	return $user
}

function Get-AttributesToModify {
	[CmdletBinding()]
	param(
        [Parameter( 
			Mandatory=$true)]
        [System.String]$UserPrincipalName,
		[Parameter( 
			Mandatory=$true)]
        [hashtable]$Attributes
    )	
	
	$strFilter = "(&(objectCategory=User)(UserPrincipalName=$UserPrincipalName))"

	$objDomain = New-Object System.DirectoryServices.DirectoryEntry
	$objSearcher = New-Object System.DirectoryServices.DirectorySearcher
	$objSearcher.SearchRoot = $objDomain
	$objSearcher.PageSize = 1000
	$objSearcher.Filter = $strFilter
	$objSearcher.SearchScope = "Subtree"
	
	$colResults = $objSearcher.FindAll() 
	
	#Loop through the search results and convert to a hashtable
	$CurrentAttributes = @{}
	foreach ($result in $colResults) {    
		$propertiesCollection = $result.Properties.GetEnumerator() | Sort-Object Name
	
		foreach ($entry in $propertiesCollection) {
			$CurrentAttributes[$entry.Key] = $entry.Value
		}
	}

	$AttributesToModify = Compare-Attributes -CurrentAttributes $CurrentAttributes -NewAttributes $Attributes

    # Make sure the attributes needed for CN changes are available
    if($AttributesToModify.SamAccountName -or $AttributesToModify.givenName -or $AttributesToModify.sn -or $AttributesToModify.cn){
        $AttributesToModify.SamAccountName = $Attributes.SamAccountName
        $AttributesToModify.givenName = $Attributes.givenName
        $AttributesToModify.sn = $Attributes.sn
        $AttributesToModify.displayName = $Attributes.sn + ', ' + $Attributes.givenName
     }
	
	return $AttributesToModify	
}

function Set-Account {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName,
		[Parameter(Mandatory=$true)] [hashtable]$Attributes
    )	
	
	$GUID = (Get-QADUser -Identity $UserPrincipalName).guid
	
	#Update CommonName
	if($Attributes.SamAccountName -or $Attributes.givenName -or $Attributes.sn -or $Attributes.cn){
		if ($Attributes.cn){
			$NewCommonName = $Attributes.cn
			$Attributes.Remove("cn")
		} else {
			$NewCommonName = $Attributes.sn + ', ' + $Attributes.givenName + ' [' + $Attributes.SamAccountName + ']'
		}
		Write-LogEntry 1 Information "Set-Account: Updating CommonName on $UserPrincipalName to $NewCommonName"
		Rename-QADObject -Identity $GUID -NewName $NewCommonName
	}
	
	if($Attributes.UserPrincipalName){
		$UserPrincipalName = $Attributes.UserPrincipalName
	}
	
	$num = $Attributes.Keys | Measure-Object | Select-Object -expand count
	Write-LogEntry 1 Information "Set-Account: Updating $num attributes on $UserPrincipalName"
	Set-QADUser -Identity $GUID -ObjectAttributes $Attributes | Out-Null
	
	return $UserPrincipalName
}

function Move-Account {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName,
		[Parameter(Mandatory=$true)] [System.String]$Container
    )
	Write-LogEntry 1 Information "Move-Account: Moving $UserPrincipalName to new container $Container"
	Move-QADObject -Identity $UserPrincipalName -NewParentContainer $Container
}

function Get-CurrentCimsGroupList {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )
	
	$GroupDNlist = Get-QADUser -Identity $UserPrincipalName | Select-Object "memberOf"
	$array = [regex]::matches($GroupDNlist.MemberOf, "CN=(CIMS.*?),.*?") | % {$_.Result('$1')}
	return [System.Array] $array
}

function Set-CimsGroups {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName,
		[Parameter(Mandatory=$true)] $NewCimsGroups
    )
	
	$CurrentCimsGroupList = Get-CurrentCimsGroupList -UserPrincipalName $UserPrincipalName
	
	if (! $CurrentCimsGroupList.count -gt 0){ $CurrentCimsGroupList = @()}
	if (! $NewCimsGroups -gt 0){ $NewCimsGroups = @()}
	
	$AddList = (Compare-Object $NewCimsGroups $CurrentCimsGroupList | Where {$_.SideIndicator -eq '<='} | Select-Object InputObject).InputObject
	$RemoveList = (Compare-Object $NewCimsGroups $CurrentCimsGroupList | Where {$_.SideIndicator -eq '=>'} | Select-Object InputObject).InputObject

	foreach ($group in $AddList) {
		Add-QADGroupMember -Identity $group -Member $UserPrincipalName | Out-Null
	}
	foreach ($group in $RemoveList) {
		Remove-QADGroupMember -Identity $group -Member $UserPrincipalName | Out-Null
	}
	
	return "Group Results: [Added: $AddList] [Removed: $RemoveList]"
}


function Confirm-NonActiveMember {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )
	
	$list = (Get-QADUser -Identity $UserPrincipalName).memberOf 
	$list -contains "CN=Non-Active Users,CN=Users,DC=forest,DC=usf,DC=edu"
}

function Add-NonActiveMember {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )
	
	Add-QADMemberOf -Identity $UserPrincipalName -Group "CN=Non-Active Users,CN=Users,DC=forest,DC=usf,DC=edu"
}

function Remove-NonActiveMember {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName
    )
	
	Remove-QADMemberOf -Identity $UserPrincipalName -Group "CN=Non-Active Users,CN=Users,DC=forest,DC=usf,DC=edu"
}

Export-ModuleMember -Function Get-UserDetails
Export-ModuleMember -Function Get-UserExists
Export-ModuleMember -Function New-Account
Export-ModuleMember -Function Set-Account
Export-ModuleMember -Function Move-Account
Export-ModuleMember -Function Get-CurrentCimsGroupList
Export-ModuleMember -Function Set-CimsGroups
Export-ModuleMember -Function Confirm-NonActiveMember
Export-ModuleMember -Function Add-NonActiveMember
Export-ModuleMember -Function Remove-NonActiveMember
Export-ModuleMember -Function Get-AttributesToModify
Export-ModuleMember -Function Write-LogEntry
Export-ModuleMember -Function Get-AzureMailboxExists
Export-ModuleMember -Function Get-OnPremMailboxExists
Export-ModuleMember -Function Disable-OnPremMailboxAccess
Export-ModuleMember -Function Disable-AzureMailboxAccess
Export-ModuleMember -Function Enable-OnPremMailboxAccess
Export-ModuleMember -Function Enable-AzureMailboxAccess
Export-ModuleMember -Function Get-OnPremGalAddressExists
Export-ModuleMember -Function Get-OnPremGalAddressHidden
Export-ModuleMember -Function Set-OnPremGalAddressHidden
Export-ModuleMember -Function Get-MsolUserExists
Export-ModuleMember -Function Get-MsolUserLicenses
Export-ModuleMember -Function Set-MsolUserLicenses
Export-ModuleMember -Function Get-MsolUserIsLicensed


#Get the Logfile ready
#Intialize-Logging