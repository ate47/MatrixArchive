param (
	[string]
	$RoomsFile = "rooms.json",
	[string]
	$Server = "https://matrix.example.com",
	[string]
	$DateFormat = "yyyy/MM/dd HH:mm:ss"
)
function Send-Get {
	# Send a GET and return the result as a PSObject from Json
	[CmdletBinding()]
	param (
		[String]$Path       
	)
	return (Invoke-WebRequest -Method Get -Uri "$Server$Path").Content | ConvertFrom-Json
}
function Send-Post {
	# Send a POST and return the result as a PSObject from Json
	[CmdletBinding()]
	param (
		$Data = @{},
		[String]$Path
	)
	$Json = $Data | ConvertTo-Json -Compress -Depth 100
	Write-Host "Json: '$Json'"
	return (Invoke-WebRequest -Method Post -Body $Json -Uri "$Server$Path" -ContentType "application/json").Content | ConvertFrom-Json
}

function Connect {
	[CmdletBinding()]
	param (
		$User,
		$Secret
	)
	return (Send-Post -Data @{
			"type"     = 'm.login.password'
			"user"     = $User
			"password" = $Secret
		} -Path "/_matrix/client/r0/login").access_token

}

function Get-InitialSync {
	[CmdletBinding()]
	param (
		[string]$RoomId,
		[string]$Token
	)
	# GET /_matrix/client/api/v1/rooms/{roomId}/initialSync
	return (Send-Get "/_matrix/client/api/v1/rooms/$RoomId/initialSync?access_token=$Token")
}

function Get-Messages {
	[CmdletBinding()]
	param (
		[string]$RoomId,
		[string]$Token,
		[string]$FromToken,
		[ValidateSet("f", "b")]
		[string]$Dir = "b",
		[int]$Limit = 1000000000
	)
	#  GET /_matrix/client/api/v1/rooms/{roomId}/messages
	return (Send-Get "/_matrix/client/api/v1/rooms/$RoomId/messages?access_token=$Token&dir=$Dir&limit=$Limit&from=$FromToken")
}

function Get-FromMsTimestamp ($ts) {
	return (Get-Date 01.01.1970) + ([System.TimeSpan]::FromMilliseconds(($ts)))
}

function Get-WithoutSpeChar ($str) {
	return $str.Replace(':', "_").Replace('<', "_").Replace('>', "_").Replace('"', "_").Replace('/', "_").Replace('\', "_").Replace('|', "_").Replace('?', "_").Replace('*', "_")
}

class RoomMessage {
	[array]  $tickets = @()
	[string] $date
	[string] $hours
	[string] $origin
	[string] $content
	RoomMessage($ts, $origin, $content) {
		$d = Get-FromMsTimestamp($ts)
		$this.date = $d.ToString($script:DateFormat)
		$this.origin = $origin
		$this.content = $content
	}
}

$MessageTypeText = 'm.text', 'm.emote', 'm.notice'
$MessageTypeFile = 'm.image', 'm.audio', 'm.video', 'm.file'

function Get-RoomMessage {
	[CmdletBinding()]
	param (
		$messages,
		$tid
	)
	$roomMessages = [System.Collections.ArrayList]::new()
	foreach ($msg in $messages) {

		# Fetch the room messages
		if ($msg.type -eq "m.room.message") {
			$type = $msg.content.msgtype
			$rm = [RoomMessage]::new($msg.origin_server_ts, $msg.user_id, $msg.content.body)
			switch ($type) {
				'm.location' {
					$rm.content += " " + $msg.content.geo_uri
				}
				{ $_ -in $MessageTypeFile } {
					$url = $msg.content.url
					$name = $msg.content.body
					$folder = $tid
					New-Item -Name "output/$folder" -ItemType Directory -Force > $null

					$i = 1
					$fileOr = "output/$folder/$name"
					$file = $fileOr
					$ext = ""
					$extIdx = $fileOr.LastIndexOf(".")
					if ($extIdx -ne -1) {
						$ext = $fileOr.Substring($extIdx)
						$fileOr = $fileOr.Substring(0, $extIdx)
					}

					# test already exists
					while (Test-Path $file) {
						$file = "$fileOr ($i)$ext"
						$i++
					}

					# Download the file
					# GET /_matrix/media/v1/download/{serverName}/{mediaId}
					# mxc://{mserver}/{mediaId}
					$mserver, $mediaId = $url.Substring("mxc://".Length).Split("/")
					$uri = "$Server/_matrix/media/v1/download/$mserver/$mediaId"
					Write-Host -Object "Downloading $uri..." -ForegroundColor Cyan
					Invoke-WebRequest -Uri $uri -OutFile $file > $null
					$rm.content = "< " + $file + " >"
				}
				{ $_ -in $MessageTypeText } {}
			}
			$roomMessages.Add($rm) > $null
		}
	}
	return $roomMessages.ToArray()
}

function Read-Room ($r) {
	Write-Host "RID: $($r.rid)" -ForegroundColor Gray
	Write-Host "USR: $($r.u)" -ForegroundColor Gray
	Write-Host "PWD: $($r.p)" -ForegroundColor Gray
	Write-Host "Connect to Matrix..." -ForegroundColor Cyan
    
	$token = Connect -User $r.u -Secret $r.p
    
	Write-Host "Connected, token: " -ForegroundColor Cyan -NoNewline
	Write-Host $token -ForegroundColor White
    
	Write-Host "Fetching the initial state" -ForegroundColor Cyan
	$initial = Get-InitialSync -RoomId $r.rid -Token $token
    
	$fromToken = $initial.messages.end
    
	Write-Host "Fetched, token: " -ForegroundColor Cyan -NoNewline
	Write-Host $fromToken -ForegroundColor White
    
	Write-Host "Get messages" -ForegroundColor Cyan
	$messages = (Get-Messages -RoomId $r.rid -Token $token -FromToken $fromToken).chunk
	Write-Host "Done." -ForegroundColor Cyan
    
	$tid = Get-WithoutSpeChar $r.rid
	$roomMessages = Get-RoomMessage -Messages $messages -Tid $tid

	$actors = $roomMessages | ForEach-Object { $_.origin } | Sort-Object -Unique

	[array]::Reverse($roomMessages)

	$ticket = @{
		"messages" = $roomMessages
		"actors"   = $actors
		"id"       = $tid
	}

	$ticket | ConvertTo-Json -Depth 8 | Out-File -Encoding utf8 -FilePath "output/$tid.json" 
}

Write-Host "Reading rooms..." -ForegroundColor Cyan
$rooms = Get-Content -Encoding utf8 $RoomsFile | ConvertFrom-Json

New-Item -Name "output" -ItemType Directory -Force
for ($i = 0; $i -lt $rooms.Count; $i++) {
	$r = $rooms[$i]
	Write-Progress -Activity "Reading $($rooms.Count) rooms" -Status ($r.rid) -PercentComplete ($i * 100 / $rooms.Count)
	Read-Room $r
}

