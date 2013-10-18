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
	
	return $AttributesToModify	
}

function Set-Account {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory=$true)] [System.String]$UserPrincipalName,
		[Parameter(Mandatory=$true)] [hashtable]$Attributes
    )	
	
	#Update CommonName
	if($Attributes.SamAccountName -or $Attributes.givenName -or $Attributes.sn -or $Attributes.cn){
		if ($Attributes.cn){
			$NewCommonName = $Attributes.cn
			$Attributes.Remove("cn")
		} else {
			$NewCommonName = $Attributes.sn + ', ' + $Attributes.givenName + ' [' + $Attributes.SamAccountName + ']'
		}
		Write-LogEntry 1 Information "Set-Account: Updating CommonName on $UserPrincipalName to $NewCommonName"
		Rename-QADObject -Identity $UserPrincipalName -NewName $NewCommonName
	}
	$num = $Attributes.Keys | Measure-Object | Select-Object -expand count
	Write-LogEntry 1 Information "Set-Account: Updating $num attributes on $UserPrincipalName"
	Set-QADUser -Identity $UserPrincipalName -ObjectAttributes $Attributes | Out-Null
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
	return $array
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
Export-ModuleMember -Function Confirm-NonActiveMember
Export-ModuleMember -Function Add-NonActiveMember
Export-ModuleMember -Function Remove-NonActiveMember
Export-ModuleMember -Function Get-AttributesToModify
Export-ModuleMember -Function Write-LogEntry


#Get the Logfile ready
Intialize-Logging