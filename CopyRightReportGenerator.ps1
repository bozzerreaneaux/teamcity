<#
.SYNOPSIS
Produces a report with binaries and company owner information from DLL and EXE file properties
.DESCRIPTION
Scans all DLL and EXE files for the *Copyright* and/or *Digital Signature* field and finally ouput a summary to a CSV file.
author: bozzerreaneux@github
.PARAMETER PATH
Path to desired folder where all packages will be present + destination for the final report.
.EXAMPLE
CopyRightReportGenerator.ps1 "PATH\TO\DESTINATION\FOLDER"
#>

[CmdletBinding()]
PARAM (
    [Parameter(Mandatory=$TRUE,Position=1)]
    [string]$PATH
)

$ErrorActionPreference = 'Stop'

$targetpackages = Get-ChildItem $PATH -Include *.tar.gz -Recurse

# Extracting...
#$targetpackages.FullName | 
#% {CMD.EXE /C "$PSScriptRoot\Tools\7Z\7za.exe x $_ -so | $PSScriptRoot\Tools\7Z\7za.exe x -aoa -si -ttar -o`"$(Split-Path $_ -parent)\package`""}

# Scanning through all .DLL,.EXE,.H and .LIB files for the *CopyRight* property and producing final report
Write-Host "`nScanning through files...`n"
$files = Get-ChildItem $PATH -Include '*.dll','*.exe' -Recurse

$(FOREACH ($file in $files) 
{ 
    IF ([IO.Path]::GetExtension($file.FullName) -eq ".exe") 
    {
		IF (((Get-AuthenticodeSignature $file.FullName).SignerCertificate -eq $NULL) -or (((Get-AuthenticodeSignature $file.FullName).SignerCertificate.Length -lt 3)) )
        {
			IF (([System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName).LegalCopyRight.Length -gt 3))
            {
				[pscustomobject]@{"BINARY" = $file.Name; "COMPANY" = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName).LegalCopyRight}
			}
			ELSE
            {
				[pscustomobject]@{"BINARY" = $file.Name; "COMPANY" = "MISSING INFO"}
			}
		}
		ELSE 
        {
			[pscustomobject]@{"BINARY" = $file.Name; "COMPANY" = $(Get-AuthenticodeSignature $file.FullName).SignerCertificate.Subject.Split(',')[0]}
		}
    } 	
	IF ([IO.Path]::GetExtension($file.FullName) -eq ".dll") 
    {
		IF (([System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName).LegalCopyRight.Length -gt 3))
            {
				[pscustomobject]@{"BINARY" = $file.Name; "COMPANY" = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName).LegalCopyRight}
			}
			ELSE 
            {
				[pscustomobject]@{"BINARY" = $file.Name; "COMPANY" = "MISSING INFO"}
			}
    }
}) |
Export-Csv $PATH\CopyRight_Report.csv -Append -NoTypeInformation

Write-Host "Please find the generated report here:`n`n`t (╯°□°）╯︵ ┻━┻`t`t $(Resolve-Path $PATH\CopyRight_Report.csv)`n`n" -ForegroundColor Yellow
