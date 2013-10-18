$ScriptPath = "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh"

Import-Module $ScriptPath\Include\Import-INI.psm1 -Force
$config = Import-INI "C:\Users\epierce\Documents\GitHub\MessageServiceWorker-Posh\Config\ProvisionAccounts.ini"



Write-Host "Setting credential for" $config["MessageService"]["User"]
read-host -assecurestring | convertfrom-securestring | out-file $config["MessageService"]["CredentialFile"]