$MaxThreads = 10
$SleepTimer = 50
$ScriptPath = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

$LogDir = $ScriptPath+"\Logs"
$LogFileName = $LogDir+"\update-accounts.log"

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

for($counter = 1; $counter -le $MaxThreads; $counter++){
	$ThreadLogFileName = $LogFileName + "." + $counter
	if(! [IO.File]::Exists($ThreadLogFileName)){
		New-Item -ItemType file -Path $ThreadLogFileName | Out-Null
	}
	$InputObject = "update|"+$ScriptPath+"|"+$ThreadLogFileName 
    Start-Job -InitializationScript $InitBlock -FilePath $RunCommand -InputObject $InputObject  | Out-Null
	Start-Sleep -Milliseconds $SleepTimer
}

Get-Job | Wait-Job | Out-Null

#Combine logs into a single file
for($counter = 1; $counter -le $MaxThreads; $counter++){
	$ThreadLogFileName = $LogFileName + "." + $counter
	$CharCount = (Get-Content $ThreadLogFileName | Measure-Object).count
	if ($CharCount -gt 0){
		Get-Content $ThreadLogFileName | Add-Content $LogFileName
		#Add-Content $LogFileName "`n"
	}
	Remove-Item $ThreadLogFileName
}