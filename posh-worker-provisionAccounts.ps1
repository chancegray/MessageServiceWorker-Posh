#Sleep 2 seconds between runs
$SleepTimer = 2000
$ScriptPath = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

$LogDir = $ScriptPath+"\Logs"
$LogFileName = $LogDir+"\provision-accounts.log"

$RunCommand = $ScriptPath+"\Scripts\ProvisionAccounts.ps1"
$RunCommandINI = $ScriptPath+"\Config\ProvisionAccounts.ini"

#Create log file if it doesn't already exist
if(! [IO.File]::Exists($LogFileName)){
	New-Item -ItemType file -Path $LogFileName | Out-Null
}

# Load Snap-ins we'll need
$InitBlock = {
	Add-PSSnapin Quest.ActiveRoles.ADManagement
}

#Loop forever
while($true){
	$ThreadLogFileName = $LogFileName + ".tmp"
	if(! [IO.File]::Exists($ThreadLogFileName)){
		New-Item -ItemType file -Path $ThreadLogFileName | Out-Null
	}
	$InputObject = "provision|"+$ScriptPath+"|"+$ThreadLogFileName 
    Start-Job -InitializationScript $InitBlock -FilePath $RunCommand -InputObject $InputObject -Name "AccountProvision" | Out-Null

	#Wait for the job to complete, but give up after 5 minutes
	Get-Job | Wait-Job -Timeout 300 | Out-Null

	#Combine logfile with main one
	Get-Content $ThreadLogFileName | Add-Content $LogFileName
	Remove-Item $ThreadLogFileName
	
	#wait to start next loop
	Start-Sleep -Milliseconds $SleepTimer
	
	#Cleanup old jobs
	Get-Job -Name "AccountProvision" | Remove-Job
}