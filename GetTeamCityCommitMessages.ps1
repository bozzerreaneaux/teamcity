<#
.SYNOPSIS
Gets TFVC checkin comments and associated work items.
Designed to be be used from within a TeamCity configuration step.
.DESCRIPTION
Gets all changes for a specific TeamCity build and for each change retrieves comments and associated work items and writes them to an .MD file
Meant to be used inside a TeamCity build step in order for all properties to be resolved correctly.
The .MD file is then passed as an additional --releaseNotesFile argument to Octo.exe in a subsequent step.
author: bozzerreaneux@github
#>

# TeamCity server URL
$teamcityUrl = "%teamcity.serverUrl%"

# TFS project stripped from TeamCity build parameter
$TFVCProject = [regex]::match("%vcsroot.tfs-root%",'/([^/)]+)/').Groups[1].Value

# TFS server URL
$TFSUrl = "%vcsroot.tfs-url%"

# ReleaseNotesFile
$releaseNotesFile = "%system.teamcity.build.tempDir%\releasenotes_%teamcity.build.id%.md"

# Credentials to access TeamCity REST API
$credentials = New-Object System.Net.NetworkCredential("%system.teamcity.auth.userId%", "%system.teamcity.auth.password%")

$AuthHeaderRaw = ($credentials.UserName.ToString() + ":" + $credentials.Password.ToString()).ToString()
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($AuthHeaderRaw)
$AuthHeader = [Convert]::ToBase64String($Bytes)

# Holds current build ID
$buildId = "%teamcity.build.id%"

FUNCTION GetCommitMessagesFromTFS {
  <#
.SYNOPSIS
Gets the commit messages and associated work items for the specIFied change id;
.PARAMETER changeid
The change id to retrieve commit messages for
#>
  [CmdletBinding()]
  PARAM (
    [Parameter(ValueFromPipeline = $TRUE, Mandatory = $TRUE, Position = 0)]
    [string]$changeid
  )
  $url = "$TFSUrl/$TFVCProject/_apis/tfvc/changesets/$($changeid)?includeWorkItems=true"
  
  $request = Invoke-WebRequest -Uri $url  -UseDefaultCredentials
  $response = ConvertFrom-Json $request.Content
  $obj = @{
    Author    = $response.author.displayName;
    Date      = $($response.createdDate).split('T')[0];
    Comment   = $response.comment;
    Id        = $response.changesetId;
    Url       = $response.url;
    WorkItems = $response.workItems | Select-Object  -Property webUrl, title, id
  }
  RETURN $obj;
}

FUNCTION GetBuildDetails {
  <#
.SYNOPSIS
Gets build details for the specIFied build id;
.PARAMETER buildId
The build id to retrieve details for
#>
  [CmdletBinding()]
  PARAM (
    [Parameter(ValueFromPipeline = $TRUE, Mandatory = $TRUE, Position = 0)]
    [string]$buildId
  )

  $url = "$teamcityUrl/httpAuth/app/rest/builds/id:$($buildId)"

  $responseRaw = Invoke-WebRequest -Uri $url -Headers @{ 
    "Authorization" = "Basic $AuthHeader"
    "Accept"        = "application/json"
  }
   
  RETURN  ConvertFrom-Json $responseRaw.Content
}

FUNCTION GetChanges {
  <#
.SYNOPSIS
Gets the  messages and associated work items for this build;
#>
   
  # Get all changes for the current build
  $url = "$teamcityUrl/httpAuth/app/rest/changes?build=id:$($buildId)"
  $requestXML = Invoke-WebRequest -Uri $url -Headers @{"Authorization" = "Basic $AuthHeader"}

  # Get all checkin comments and work items for each change
  $xml = Microsoft.PowerShell.Utility\Select-Xml  -XPath "/changes/change" -Content $requestXML.Content
  $changes = @()
  IF ($xml -ne $null -and $xml -ne "") {

    FOREACH ($item IN $xml) {

      IF (($item -ne $null -and $item -ne "" ) -and $item.Node.version -match '^[0-9]+$') {
        $changes += GetCommitMessagesFromTFS($item.Node.version)
      }

    }

  }
  ELSE {
    $changes += GetCommitMessagesFromTFS("%build.vcs.number%")
  }
  
  RETURN $changes
}

$changes = GetChanges
$buildDetails = GetBuildDetails($buildId)

#Build MD file content...
$ff += "Release Created by build [$($buildDetails.buildType.name) - $($buildDetails.number)]($($buildDetails.webUrl))`r`n`r`n" 
$ff += "**Changeset Comments:**`r`n"

FOREACH ($change IN $changes) {
  $ff += "+ [$($change.date)] [$($change.Id)]($($change.Url)) by $($change.Author) - $($change.Comment)`r`n"
}

$ff += "`r`n**Work Items:**`r`n"
FOREACH ($change IN $changes) {
  FOREACH ($workItem IN $change.WorkItems) {
    $ff += "+ [$($workItem.id)]($($workItem.webUrl)) - $($workItem.title)`rn"
  }
}

$ff > $releaseNotesFile