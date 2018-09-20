$rra_users = (Get-ADUser -Filter {samaccountname -like "rra-*"}) | Select-Object -Property samaccountname,givenname,surname,distinguishedname

$formatted = [string] ($rra_users | Format-Table -AutoSize | Out-String)

Send-MailMessage -SmtpServer "bumblebee.forest.usf.edu" -From "cims-tech-core@mail.usf.edu" -To "cims-tech-core@mail.usf.edu" -Subject "Restricted Research Accounts" -Body $formatted