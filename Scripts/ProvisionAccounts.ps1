$ScriptPath = "C:\Users\epierce.FOREST\Documents\GitHub\MessageServiceWorker-Posh"

Import-Module $ScriptPath\Include\MessageServiceClient.psm1 -Force
Import-Module $ScriptPath\Include\Import-INI.psm1 -Force
Import-Module $ScriptPath\Include\AccountProvisioner.psm1 -Force
Import-Module $ScriptPath\Include\USFProvisionWorker.psm1 -Force

$config = Import-INI "C:\Users\epierce.FOREST\Documents\GitHub\MessageServiceWorker-Posh\Config\ProvisionAccounts.ini"

#Set up the credentials we're going to use
$Password = Get-Content $config["MessageService"]["CredentialFile"] | ConvertTo-SecureString 
$MessageServiceCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["MessageService"]["User"],$Password
$WindowsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["ActiveDirectory"]["User"],$Password


$QueueName = $config["MessageService"]["QueueName"]
$MaxMessages =  $config["MessageService"]["MaxMessages"]
$MaxThreads =  $config["MessageService"]["MaxThreads"]
$SleepTimer =  $config["MessageService"]["SleepTimer"]

$UpnDomain = $config["ActiveDirectory"]["UpnDomain"]
$Domain = $config["ActiveDirectory"]["Domain"]
$BaseDN = $config["ActiveDirectory"]["BaseDN"]

if ($config["ActiveDirectory"]["Verbose"] -eq "true"){
	$Verbose = $true
} else {
	$Verbose = $false
}


$Connection = Connect-QADService -service $Domain -Credential $WindowsCredential


if ($Verbose){
	Write-Host "Retreiving" $MaxMessages "messages"
}

for($counter = 1; $counter -le $MaxMessages; $counter++){

	#Grab a message from the queue
	$Message = Get-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Verbose $Verbose
	
	if ($Message) {
		#Message contains one or more NetIDs
		if($Message.messageData.attributes.uid -is [System.Array]){
			$AccountExists = $false
			if ($Verbose){
				Write-Host "This user has" $Message.messageData.attributes.uid.length "uid entries"
			}
			if($Message.messageData.attributes.uid.length -gt 1){
				#Multiple NetIDs - Check the primary one first
				$Username = $Message.messageData.attributes.uid[0]
				$UserPrincipalName = $($Username+"@"+$UpnDomain)
				if (Get-UserExists -UserPrincipalName $UserPrincipalName -SearchRoot $BaseDN){
					if ($Verbose){ Write-Host "Account" $UserPrincipalName "found" }
					$AccountExists = $true
					$ChangeType = "update"
				} else {
					#Multiple NetIDs - loop through the list to see if another netid account exists
					foreach ($uid in $Message.messageData.attributes.uid) {
						#ignore *-student, *-faculty, *-staff netids
						if($uid -match ".*(-student|-staff|-faculty)"){
							continue
						}
						$Username = $uid
						$UserPrincipalName = $($Username+"@"+$UpnDomain)
						if (Get-UserExists -UserPrincipalName $UserPrincipalName -SearchRoot $BaseDN){
							if ($Verbose){ Write-Host "Account" $UserPrincipalName "found" }
							$AccountExists = $true
							$ChangeType = "rename"
							break
						}
					}
					#We got all the way through the NetID list and none of the accounts exist - create an account for the first one
					if($AccountExists -eq $false){
						$ChangeType = "create"
						$Username = $Message.messageData.attributes.uid[0]
						$UserPrincipalName = $($Username+"@"+$UpnDomain)
						if ($Verbose){ Write-Host "Creating account for $UserPrincipalName" }
					}
				}
			} else {
				#Single NetID
				$Username = $Message.messageData.attributes.uid[0]
				$UserPrincipalName = $($Username+"@"+$UpnDomain)
				if (Get-UserExists -UserPrincipalName $UserPrincipalName -SearchRoot $BaseDN){
					if ($Verbose){ Write-Host "Account $UserPrincipalName found" }
					$AccountExists = $true
					$ChangeType = "update"
				} else {
					if ($Verbose){ Write-Host "Creating account for $UserPrincipalName" }
					$AccountExists = $false
					$ChangeType = "create"
				}
			}
			
			"--"
			$UserPrincipalName		
			
			#Create an account if needed
			if($ChangeType -eq "create"){
				#create			
				$ParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
				if ($Verbose) { "Creating account in $ParentContainer" }
				$GivenName = $Message.messageData.attributes.givenName[0]
				$FamilyName = $Message.messageData.attributes.sn[0]
				"New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain"
				New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
			}

			#Get a HashMap of attributes
			$NewAttributes = ConvertTo-AttributeHash -AttributesFromJSON $Message.messageData.attributes
			
			$AttrList = Get-AttributesToModify -UserPrincipalName $UserPrincipalName -Attributes $NewAttributes
			if ($Verbose){ $AttrList | Format-List } 
			
			#Update Account
			if ($Verbose) { Write-Host "Updating $UserPrincipalName" }
			try {
			
				#Is this account in a managed OU?
				$CurrentParentContainer = (Get-QADUser -UserPrincipalName $UserPrincipalName).ParentContainerDN.ToString()
				$InManagedContainer = Confirm-ManagedContainer -Container $CurrentParentContainer

				$CurrentParentContainer
				if($InManagedContainer){
					#Get correct account location
					$DefaultParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
					
					if( $DefaultParentContainer -ne $CurrentParentContainer ) {
						$UserPrincipalName+" is in "+$CurrentParentContainer+".  It should be in "+$DefaultParentContainer | Write-Host
						Move-Account -UserPrincipalName $UserPrincipalName -Container $DefaultParentContainer | Out-Null
					}
				}
				
				Set-Account -UserPrincipalName $UserPrincipalName -Attributes $AttrList | Out-Null
				Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
			} catch [system.exception] {
				if ($Verbose) { Write-Host $Error[0].Exception }
				Write-LogEntry 1 Error "ProvisionWorker: $Error[0].Exception"
			}
			
			Remove-Variable ChangeType
		} else {
			#"No NetID - Skipping"
			if ($Verbose){ Write-Host "No NetID - Skipping" }
			Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
		}
		Remove-Variable Message
	} else {
		#We didn't get a message back - end this thread
		break
	}
}