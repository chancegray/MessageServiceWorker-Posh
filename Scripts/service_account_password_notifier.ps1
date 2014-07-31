$ScriptPath="C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

Import-Module $ScriptPath\Include\MessageServiceClient.psm1 -Force
Import-Module $ScriptPath\Include\Import-INI.psm1 -Force

$config = Import-INI $ScriptPath\Config\ProvisionAccounts.ini


# Hide all Errors
$ErrorActionPreference= 'silentlycontinue'


[int]$NotifyDays = $config["Notifier"]["Days"]
$NotifyMailHost  = $config["Notifier"]["MailHost"]
$NotifyFrom  = $config["Notifier"]["From"]

$LogFile = $ScriptPath+"\Logs\service_account_notifier.log"

$expiring = 0
$expired = 0
$no_requester = 0
	
$expireDate = (Get-Date).AddDays($NotifyDays)
$accounts_to_be_notified = Get-QADUser -Enabled -PasswordNeverExpires:$false -IncludedProperties userprincipalname,PasswordStatus,othermailbox,usfedurequester -SearchAttributes @{usfeduprimaryaffiliation='ServiceAccounts'} | Where {($_.PasswordExpires -lt $expireDate) -and ($_.PasswordStatus -ne "User must change password at next logon.")}

foreach ($account in $accounts_to_be_notified){
	
	#Get the requester's email address
	$requester = $account.usfedurequester
	if(! [string]::IsNullOrEmpty($requester)){
		$requester_email = (Get-QADUser -Identity $requester -IncludedProperties usfeduprimaryemail).USFeduPrimaryEmail
	
    	$today = (get-date)
    	$days_remaining = (New-TimeSpan -Start $today -End $account.PasswordExpires).Days
	
		$body_intro = "The password for a service account (" + $account.userprincipalname + ") expires on " + $account.PasswordExpires + "."
		# Password is already expired
		if($days_remaining -lt 0){
			$subject = "IMPORTANT: The Password for your Service Account has expired!"
			$body_intro = "The password for a service account (" + $account.userprincipalname + ") expired on " + $account.PasswordExpires + "."
			$expired += 1
		# Password expires today
		} elseif ($days_remaining -eq 1) {
			$subject = "IMPORTANT: The Password for your Service Account expires today!"
			$expiring += 1
		# Password expires in 2-30 days
		} else {
			$subject = "IMPORTANT: The Password for your Service Account expires in " + $days_remaining + " days"
			$expiring += 1
		}
		
		$requester_body = $body_intro + "
You are receiving this message because you requested the creation of this account or have been designated as the person responsible for the account.
To update the password, please go to  https://netid.usf.edu/AccountTools/Change_SVC_Password  You will be prompted to login with your NetID before 
changing the password for the service account.  Notify and coordinate with all users of this service account BEFORE changing the password.
			
To remove this account if it is no longer needed, please submit a ServiceNow Ticket for IT Security at https://usffl.service-now.com"
		
		#Get the notification list and remove the requester's email if it exists
		$raw_notify_list = $account.othermailbox
		if($raw_notify_list -is [system.array]){
			$notify_list = 	$raw_notify_list -ne $requester_email	
			
			$notify_list_body = $body_intro + "
You are receiving this message because you were identified by the requester of the account (" + $requester_email + ") as an important
user of this account.  Please contact the requester to learn the new password.

Only the requester can change the password, if the requester is not available, please submit a ServiceNow Ticket for IT Security at https://usffl.service-now.com"
		} else {
			$notify_list = @()
			$raw_notify_list = @()
		}
	
	# No requester - send an error message
	} else {
		$requester_email = "epierce@usf.edu"
		$subject = "No requester found for " + $account.SamAccountName
		$requester_body  = "The account( " + $account.SamAccountName + ") expires on " + $account.PasswordExpires + " and does not have a requester set!"
		
		Send-MailMessage -SmtpServer $NotifyMailHost -From $NotifyFrom -To $requester_email -Subject $subject -Body $requester_body
		$no_requester += 1
	}
	
	Send-MailMessage -SmtpServer $NotifyMailHost -From $NotifyFrom -To $requester_email -Subject $subject -Body $requester_body
	
	if( $notify_list -is [system.array] ){
		foreach ($address in $notify_list) {
			Send-MailMessage -SmtpServer $NotifyMailHost -From $NotifyFrom -To $address -Subject $subject -Body $notify_list_body
		}
	}
	
	# Cleanup variables for next account
	Remove-Variable raw_notify_list
	Remove-Variable notify_list
	Remove-Variable requester
}
(Get-Date -Format s)+"|EXPIRING:"+$expiring+"|EXPIRED:"+$expired+"|ERROR:"+$no_requester | Out-File $LogFile -Append -Force