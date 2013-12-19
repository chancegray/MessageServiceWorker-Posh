[String]$StartupString = $input
$StartupObject = $StartupString.split("|")

[String]$Action = $StartupObject[0]
[String]$ScriptPath = $StartupObject[1]
[String]$LogFile = $StartupObject[2]

#$LogFile = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Logs\test.log"
#$Action="provision"
#$ScriptPath="C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

#Import-Module MSOnline -Force
Import-Module $ScriptPath\Include\MessageServiceClient.psm1 -Force
Import-Module $ScriptPath\Include\Import-INI.psm1 -Force
Import-Module $ScriptPath\Include\AccountProvisioner.psm1 -Force
Import-Module $ScriptPath\Include\USFProvisionWorker.psm1 -Force

$config = Import-INI $ScriptPath\Config\ProvisionAccounts.ini

#Set up the credentials we're going to use
$MessageServicePassword = Get-Content $config["MessageService"]["CredentialFile"] | ConvertTo-SecureString
$WindowsPassword = Get-Content $config["ActiveDirectory"]["CredentialFile"] | ConvertTo-SecureString
$AzurePassword = Get-Content $config["Azure"]["CredentialFile"] | ConvertTo-SecureString
$MessageServiceCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["MessageService"]["User"],$MessageServicePassword
$WindowsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["ActiveDirectory"]["User"],$WindowsPassword
$AzureCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["Azure"]["User"],$AzurePassword
$UpnDomain = $config["ActiveDirectory"]["UpnDomain"]
$Domain = $config["ActiveDirectory"]["Domain"]
$BaseDN = $config["ActiveDirectory"]["BaseDN"]

#Connect to On-Premise Exchange
#$ProgressPreference = "SilentlyContinue";
#$ExchSess = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $config["ActiveDirectory"]["ExchangePowerShellURI"] -Authentication Kerberos -Credential $WindowsCredential
#Import-PSSession $ExchSess -AllowClobber -WarningAction silentlyContinue | Out-Null

#Connect to Active Directory
$Connection = Connect-QADService -service $Domain -Credential $WindowsCredential

$QueueName = $config["MessageService"]["UpdateQueueName"]
$ProvisionQueueName = $config["MessageService"]["ProvisionQueueName"]

if($Action -eq "provision"){
	$QueueName = $ProvisionQueueName
}

$MaxMessages = $config["MessageService"]["MaxMessages"]
$MaxThreads = $config["MessageService"]["MaxThreads"]
$SleepTimer = $config["MessageService"]["SleepTimer"]

if ($config["ActiveDirectory"]["Verbose"] -eq "true"){
	$Verbose = $true
} else {
	$Verbose = $false
}

if ($Verbose){
	Write-Host "Retreiving" $MaxMessages "messages" | Out-File $LogFile -Append -Force
}

$TotalMessages = 0
$Created = 0
$Moved = 0
$Enabled = 0

