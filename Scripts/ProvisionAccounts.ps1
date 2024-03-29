[String]$StartupString = $input
$StartupObject = $StartupString.split("|")
[String]$Action = $StartupObject[0]
[String]$ScriptPath = $StartupObject[1]
[String]$LogFile = $StartupObject[2]

# Ignore certificate errors
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

<#
$LogFile = "D:\Provisioning\MessageServiceWorker-Posh\Logs\test.log"
$Action="provision"
$ScriptPath="D:\Provisioning\MessageServiceWorker-Posh"
Add-PSSnapin Quest.ActiveRoles.ADManagement
#>

Import-Module ActiveDirectory
Import-Module MSOnline -Force
Import-Module $ScriptPath\Include\MessageServiceClient.psm1 -Force
Import-Module $ScriptPath\Include\Import-INI.psm1 -Force
Import-Module $ScriptPath\Include\AccountProvisioner.psm1 -Force
Import-Module $ScriptPath\Include\USFProvisionWorker.psm1 -Force
Import-Module $ScriptPath\Include\Get-EncryptedAesString.psm1 -Force

$config = Import-INI $ScriptPath\Config\ProvisionAccounts.ini

#Set up the credentials we're going to use
$MessageServicePassword = Get-Content $config["MessageService"]["CredentialFile"] | ConvertTo-SecureString
$WindowsPassword = Get-Content $config["ActiveDirectory"]["CredentialFile"] | ConvertTo-SecureString
$AzurePassword = Get-Content $config["Azure"]["CredentialFile"] | ConvertTo-SecureString
$MessageServiceCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["MessageService"]["User"],$MessageServicePassword
$WindowsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["ActiveDirectory"]["User"],$WindowsPassword
$AzureCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config["Azure"]["User"],$AzurePassword
$AesPassphrase = Get-Content $config["MessageService"]["AESpassphraseFile"]
$UpnDomain = $config["ActiveDirectory"]["UpnDomain"]
$O365Domain = $config["Azure"]["Office365Domain"]
$Domain = $config["ActiveDirectory"]["Domain"]
$BaseDN = $config["ActiveDirectory"]["BaseDN"]

