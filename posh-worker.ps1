$MaxThreads = 10
$SleepTimer = 50
$LogDir = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Logs"
$LogFileName = $LogDir+"\provision-"+(Get-Date -Format yyyyMMddHHmss)+".log"

$RunCommand = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Scripts\ProvisionAccounts.ps1"
$RunCommandINI = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Config\ProvisionAccounts.ini"

$StopWatch = [Diagnostics.Stopwatch]::StartNew()

# Create a pool of X runspaces
if ($Verbose){
	Write-Host "Creating $MaxProcs RunSpaces"
}

# Load Snap-ins we'll need
$InitBlock = {
	Add-PSSnapin Quest.ActiveRoles.ADManagement
}

"Starting at " + (Get-Date -Format s)  | Out-File $LogFileName -Append -Force
"MaxThreads: " + $MaxThreads | Out-File $LogFileName -Append -Force
"Sleep between starting threads: " + $SleepTimer + " Milliseconds" | Out-File $LogFileName -Append -Force
"#########################################" | Out-File $LogFileName -Append -Force

for($counter = 1; $counter -le $MaxThreads; $counter++){
	$ThreadLogFileName = $LogFileName + "." + $counter
	if(! [IO.File]::Exists($ThreadLogFileName)){
		New-Item -ItemType file -Path $ThreadLogFileName | Out-Null
	}
    Start-Job -InitializationScript $InitBlock -FilePath $RunCommand -InputObject $ThreadLogFileName | Out-Null
	Start-Sleep -Milliseconds $SleepTimer
}

Get-Job | Wait-Job | Out-Null

#Combine logs into a single file
for($counter = 1; $counter -le $MaxThreads; $counter++){
	$ThreadLogFileName = $LogFileName + "." + $counter
	Add-Content $LogFileName "`n#########################################"
	Add-Content $LogFileName "`nResults from process number $counter"
	Add-Content $LogFileName "`n#########################################"
	Get-Content $ThreadLogFileName | Add-Content $LogFileName
	Add-Content $LogFileName "`n"
	Remove-Item $ThreadLogFileName
}

Add-Content $LogFileName "`nCompleted at $(Get-Date -Format s)"
$StopWatch.Stop()
$elapsed = $StopWatch.Elapsed.toString()
Add-Content $LogFileName "`nTotal Elapsed time: $elapsed"