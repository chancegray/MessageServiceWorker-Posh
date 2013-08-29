$SCRIPT:baseURI = "https://sync.it.usf.edu/MessageService/basic"

function ConvertTo-UnsecureString(
 [System.Security.SecureString][parameter(mandatory=$true)]$SecurePassword)
{
	$unmanagedString = [System.IntPtr]::Zero;
	try
	{
		$unmanagedString = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($SecurePassword)
		return [Runtime.InteropServices.Marshal]::PtrToStringUni($unmanagedString)
	}
	finally
	{
		[Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedString)
	}
}

function ConvertTo-Base64($string) {
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($string)
	$encoded = [System.Convert]::ToBase64String($bytes)

	return $encoded
}

function Get-HttpBasicHeader($Credentials, $Headers = @{})
{
	$b64 = ConvertTo-Base64 "$($Credentials.UserName):$(ConvertTo-UnsecureString $Credentials.Password)"
	$Headers["Authorization"] = "Basic $b64"
	return $Headers
}

function Get-QueueFile([string] $action, [string] $type, [string] $name)
{
	$uTime = [string][int][double]::Parse((Get-Date -UFormat %s))
	$rand = Get-Random
	$QueueName = [System.IO.Path]::GetTempPath() + $uTime + "-" + $action + "-" + $name + "-" + $rand + "." + $type
	return $QueueName
}

function Display-Message([PSCustomObject] $Message){
	Write-Host ""
	Write-Host "--"
	Write-Host "Message Data"
	Write-Host "###############################"
	Write-Host "ID: "$Message.id
	Write-Host "Created: "$Message.createTime
	Write-Host "MessageData: "$Message.messageData
	Write-Host "###############################"
}

##################
function Get-Topics($Credentials)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/topic"	
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		return $result.topics
	} catch [System.Net.WebException] {
			Write-Warning "Failed reading topic list."
	}
}

function Get-TopicMessages($Credentials, [string] $Topic)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/topic/$Topic"
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		return $result.messages
	} catch [System.Net.WebException] {
			Write-Warning "Failed reading from topic $Topic."
	}
}

function Publish-TopicMessage($Credentials, [string] $Program, [string] $Topic, [Object] $Data )
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/topic/$Topic"
	$bodyData = @{ apiversion = "1"; createProg = $Program; messageData = $Data } | ConvertTo-Json
	try	{
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "POST" -Body $bodyData -ErrorVariable a
	} catch [System.Net.WebException] {
			$QueueFile = Get-QueueFile "WriteMessage" "topic" $Topic
			Write-Warning "Failed writing to topic $Topic. Writing data to $QueueFile"
			New-Item $QueueFile -type file -value $bodyData | Out-Null
	}
}
#############################
function Get-Queues($Credentials)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue"	
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		return $result.queues
	} catch [System.Net.WebException] {
			Write-Warning "Failed reading queue list."
	}
}

function Get-QueueMessage($Credentials, [string] $Queue, [bool] $Verbose)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue/$Queue"
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		if ($Verbose) {
			Display-Message $result.messages[0]
		}
		if ( $result.messages  -is [System.Array]){
			return $result.messages[0]
		} else {
			$jsonResult = ConvertFrom-Json -InputObject $result
			$jsonResult.gettype() | Write-Host
			$jsonResult | Write-Host
			return
		}	
	} catch [System.Net.WebException] {
		if ($Verbose) {
			Write-Warning "Failed reading from queue $Queue."
			Write-Warning $_ | fl * -Force
		}
	}
}

function Show-QueueMessage($Credentials, [string] $Queue, [int] $Count = 10)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue/$Queue/peek/?count=$Count"
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		return $result.messages
	} catch [System.Net.WebException] {
			Write-Warning "Failed reading from queue $Queue."
	}
}

function Get-InProgress($Credentials, [string] $Queue)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue/$Queue/in-progress"
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "GET"
		return $result.messages
	} catch [System.Net.WebException] {
			Write-Warning "Failed reading from queue $Queue."
	}
}

function Publish-QueueMessage($Credentials, [string] $Program, [string] $Queue, [Object] $Data )
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue/$Queue"
	$bodyData = @{ apiversion = "1"; createProg = $Program; messageData = $Data } | ConvertTo-Json
	try	{
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "POST" -Body $bodyData -ErrorVariable a
	} catch [System.Net.WebException] {
			$QueueFile = Get-QueueFile "WriteMessage" "queue" $Queue
			Write-Warning "Failed writing to queue $Queue. Writing data to $QueueFile"
			New-Item $QueueFile -type file -value $bodyData | Out-Null
	}
}

function Remove-QueueMessage($Credentials, [string] $Queue, [string] $Id, [bool] $Verbose)
{
	$headers = Get-HttpBasicHeader $Credentials
	$uri = "$SCRIPT:baseURI/queue/$Queue/$Id"
	try {
		$ProgressPreference = "SilentlyContinue"
		$result = Invoke-RestMethod -uri $uri -Headers $headers -ContentType "application/json" -Method "DELETE"
		if ($Verbose) { Write-Host "Message $Id deleted" }
	} catch [System.Net.WebException] {
			$QueueFile = Get-QueueFile "DeleteMessage" "queue" $Queue
			Write-Warning "Failed deleting message $Id from queue $Queue. Writing data to $QueueFile"
			Write-Warning $_ | fl * -Force
			New-Item $QueueFile -type file -value $Id | Out-Null
	}
}

Export-ModuleMember -function Get-Topics
Export-ModuleMember -function Get-TopicMessages
Export-ModuleMember -function Publish-TopicMessage
Export-ModuleMember -function Get-Queues
Export-ModuleMember -function Get-QueueMessage
Export-ModuleMember -function Publish-QueueMessage
Export-ModuleMember -function Remove-QueueMessage
Export-ModuleMember -function Show-QueueMessage
Export-ModuleMember -function Get-InProgress


New-Alias -Name peek -Value Show-QueueMessage
Export-ModuleMember -Alias peek

New-Alias -Name InProgress -Value Get-QueueMessage 
Export-ModuleMember -Alias InProgress