#Do we already have a connection to the Exchange servers?
if (! (Get-PSSession -Name "OnPremExchange" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
	#Connect to On-Premise Exchange
	$ProgressPreference = "SilentlyContinue";
	$ExchSession = New-PSSession -Name "OnPremExchange" -ConfigurationName Microsoft.Exchange -ConnectionUri $config["ActiveDirectory"]["ExchangePowerShellURI"] -Authentication Kerberos -Credential $WindowsCredential
	Import-PSSession $ExchSession -AllowClobber -WarningAction SilentlyContinue -Prefix "OnPrem" | Out-Null
	if ($Verbose){ Write-Host "Created OnPremExchange Powershell connection" }
}


if (! (Get-PSSession -Name "AzureExchange" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
	#Connect to Azure Active Directory
	$O365Session = New-PSSession -Name "AzureExchange" -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $AzureCredential -Authentication Basic -AllowRedirection -WarningAction SilentlyContinue
	Import-PSSession $O365Session -AllowClobber -WarningAction SilentlyContinue -Prefix "Azure" | Out-Null 
	Connect-MsolService -Credential $AzureCredential
	if ($Verbose){ Write-Host "Created AzureExchange Powershell connection" }
}

#Connect to On-Premises Active Directory
$Connection = Connect-QADService -service $Domain -Credential $WindowsCredential

$UpdateQueueName = $config["MessageService"]["UpdateQueueName"]
$ProvisionQueueName = $config["MessageService"]["ProvisionQueueName"]
$AzureQueueName = $config["MessageService"]["AzureQueueName"]
$ConfirmationTopicName = $config["MessageService"]["ConfirmationTopicName"]

$MaxMessages = $config["MessageService"]["MaxMessages"]
$MaxThreads = $config["MessageService"]["MaxThreads"]
$SleepTimer = $config["MessageService"]["SleepTimer"]

if ($config["ActiveDirectory"]["Verbose"] -eq "true"){
	$Verbose = $true
} else {
	$Verbose = $false
}

switch ($Action) {
	"provision" { $QueueName = $ProvisionQueueName }
	"azureProvision" { $QueueName = $AzureQueueName }
	default { $QueueName = $UpdateQueueName }
}

if ($Verbose){ Write-Host "Retreiving" $MaxMessages "messages from " $QueueName }

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
			
			if ($Verbose){ Write-Host "This user has" $Message.messageData.attributes.uid.length "uid entries" }
			
			if($Message.messageData.attributes.uid.length -gt 1){
				#Multiple NetIDs - Check the primary one first
				$Username = $Message.messageData.attributes.uid[0]
				$UserPrincipalName = $($Username+"@"+$UpnDomain)
				$RemoteMailAddress = $($Username+"@"+$O365Domain)
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
						$RemoteMailAddress = $($Username+"@"+$O365Domain)
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
							$RemoteMailAddress = $($Username+"@"+$O365Domain)
							if ($Verbose){ Write-Host "Creating account for $UserPrincipalName" }
							(Get-Date -Format s)+"|Creating account for "+$UserPrincipalName+" in "+$ParentContainer | Out-File $LogFile -Append -Force
 
							if ( [String]::IsNullOrEmpty($Message.messageData.password) ) {
								if ($Verbose){ Write-Host "No password in message.  Creating the account with a random password." }
								New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
							} else {
								$Password = Get-EncryptedAesString -Encrypted $Message.messageData.password -Passphrase $AesPassphrase
								if ($Verbose){ Write-Host "Found an encrypted password.  Decrypted to "+$Password }
								New-Account -Username $Username -Password $Password -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
							}
							$Created++
						}
					}
				}
			} else {
				#Single NetID
				$Username = $Message.messageData.attributes.uid[0]
				$UserPrincipalName = $($Username+"@"+$UpnDomain)
				$RemoteMailAddress = $($Username+"@"+$O365Domain)
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
						if ( [String]::IsNullOrEmpty($Message.messageData.password) ) {
							if ($Verbose){ Write-Host "No password in message.  Creating the account with a random password." }
							New-Account -Username $Username -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
						} else {
							$Password = Get-EncryptedAesString -Encrypted $Message.messageData.password -Passphrase $AesPassphrase
							if ($Verbose){ Write-Host "Found an encrypted password.  Decrypted to "+$Password }
							New-Account -Username $Username -Password $Password -ParentContainer $ParentContainer -GivenName $GivenName -FamilyName $FamilyName -Domain $UpnDomain | Out-Null
						}
						$Created++
					}
				}
			}

