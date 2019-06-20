<#
.SYNOPSIS
Installs specific versions of NodeJS + specific NPM modules required for web minification jobs:
fs-extra;less;uglifyJS;gulp
author: bozzerreaneux@github
.PARAMETER Computers
An array of Team City agents computernames where nodejs + required modules to be installed
#>

[CmdletBinding()]
PARAM (
    [Parameter(Mandatory = $TRUE,HelpMessage="Please specify list of computer(s) to install Node + modules",Position = 0)]
    [string[]]$computers
	)

FUNCTION Install-NodeModules {
<#
.SYNOPSIS
Checks if NodeJS is installed on the server and if not, installs it. Then installs specific npm modules
#>

	[CmdletBinding()]
	PARAM (
		[Parameter(Mandatory = $TRUE)]
		[string[]]$pcnames
		)

	Invoke-Command -ComputerName $pcnames -ScriptBlock {
		IF (-not ((Get-WmiObject -class Win32_Product).name -like "node*"))
		{
			IF(!(Test-Path "C:\Temp"))
			{
				New-Item -ItemType Directory -Force -Path "C:\Temp"
			}
			Write-Host "PROCESSING:  $(hostname)" -ForegroundColor Cyan
			Write-Host "Proceed installing NodeJS" -ForegroundColor DarkYellow
			$webclient = New-Object System.Net.WebClient
			# Downloading..
			$webclient.DownloadFile("https://nodejs.org/download/release/v6.10.2/node-v6.10.2-x64.msi","C:\Temp\Node_v6.10.2.msi")
			$msifile= "C:\Temp\Node_v6.10.2.msi" 
			$arguments= "/qn"
			Start-Process `
			-file  $msifile `
			-arg $arguments `
			-passthru | Wait-Process
			Start-Sleep -s 5
			Stop-Process -ProcessName Explorer -Force
			Remove-Item "C:\Temp\Node_v6.10.2.msi" -Force
		}
		ELSE
		{
			CONTINUE
		}	
	}
	
	Invoke-Command -ComputerName $pcnames -ScriptBlock {
		Write-Host "PROCESSING:  $(hostname)" -ForegroundColor Cyan
		SETX PATH "%PATH%;c:/Users/build/AppData/Roaming/npm/"
		CMD.EXE /C "npm install gulp"
		CMD.EXE /C "npm install -g gulp"
		CMD.EXE /C "npm install -g fs-extra@2.1.2"
		CMD.EXE /C "npm install -g less@2.7.2"
		CMD.EXE /C "npm install -g uglify-js@2.8.22"       
	}
}
	
Install-NodeModules -pcnames $computers