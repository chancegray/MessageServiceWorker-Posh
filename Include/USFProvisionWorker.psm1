<#
.SYNOPSIS
    A brief description of the module.
.DESCRIPTION
    A detailed description of the module.
#>

function ConvertTo-AttributeHash {
    param(
        [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)] $AttributesFromJSON
    )
	
	$AttributeHash = @{  	
		#'middlename' = 'DELETE_ATTRIBUTE';
		#'Title' = 'DELETE_ATTRIBUTE';
		#'physicalDeliveryOfficeName' = 'DELETE_ATTRIBUTE';
		#'givenName' = 'DELETE_ATTRIBUTE';
		#'sn' = 'DELETE_ATTRIBUTE';
		#'displayName' = 'DELETE_ATTRIBUTE';
		#'l' = 'DELETE_ATTRIBUTE';
		#'st' = 'DELETE_ATTRIBUTE';
		#'postalCode' = 'DELETE_ATTRIBUTE';
		#'streetAddress' = 'DELETE_ATTRIBUTE';
		#'telephoneNumber' = 'DELETE_ATTRIBUTE';
		#'Company' = 'DELETE_ATTRIBUTE';
		#'Department' = 'DELETE_ATTRIBUTE'; 
		#'Description' = 'DELETE_ATTRIBUTE';
		'gidNumber' = 'DELETE_ATTRIBUTE';	
		'loginShell' = 'DELETE_ATTRIBUTE';
		'uidNumber' = 'DELETE_ATTRIBUTE';
		'unixHomeDirectory' = 'DELETE_ATTRIBUTE';
		'EmployeeID' = 'DELETE_ATTRIBUTE';
		'eduPersonEntitlement' = 'DELETE_ATTRIBUTE';
		'eduPersonPrimaryAffiliation' = 'DELETE_ATTRIBUTE';
		'eduPersonAffiliation' = 'DELETE_ATTRIBUTE';
		'eduPersonNickName' = 'DELETE_ATTRIBUTE';
		'eduPersonOrgDN' = 'DELETE_ATTRIBUTE';
		'eduPersonOrgUnitDN' = 'DELETE_ATTRIBUTE';
		'eduPersonPrincipalName' = 'DELETE_ATTRIBUTE';
		'eduPersonPrimaryOrgUnitDN' = 'DELETE_ATTRIBUTE';
		'eduPersonScopedAffiliation' = 'DELETE_ATTRIBUTE';
		'eduPersonTargetedID' = 'DELETE_ATTRIBUTE';
		'eduPersonAssurance' = 'DELETE_ATTRIBUTE';
		'USFeduAffiliation' = 'DELETE_ATTRIBUTE';
		'USFeduCampus' = 'DELETE_ATTRIBUTE';
		'USFeduCollege' = 'DELETE_ATTRIBUTE';
		'USFeduDepartment' = 'DELETE_ATTRIBUTE';
		'USFeduNAMSid' = 'DELETE_ATTRIBUTE';
		'USFeduPrivacy' = 'DELETE_ATTRIBUTE';
		'USFeduRequester' = 'DELETE_ATTRIBUTE';
		'USFeduNotifyGroup' = 'DELETE_ATTRIBUTE';
		'USFeduUnumber' = 'DELETE_ATTRIBUTE';
		'USFeduNetID' = 'DELETE_ATTRIBUTE';
		'USFeduPrimaryAffiliation' = 'DELETE_ATTRIBUTE';
		'USFeduPrimaryCollege' = 'DELETE_ATTRIBUTE';
		'USFeduPrimaryDepartment' = 'DELETE_ATTRIBUTE';
		'extensionAttribute1' = 'DELETE_ATTRIBUTE';
		'extensionAttribute11' = 'DELETE_ATTRIBUTE';
		'USFeduPrimaryEmail' = 'DELETE_ATTRIBUTE';
		'USFeduOfficialGivenname' = 'DELETE_ATTRIBUTE';
		'USFeduOfficialMiddlename' = 'DELETE_ATTRIBUTE';
		'USFeduOfficialSurname' = 'DELETE_ATTRIBUTE';
	}
	
	$NewAttributes = @{}
	foreach( $key in $AttributeHash.keys ) {
		if ($AttributesFromJSON.$key) {
			if($AttributesFromJSON.$key -is [System.Array] -and $AttributesFromJSON.$key.length -eq 1){
				$NewAttributes.$key = $AttributesFromJSON.$key[0]
			}else{
				$NewAttributes.$key = $AttributesFromJSON.$key
			}
		} else {
			$NewAttributes.$key = $AttributeHash.$key
		}
	}
	
	#Fix specific attributes that differ between LDAP and AD
	if($AttributesFromJSON.USFeduPrimaryAffiliation -eq 'N/A'){
		$NewAttributes.USFeduPrimaryAffiliation = 'DELETE_ATTRIBUTE';
	}
	
	$NewAttributes.extensionAttribute1 = $AttributesFromJSON.namsid[0]
	$NewAttributes.USFeduNAMSid = $AttributesFromJSON.namsid[0]
	
	if($AttributesFromJSON.USFeduEmplid){
		$NewAttributes.extensionAttribute11 = $AttributesFromJSON.USFeduEmplid[0]
		$NewAttributes.EmployeeID = $AttributesFromJSON.USFeduEmplid[0]
	}
	
	if($AttributesFromJSON.uid) {
		$NewAttributes.SamAccountName = $AttributesFromJSON.uid[0]
		if($AttributesFromJSON.uid.length -eq 1){
			$NewAttributes.USFeduNetID = $AttributesFromJSON.uid[0]
		}else{
			$NewAttributes.USFeduNetID = $AttributesFromJSON.uid
		}
	}
	
	if($AttributesFromJSON.homeDirectory) {
		$NewAttributes.unixHomeDirectory = $AttributesFromJSON.homeDirectory
	}
	
	if($AttributesFromJSON.sn -and $AttributesFromJSON.givenName -and $AttributesFromJSON.uid){
		$NewAttributes.cn = $AttributesFromJSON.sn[0] + ', ' + $AttributesFromJSON.givenName[0] + ' [' + $AttributesFromJSON.uid[0] + ']'
	}
	
	return $NewAttributes
}