<#################################
# Account Provisioning Complete
# Begin Azure Account Provisioning
##################################>

			if($Action -eq "azureProvision"){
				(Get-Date -Format s)+"|Started Azure Provisioning for: "+$UserPrincipalName | Out-File $LogFile -Append -Force
			
				#Does a Windows Azure account exist for this user?
				if ( Get-MsolUserExists -UserPrincipalName $UserPrincipalName ){
					if ($Verbose){ Write-Host "$UserPrincipalName exists in Windows Azure" }
					(Get-Date -Format s)+"|"+$UserPrincipalName+" found in Windows Azure."  | Out-File $LogFile -Append -Force
					#Is the user already Licensed?
					if(Get-MsolUserIsLicensed -UserPrincipalName $UserPrincipalName){
						#Get Licenses
						$Licenses = Get-MsolUserLicenses -UserPrincipalName $UserPrincipalName
						if ($Verbose){ Write-Host "$UserPrincipalName has these licenses: $Licenses" }
						
						(Get-Date -Format s)+"|"+$UserPrincipalName+" was already licensed:"+$Licenses | Out-File $LogFile -Append -Force
						#Remove Message from Windows Azure Queue
						Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
					} else {
						# Add an On-Prem Lync Account
						#if (! (Get-PSSession -Name "OnPremLync" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
							#Connect to On-Premise Lync Server
							#$LyncSession = New-PSSession -Name "OnPremLync" -ConnectionUri $config["ActiveDirectory"]["LyncPowerShellURI"] -Credential $WindowsCredential
							#Import-PSSession $LyncSession -AllowClobber -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
							#if ($Verbose){ Write-Host "Created OnPremLync Powershell connection" }
						#}
						#Enable-CsUser -Identity $UserPrincipalName -RegistrarPool $config["ActiveDirectory"]["LyncPoolHost"] -SipAddressType UserPrincipalName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
						#(Get-Date -Format s)+"|Lync Account added for "+$UserPrincipalName  | Out-File $LogFile -Append -Force
						
						#License User - the mailbox is created automatically
						if ($Verbose){ Write-Host "Adding licenses to $UserPrincipalName" }
						$licenseError = Set-MsolUserLicenses -UserPrincipalName $UserPrincipalName	
                        (Get-Date -Format s)+"|"+$UserPrincipalName+" license errors: "+$licenseError  | Out-File $LogFile -Append -Force
						
						if(Get-MsolUserIsLicensed -UserPrincipalName $UserPrincipalName){
							(Get-Date -Format s)+"|"+$UserPrincipalName+" licensed successfully."  | Out-File $LogFile -Append -Force
							
							#Adding necessary attributes to local AD
							Enable-OnPremRemoteMailbox $UserPrincipalName -RemoteRoutingAddress $RemoteMailAddress -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
							(Get-Date -Format s)+"|Remote mailbox added to AD account "+$UserPrincipalName  | Out-File $LogFile -Append -Force
							#Remove Message from Windows Azure Queue
							Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
						}
					}
					
				} else {
					if ($Verbose){ Write-Host "$UserPrincipalName does not exist in Windows Azure. Skipping." }
					(Get-Date -Format s)+"|"+$UserPrincipalName+" does not exist in Windows Azure. Skipping."  | Out-File $LogFile -Append -Force
				}
			
				#Skip all other processing
				$SkipProcessing = $true
			
			}
			
