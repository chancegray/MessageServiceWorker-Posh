
function Get-EncryptedAesString {
	param(
        [Parameter(Mandatory=$true)] [System.String] $Encrypted,
        [Parameter(Mandatory=$true)] [System.String] $Passphrase
	)

	$rawData = [Convert]::FromBase64String($Encrypted)
	$iv = New-Object Byte[] 32
	[int] $cipherTextSize = $rawData.length - $iv.length
	$cipherText = [Byte[]]@(0)*$cipherTextSize

	#Split the string into the cypherText and the IV
	[System.Array]::Copy($rawData, 0, $iv, 0, 32)
	[System.Array]::Copy($rawData, 32, $cipherText, 0, $cipherTextSize)

	$Encode = new-object System.Text.ASCIIEncoding

	$r = new-Object System.Security.Cryptography.RijndaelManaged  # use Rijndael symmetric key encryption
	$r.KeySize = 256
	$r.BlockSize = 256
	$r.Mode = 'CBC'
	$r.Padding = 'PKCS7'
	$r.IV = $iv
	$r.Key = [system.Text.Encoding]::ASCII.GetBytes($Passphrase)
	
	# Create a new Decryptor`
	$d = $r.CreateDecryptor()
	# Create a New memory stream with the encrypted value.
	$ms = new-Object IO.MemoryStream @(,$cipherText)
	# Read the new memory stream and read it in the cryptology stream
	$cs = new-Object Security.Cryptography.CryptoStream $ms,$d,"Read"
	# Read the new decrypted stream
	$sr = new-Object IO.StreamReader $cs
	# Return from the function the stream
	Write-Output $sr.ReadToEnd()
	# Stops the stream	
	$sr.Close()
	# Stops the crypology stream
	$cs.Close()
	# Stops the memory stream
	$ms.Close()
	# Clears the RijndaelManaged Cryptology IV and Key
	$r.Clear()
}

Export-ModuleMember -Function Get-EncryptedAesString