function Resolve-DefaultContainer {
    param(
        [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)] $AttributesFromJSON,
		[Parameter(Position=1, Mandatory=$true)] $BaseDN
    )
	
	$PrimaryAffiliation = $AttributesFromJSON.eduPersonPrimaryAffiliation
	$UsfPrimaryAffiliation = $AttributesFromJSON.USFeduPrimaryAffiliation
	
	if ($PrimaryAffiliation){
		#Check based on ePPA
		switch -regex ($PrimaryAffiliation) {
			"Student" {
				$ParentContainer = $("OU=Accounts,OU=Students,"+$BaseDN)
				break
			}
			"(Faculty|Staff)" {		
				#USF Health accounts go in their own OU
				if($AttributesFromJSON.USFeduCollege -and $AttributesFromJSON.USFeduCollege[0] -match "(Medicine|Public Health|Nursing|Pharmacy)"){
					$ParentContainer = $("OU=USF Health,"+$BaseDN)
				#So do USFSP
				} elseif ($AttributesFromJSON.USFeduCampus -and $AttributesFromJSON.USFeduCampus[0] -eq "StPete") {
					$ParentContainer = $("OU=USF St Pete,"+$BaseDN)
				#Everyone else goes in NewAccounts
				} else {
					$ParentContainer = $("OU=NewAccounts,"+$BaseDN)
				}
				break
			}
			"Affiliate" {
				$ParentContainer = $("OU=VIP,OU=NewAccounts,"+$BaseDN)
				break
			}
			default {
				$ParentContainer = $("OU=No Affiliation,"+$BaseDN)
				break
			}
		}
	} else {
		#Some VIP groups don't give an ePPA, so we have to go by USFPA
		if ($UsfPrimaryAffiliation -eq "VIP"){
			$ParentContainer = $("OU=VIP,OU=NewAccounts,"+$BaseDN)
		} else {
			$ParentContainer = $("OU=No Affiliation,"+$BaseDN)
		}
	}
	
	#Override the default if we're passed a special value
	if ($AttributesFromJSON.ParentContainer){
		$ParentContainer = $AttributesFromJSON.ParentContainer
	}
	
	return $ParentContainer
}

function Confirm-ManagedContainer {
	param(
        [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)] $Container
    )
	
		#List of managed OUs
		$ManagedContainers = @(
			$("OU=No Affiliation,"+$BaseDN),
			$("OU=NewAccounts,"+$BaseDN),
			$("OU=VIP,OU=NewAccounts,"+$BaseDN),
			$("OU=NewAccounts,"+$BaseDN),
			$("OU=USF StPete,"+$BaseDN),
			$("OU=USF Health,"+$BaseDN),
			$("OU=Accounts,OU=Students,"+$BaseDN),
			$("OU=Disabled,OU=Students,"+$BaseDN)
		)

		return $ManagedContainers -contains $Container
}

Export-ModuleMember -Function Confirm-ManagedContainer
Export-ModuleMember -Function ConvertTo-AttributeHash
Export-ModuleMember -Function Resolve-DefaultContainer
