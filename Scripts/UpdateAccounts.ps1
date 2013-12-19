[string]$LogFile = $input
$ScriptPath = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

Import-Module $ScriptPath\Include\MessageServiceClient.psm1 -Force
Import-Module $ScriptPath\Include\Import-INI.psm1 -Force
Import-Module $ScriptPath\Include\AccountProvisioner.psm1 -Force
Import-Module $ScriptPath\Include\USFProvisionWorker.psm1 -Force

$config = Import-INI "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Config\ProvisionAccounts.ini"

#$StopWatch = [Diagnostics.Stopwatch]::StartNew()

#Set up the credentials we're going to use
$Password = Get-Content $config["MessageService"]["CredentialFile"] | ConvertTo-SecureString 
$MessageServiceCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["MessageService"]["User"],$Password
$WindowsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["ActiveDirectory"]["User"],$Password

$QueueName = $config["MessageService"]["UpdateQueueName"]
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

$TotalMessages = 0
$Created = 0
$Moved = 0
$Enabled = 0

for($counter = 1; $counter -le $MaxMessages; $counter++){

	#Grab a message from the queue
	$Message = Get-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Verbose $Verbose
	
	if ($Message) {
		
		$TotalMessages++
		
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
							"Looking for $Message.messageData.attributes.uid[0], found previous Netid: $Username" | Out-File $LogFile -Append -Force
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
			
			#Create an account if needed
			if($ChangeType -eq "create"){
				#create			
				$ParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
				if ($Verbose) { "Creating account in $ParentContainer" }
				$GivenName = $Message.messageData.attributes.givenName[0]
				$FamilyName = $Message.messageData.attributes.sn[0]
				(Get-Date -Format s)+"|Creating account for "+$UserPrincipalName+" in "+$ParentContainer | Out-File $LogFile -Append -Force
				New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
				$Created++
			}

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
				#Write-LogEntry 1 Error "ProvisionWorker: $Error[0].Exception"
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

#$StopWatch.Stop()
#$elapsed = $StopWatch.Elapsed.toString()

#Add-Content $LogFile "Created: $Created"
#Add-Content $LogFile "Moved: $Moved"
#Add-Content $LogFile "Enabled: $Enabled"
#Add-Content $LogFile "Total messages read: $TotalMessages"
#Add-Content $LogFile "Elapsed time: $elapsed"