for($counter = 1; $counter -le $MaxMessages; $counter++){

	#Set defaults
	$SkipProcessing = $false
	$AccountExists = $false

	#Grab a message from the queue
	$Message = Get-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Verbose $Verbose
	
	if ($Message) {
		
		$TotalMessages++
		
		#Message contains one or more NetIDs
		if($Message.messageData.attributes.uid -is [System.Array]){
			
			$ParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
			$GivenName = $Message.messageData.attributes.givenName[0]
			$FamilyName = $Message.messageData.attributes.sn[0]
			
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
							"Looking for $Message.messageData.attributes.uid[0], found previous Netid: $Username" | Out-File $LogFile -Append -Force
							break
						}
					}
					#We got all the way through the NetID list and none of the accounts exist - create an account for the first one
					if($AccountExists -ne $true){					
						if($Action -ne "provision"){
							#move the message to a different queue
							Publish-QueueMessage -Credentials $MessageServiceCredential -Program "edu:usf:cims:PowerShell:ProvisionAccounts" -Queue $ProvisionQueueName -Data $Message.messageData
							Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
							$SkipProcessing = $true
							(Get-Date -Format s)+"|Sending message to provisioning queue" | Out-File $LogFile -Append -Force
						} else {
							$ChangeType = "create"
							$Username = $Message.messageData.attributes.uid[0]
							$UserPrincipalName = $($Username+"@"+$UpnDomain)
							if ($Verbose){ Write-Host "Creating account for $UserPrincipalName" }
							(Get-Date -Format s)+"|Creating account for "+$UserPrincipalName+" in "+$ParentContainer | Out-File $LogFile -Append -Force
							New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
							$Created++
						}
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
					if($Action -ne "provision"){
						#move the message to a different queue
						Publish-QueueMessage -Credentials $MessageServiceCredential -Program "edu:usf:cims:PowerShell:ProvisionAccounts" -Queue $ProvisionQueueName -Data $Message.messageData
						Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
						$SkipProcessing = $true
						(Get-Date -Format s)+"|Sending message to provisioning queue" | Out-File $LogFile -Append -Force
					} else {
						if ($Verbose){ Write-Host "Creating account for $UserPrincipalName" }
						$ChangeType = "create"
						(Get-Date -Format s)+"|Creating account for "+$UserPrincipalName+" in "+$ParentContainer | Out-File $LogFile -Append -Force
						New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
						$Created++
					}
				}
			}

			if($SkipProcessing -ne $true){
				#Get a HashMap of attributes
				$NewAttributes = ConvertTo-AttributeHash -AttributesFromJSON $Message.messageData.attributes
			
				$AttrList = Get-AttributesToModify -UserPrincipalName $UserPrincipalName -Attributes $NewAttributes
				if ($Verbose){ $AttrList | Format-List } 
			
				#Update Account
				if ($Verbose) { Write-Host "Updating $UserPrincipalName" }
				try {
					$CurrentAccount = Get-QADUser -UserPrincipalName $UserPrincipalName -IncludedProperties userAccountControl
					
					#Is this account in a managed OU?
					$CurrentParentContainer = $CurrentAccount.ParentContainerDN.ToString()
					$InManagedContainer = Confirm-ManagedContainer -Container $CurrentParentContainer
	
					if($InManagedContainer){				
						#Make sure the account is enabled and doesn't have any special uAC flags
						if( $CurrentAccount.userAccountControl -ne '512' ){
							Set-QADUser -Identity $UserPrincipalName -ObjectAttributes @{userAccountControl=512} | Out-Null
							(Get-Date -Format s)+"|"+$UserPrincipalName+" uAC updated" | Out-File $LogFile -Append -Force
							$Enabled++
						}
						
						#Get correct account location
						$DefaultParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
					
						if( $DefaultParentContainer -ne $CurrentParentContainer ) {
							# Output info
							(Get-Date -Format s)+"|"+$UserPrincipalName+" is in "+$CurrentParentContainer+".  Moving it to "+$DefaultParentContainer | Out-File $LogFile -Append -Force
							Move-Account -UserPrincipalName $UserPrincipalName -Container $DefaultParentContainer | Out-Null
							$Moved++
						}
					}
				
					# Skip everyone in the Disabled User Accounts OU
					if ($CurrentParentContainer -eq $("OU=Disabled User Accounts,OU=Colleges and Departments,"+$BaseDN) ) {
						(Get-Date -Format s)+"|"+$UserPrincipalName+" is in "+$CurrentParentContainer+".  Skipping all modifications." | Out-File $LogFile -Append -Force
					} else {
						#Should the account be in the 'No Access' group?
						$NonActiveMember = Confirm-NonActiveMember -UserPrincipalName $UserPrincipalName
						if( $DefaultParentContainer -eq $("OU=No Affiliation,"+$BaseDN) ) {
							if (! $NonActiveMember -and $InManagedContainer){
								Add-NonActiveMember -UserPrincipalName $UserPrincipalName | Out-Null
								(Get-Date -Format s)+"|"+$UserPrincipalName+" added to Non-Active Group" | Out-File $LogFile -Append -Force
							}
						} else {
							if ($NonActiveMember){
								Remove-NonActiveMember -UserPrincipalName $UserPrincipalName | Out-Null
								(Get-Date -Format s)+"|"+$UserPrincipalName+" removed from Non-Active Group" | Out-File $LogFile -Append -Force
							}
						}
				
						Set-Account -UserPrincipalName $UserPrincipalName -Attributes $AttrList | Out-Null
						# Output info
						(Get-Date -Format s)+"|"+$UserPrincipalName+" updated" | Out-File $LogFile -Append -Force
					}
				
					#Remove message
					Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
				} catch [system.exception] {
					if ($Verbose) { Write-Host $Error[0].Exception }
					$Error[0].Exception | Out-File $LogFile -Append -Force
				}
			
				Remove-Variable ChangeType
			}
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