<############################
# Provisioning Complete
# Begin Account Updates
##############################>

			if($SkipProcessing -ne $true){
				#Get a HashMap of attributes
				$NewAttributes = ConvertTo-AttributeHash -AttributesFromJSON $Message.messageData.attributes -UpnDomain $UpnDomain
			
				$AttrList = Get-AttributesToModify -UserPrincipalName $UserPrincipalName -Attributes $NewAttributes
				if ($Verbose){ $AttrList | Format-List } 
				
				#Does this user need an Exchange acount and does one already exist?
				$CreateExchangeAccount = Get-ExchangeAccountNeeded $Message.messageData.attributes
				$OnPremExchangeAccount = Get-OnPremMailboxExists $UserPrincipalName
				$AzureExchangeAccount = Get-AzureMailboxExists $UserPrincipalName
				
				#Update Account
				if ($Verbose) { Write-Host "Updating $UserPrincipalName" }
				try {
					$CurrentAccount = Get-QADUser -Identity $UserPrincipalName -IncludedProperties userAccountControl
					
					#Update CIMS Groups
					$CurrentCimsGroups = Get-CurrentCimsGroupList -UserPrincipalName $UserPrincipalName
					
					if (! $CurrentCimsGroups.Count -gt 0) { [System.Array] $CurrentCimsGroups = $() }
					
					if ($Verbose) { Write-Host "Current CIMS groups: $CurrentCimsGroups"}
					
					$Results = Set-CimsGroups -UserPrincipalName $UserPrincipalName -NewCimsGroups $Message.messageData.attributes.CimsGroups
				
					(Get-Date -Format s)+"|"+$UserPrincipalName+" "+$Results | Out-File $LogFile -Append -Force
					if ($Verbose) { Write-Host $Results }
					
                    # Set the correct uAC flags
					Get-ADUser -Filter {userprincipalname -eq $UserPrincipalName} | Set-ADAccountControl -CannotChangePassword $true -PasswordNeverExpires $false -PasswordNotRequired $false | out-null
                    (Get-Date -Format s)+"|"+$UserPrincipalName+" account uAC updated" | Out-File $LogFile -Append -Force
					
					#Is this account in a managed OU?
					$CurrentParentContainer = $CurrentAccount.ParentContainerDN.ToString()
					$InManagedContainer = Confirm-ManagedContainer -Container $CurrentParentContainer
		
					if($InManagedContainer){				
						if ($Verbose) { Write-Host "$UserPrincipalName is in a managed OU: "$CurrentParentContainer }
						#Make sure the account is enabled
						if( $CurrentAccount.userAccountControl -ne '512' ){
							if ($Verbose) { Write-Host "Updating $UserPrincipalName to be a regular account" }
							Set-QADUser -Identity $UserPrincipalName -ObjectAttributes @{userAccountControl=512} | Out-Null
							(Get-Date -Format s)+"|"+$UserPrincipalName+" account enabled" | Out-File $LogFile -Append -Force
							$Enabled++
						}
				
						#Does this user need an Exchange Account?
						if($CreateExchangeAccount){
							if($Verbose) { Write-Host "Exchange Account required for $UserPrincipalName" }
							
							#If NAMS says an Exchange account already exists, don't create another one
							if ($Message.messageData.attributes.ExchangeAccountExists -and $Message.messageData.attributes.ExchangeAccountExists[0] -eq "Yes"){
								$ExchangeAccountExists = $true
							} else {
								$ExchangeAccountExists = $false
							}
							
							#If the user doesn't already have an Exchange account put it on the Windows Azure queue
							if ( (! $OnPremExchangeAccount) -and (! $ExchangeAccountExists)) {
								if($Verbose) { Write-Host "Publishing message to Windows Azure queue" }
								(Get-Date -Format s)+"|Moving message for "+$UserPrincipalName+" to Office365 queue" | Out-File $LogFile -Append -Force
								Publish-QueueMessage -Credentials $MessageServiceCredential -Program "edu:usf:cims:PowerShell:ProvisionAccounts" -Queue $AzureQueueName -Data $Message.messageData
							}
						} else {
						#User is NOT eligible for Exchange
						
							#If this account already has an Exchange account, disable it
							if($OnPremExchangeAccount){
							#	Disable-OnPremMailboxAccess $UserPrincipalName
							#	(Get-Date -Format s)+"|"+$UserPrincipalName+" OnPrem Exchange Account Disabled" | Out-File $LogFile -Append -Force
							#} elseif($AzureExchangeAccount) {
							#	Disable-AzureMailboxAccess $UserPrincipalName
							#	(Get-Date -Format s)+"|"+$UserPrincipalName+" Office365 account Disabled" | Out-File $LogFile -Append -Force
							} else {
							#User does not have an existing Exchange account
																				
								#Does the user have an email address at all?
								if($Message.messageData.attributes.USFeduPrimaryEmail -and $Message.messageData.attributes.USFeduPrimaryEmail[0] -match '.*@.*'){
									$PrimaryEmail = $Message.messageData.attributes.USFeduPrimaryEmail[0]
									if($Verbose) { Write-Host "$UserPrincipalName has an email address: $PrimaryEmail" }
									
									#Should this address be hidden from the GAL?
									$HideAddressFromGal = Get-HideAddressFromGal -AttributesFromJSON $Message.messageData.attributes
									
									#Is this address already in the GAL?
									if (Get-OnPremGalAddressExists -EmailAddress $PrimaryEmail) {
										if($Verbose) { Write-Host "$PrimaryEmail is already in the GAL" }
										$OnPremGalAddressHidden = Get-OnPremGalAddressHidden -EmailAddress $PrimaryEmail
										
										#Hide/Show Address where needed
										if( $OnPremGalAddressHidden -ne $HideAddressFromGal ) {
											if ($HideAddressFromGal){
												if($Verbose) { Write-Host "Hiding $PrimaryEmail from the GAL" }
												Set-OnPremGalAddressHidden -EmailAddress $PrimaryEmail -Value $true
											} else {
												if($Verbose) { Write-Host "Making $PrimaryEmail visible to the GAL" }
												Set-OnPremGalAddressHidden -EmailAddress $PrimaryEmail -Value $false
											}
										}								
									} else {
										if($Verbose) { Write-Host "$PrimaryEmail is not in the GAL" }
										# Mail-enable the user if necessary
										if ((! $HideAddressFromGal) -and (Confirm-ContactNeeded $PrimaryEmail) ) {
											
											#is the user already mail-enabled with another address?
											if (Get-OnPremMailUser -Identity $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null){
												Set-OnPremMailUser -Identity $UserPrincipalName -ExternalEmailAddress $PrimaryEmail -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
											} else {
												Enable-OnPremMailUser -Identity $UserPrincipalName -ExternalEmailAddress $PrimaryEmail -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
											}
											if($Verbose) { Write-Host "Added $PrimaryEmail to the GAL" }
											
											#Because of the default email address policy that is applied to addresses in forest, we need to remove the @usf.edu and @onmicrsoft.com addresses
											$EmailAddresses = (Get-OnPremMailUser -Identity $UserPrincipalName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Select-Object EmailAddresses).EmailAddresses -notmatch ".*@usf.edu|.*@.*onmicrosoft.com"
											Set-OnPremMailUser -Identity $UserPrincipalName -EmailAddresses $EmailAddresses -EmailAddressPolicyEnabled $false | Out-Null
											if ($Verbose){ "Disabled default email address policy for $UserPrincipalName" }
										}
									}
								}
							}
						}
						
						#Get correct account location
						$DefaultParentContainer = Resolve-DefaultContainer -AttributesFromJSON $Message.messageData.attributes -BaseDN $BaseDN
					
						if( $DefaultParentContainer -ne $CurrentParentContainer ) {
							# This user is no longer affiliated and has an Exchange account, so move them to the 'transition' OU
							if (($DefaultParentContainer -eq $("OU=No Affiliation,"+$BaseDN) ) -and ($AzureExchangeAccount -or $OnPremExchangeAccount)) {
								$DefaultParentContainer = $("OU=Transition User Accounts,OU=Colleges and Departments,"+$BaseDN)
								
								# Update the description to identify when the account was moved
                                if ($CurrentAccount.description -ne $null) {
								    $description = $($CurrentAccount.description+" (Moved automatically: "+$(Get-Date -Format s)+")") 
								} else {
                                    $description = "Moved automatically: "+$(Get-Date -Format s)
                                }
                                (Get-Date -Format s)+"|Setting description for "+$UserPrincipalName+" to: "+$description | Out-File $LogFile -Append -Force
								Set-QADUser -Identity $UserPrincipalName -Description $description | Out-Null
							}
							if ($Verbose) { Write-Host -NoNewline "Moving $UserPrincipalName from $CurrentParentContainer to $DefaultParentContainer" }
							# Output info
							(Get-Date -Format s)+"|"+$UserPrincipalName+" is in "+$CurrentParentContainer+".  Moving it to "+$DefaultParentContainer | Out-File $LogFile -Append -Force
							Move-Account -UserPrincipalName $UserPrincipalName -Container $DefaultParentContainer | Out-Null
							if ($Verbose) { Write-Host "done" }
							$Moved++
						}
					}
				
					# Skip everyone in the Disabled User Accounts OU
					if ($CurrentParentContainer -eq $("OU=Disabled User Accounts,OU=Colleges and Departments,"+$BaseDN)) {
						if ($Verbose) { Write-Host "$UserPrincipalName is in $DefaultParentContainer  Skipping." }
						(Get-Date -Format s)+"|"+$UserPrincipalName+" is in "+$CurrentParentContainer+".  Skipping all modifications." | Out-File $LogFile -Append -Force
					} else {
						# Don't modify the description on accounts in the Transition User OU
						if ($CurrentParentContainer -eq $("OU=Transition User Accounts,OU=Colleges and Departments,"+$BaseDN)) {
							$AttrList.Remove('description')
							if ($Verbose) { Write-Host "$UserPrincipalName is in $DefaultParentContainer  Skipping change to description." }
							(Get-Date -Format s)+"|"+$UserPrincipalName+" is in "+$CurrentParentContainer+".  Skipping change to description." | Out-File $LogFile -Append -Force
							
							# Treat this account like it has no affiliation
							$DefaultParentContainer = $("OU=No Affiliation,"+$BaseDN)
						}
						#Should the account be in the 'No Access' group?
						$NonActiveMember = Confirm-NonActiveMember -UserPrincipalName $UserPrincipalName
						if( $DefaultParentContainer -eq $("OU=No Affiliation,"+$BaseDN) ) {
							if (! $NonActiveMember -and ($InManagedContainer -or ($CurrentParentContainer -eq $("OU=Transition User Accounts,OU=Colleges and Departments,"+$BaseDN)) )) {
								if ($Verbose) { Write-Host -NoNewline "Adding $UserPrincipalName to Non-Active Group" }
								Add-NonActiveMember -UserPrincipalName $UserPrincipalName | Out-Null
								if ($Verbose) { Write-Host "done" }
								(Get-Date -Format s)+"|"+$UserPrincipalName+" added to Non-Active Group" | Out-File $LogFile -Append -Force
							}
						} else {
							if ($NonActiveMember){
								if ($Verbose) { Write-Host -NoNewline "Removing $UserPrincipalName from Non-Active Group" }
								Remove-NonActiveMember -UserPrincipalName $UserPrincipalName | Out-Null
								if ($Verbose) { Write-Host "done" }
								(Get-Date -Format s)+"|"+$UserPrincipalName+" removed from Non-Active Group" | Out-File $LogFile -Append -Force
							}
						}
				
						if ($Verbose) { Write-Host -NoNewline "Updating $UserPrincipalName..." }
						Set-Account -UserPrincipalName $UserPrincipalName -Attributes $AttrList | Out-Null
						if ($Verbose) { Write-Host "done" }
						# Output info
						(Get-Date -Format s)+"|"+$UserPrincipalName+" updated" | Out-File $LogFile -Append -Force
					}
				
					#Remove message
					Remove-QueueMessage -Credentials $MessageServiceCredential -Queue $QueueName -Id $Message.id -Verbose $Verbose
					
					# Write a message to the confirmation queue
					$confirmationData = @{ requestId = $Message.id; requestTime = $Message.createTime; username = $UserPrincipalName; action = $Action}
					Publish-TopicMessage -Credentials $MessageServiceCredential -Program "edu:usf:cims:PowerShell:ProvisionAccounts" -Topic $ConfirmationTopicName -Data $confirmationData | Out-Null
				} catch [system.exception] {
					if ($Verbose) { Write-Host $Error[0].Exception }
					$Error[0].Exception | Out-File $LogFile -Append -Force
				}
			
				Remove-Variable ChangeType | Out-Null
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

if ( $ExchSession -ne $null ) {
	Remove-PSSession $ExchSession -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
if ($O365Session -ne $null ) {
	Remove-PSSession $O365Session -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}