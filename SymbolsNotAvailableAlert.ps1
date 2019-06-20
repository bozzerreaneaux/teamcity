<#
.SYNOPSIS
This script checks if symbol files are successfully retrieved from TeamCity and if not, sends an email alert. Meant to be used in a scheduled task.
Author: bozzerreaneux@github
.DESCRIPTION
Quick script to alert if for any reason it is not possible to retrieve symbols from Teamcity.
Only to be used when Teamcity is also used as a symbol store by utilizing their official symbol store plugin: https://github.com/JetBrains/teamcity-symbol-server
It is a requirement to stick with one particular configuration and respective symbol pdb that gets pruduced by this configuration and adjust the $configID and $PDBID inputs accordingly.
The given configuration builds need to run relatively often in order to ensure up to date coverage.
.PARAMETER configID
Build configuration ID to check against
.PARAMETER teamcityServer
Teamcity server URL
.PARAMETER PDBID
Full name of the PDB file to check against
.PARAMETER EmailFrom
Sender's email
.PARAMETER EmailTo
Recepient's email
.PARAMETER SMTP
SMTP server IP
#>

[CmdletBinding()]

PARAM (

    [Parameter(Mandatory=$TRUE,Position=0)]
	[string]$configID,
	
	[Parameter(Mandatory=$TRUE,Position=1)]
	[string]$teamcityServer = 'https://teamcity'
	
	[Parameter(Mandatory=$TRUE,Position=2)]
	[string]$PDBID
	
	[Parameter(Mandatory=$TRUE,Position=3)]
	[string]$EmailFrom
	
	[Parameter(Mandatory=$TRUE,Position=4)]
	[string]$EmailTo
	
	[Parameter(Mandatory=$TRUE,Position=5)]
	[string]$SMTP
	
	)

$ErrorActionPreference = "Stop"

TRY {
    # Getting hidden artifacts list for the latest successful build for the given configuration (Vms_Main_TopLevelInstallers_MobileServerX64)
    $hiddenArtifacts = Invoke-RestMethod -Uri "$teamcityServer/app/rest/builds/buildType:$configID,branch:default:any,status:success/artifacts/children/.teamcity/symbols" `
                             -Method GET `
                             -UseDefaultCredentials

    # Extracting the correct XML file and build id
    $file = $hiddenArtifacts.files.file.name -match "symbol-signatures-artifacts-*"
    $id = $hiddenArtifacts.files.file.href[0].Substring(20,7)
    
    # opening the "symbol-signatures-artifacts-*.xml" to extract the PDB signature
    $artifactXML = Invoke-RestMethod -Uri "$teamcityServer/repository/download/$configID/$id`:id/.teamcity/symbols/$file" `
                              -Method GET `
                              -UseDefaultCredentials

    $hash = $artifactXML.'file-signs'.InnerXml.Substring(26,32)
}

CATCH {
    Write-Host $_.Exception.Message
}

# building the respective PDB URI for the final check
$uri = "$teamcityServer/app/symbols/$PDBID/$($hash.insert(32,'1'))/$PDBID"

FUNCTION Send-ToEmail([string]$emailTo, [string]$emailFrom, [string]$SMTPServer, [string]$uri, [string]$id){

    $message = new-object Net.Mail.MailMessage
    $message.From = $emailFrom
    $message.To.Add($emailTo)
    $message.Subject = "ALERT::Teamcity symbols stopped working"
    $message.IsBodyHTML = $TRUE
    $message.Body = "<html><body style=`"background: #ff5050`"><p style=`"font-size:16px; font-family:consolas`"><font color=`"white`"; size=6>ALERT</font>: Symbols are not available in TeamCity!<br><br><br>Check was done with:<br><br>- Symbol URI: $uri<br><br><br>- Build: $teamcityServer/viewLog.html?configID=$id&tab=buildResultsDiv&buildTypeId=$configID</p></body></html>"
    $smtp = new-object Net.Mail.SmtpClient($SMTPServer, "25")
    $smtp.EnableSSL = $false
    $smtp.send($message)
    write-host "Mail Sent"
}

IF ((Invoke-Webrequest  -Method HEAD -Uri $uri -UseDefaultCredentials).statuscode -ne 200)
{
    Send-ToEmail  -emailTo $EmailTo -emailFrom $EmailFrom -SMTPServer $SMTP -uri $uri -id $id
}


