$MaxThreads = 10
$SleepTimer = 500

$RunCommand = "C:\Users\epierce.FOREST\Documents\GitHub\MessageServiceWorker-Posh\Scripts\ProvisionAccounts.ps1"
$RunCommandINI = "C:\Users\epierce.FOREST\Documents\GitHub\MessageServiceWorker-Posh\Config\ProvisionAccounts.ini"


# Create a pool of X runspaces
if ($Verbose){
	Write-Host "Creating $MaxProcs RunSpaces"
}

# Load Snap-ins we'll need
$InitBlock = {
	Add-PSSnapin Quest.ActiveRoles.ADManagement
}

# "Killing existing jobs . . ."
Get-Job | Remove-Job -Force

for($counter = 1; $counter -le $MaxThreads; $counter++){
    Start-Job -InitializationScript $InitBlock -FilePath $RunCommand | Out-Null
	Start-Sleep -Milliseconds $SleepTimer
}

Get-Job | Wait-Job


    ForEach($Job in Get-Job){
        "$($Job.Name)"
        "****************************************"
        #Receive-Job $Job
        $Job | Receive-Job
		" "
    }
