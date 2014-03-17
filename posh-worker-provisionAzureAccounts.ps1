$ScriptPath = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

$LogDir = $ScriptPath+"\Logs"
$LogFileName = $LogDir+"\provision-azure.log"

$RunCommand = $ScriptPath+"\Scripts\ProvisionAccounts.ps1"
$ResetStatusCommand = $ScriptPath+"\Scripts\ResetAzureQueue.ps1"

#Create log file if it doesn't already exist
if(! [IO.File]::Exists($LogFileName)){
	New-Item -ItemType file -Path $LogFileName | Out-Null
}

#Load Snap-ins we'll need
$InitBlock = {
	Add-PSSnapin Quest.ActiveRoles.ADManagement
}

$ThreadLogFileName = $LogFileName + ".tmp"
if(! [IO.File]::Exists($ThreadLogFileName)){
	New-Item -ItemType file -Path $ThreadLogFileName | Out-Null
}
$InputObject = "azureProvision|"+$ScriptPath+"|"+$ThreadLogFileName 
Start-Job -InitializationScript $InitBlock -FilePath $RunCommand -InputObject $InputObject  | Out-Null

Get-Job | Wait-Job | Out-Null

#Combine logfile with main one
Get-Content $ThreadLogFileName | Add-Content $LogFileName
Remove-Item $ThreadLogFileName

#Reset all "in-progress" messages to "pending" status
Start-Job -InitializationScript $InitBlock -FilePath $ResetStatusCommand -InputObject $InputObject  | Out-Null

Get-Job | Wait-Job | Out-Null

#Cleanup old jobs
Get-Job -State Completed | Remove-Job