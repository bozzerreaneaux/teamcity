<#
.SYNOPSIS
Overwrites specific sections in a given INI file
.DESCRIPTION
This script takes input from TeamCity step (meta-runner) parameters and updates specific values from an INI configuration file.
When calling the script, use either 'ByValue' or 'ByPath' parameter set by specifying the respective paramter depending on if you are updating file path values or short values (boolean, int, etc.)
Meant to be called in two subsequent build steps/meta-runners if it's required to update both paths and values
#>

[CmdletBinding()]
param (
    #Path to input INI file.
    [Parameter(Mandatory = $TRUE, Position = 0)]
    [string]$InputFilePath,

    #Path to output INI file
    [Parameter(Mandatory = $TRUE, Position = 1)]
    [string]$OutputFilePath,

    #'||' delimited triplets of INI configuration VALUES items:Section;Key;Value||Section1;Key1;Value1
    # ex.: Application;DOUBLE-BYTE;TRUE||Revert Settings;REVERT_VAL_ERROR;FALSE||Online Services;RegexValidationServer;http://someURL
    [Parameter(Mandatory = $TRUE, ParameterSetName = "ByValue")]
    [string]$ValuesToUpdate,

    # Path to file containing CSV values (Section;Key;Value) split by GroupDelimiter
    [Parameter(Mandatory = $TRUE, ParameterSetName = "ByValuesFile")]
    [string]$InputValuesFile,

    #Default section delimiter is "||" but other can be specified if escaping necessary
    [Parameter(Mandatory = $FALSE)]
    [string]$SectionDelimiter = "||",

    #Default group delimiter is ';' but other can be specified if escaping necessary
    [Parameter(Mandatory = $FALSE)]
    [string]$GroupDelimiter = ';'
)

TRY {
    $ErrorActionPreference = "Stop"

    $inputs = $null;

    IF ($PSCmdlet.ParameterSetName -eq 'ByValue') {
        $inputs = $ValuesToUpdate.Split($SectionDelimiter) | ConvertFrom-Csv -Delimiter $GroupDelimiter  -Header "Section", "Key", "Value"
    } ELSE {
        $inputs = Import-Csv -LiteralPath $InputValuesFile -Delimiter $GroupDelimiter  -Header "Section", "Key", "Value"
    }

    Import-Module "$PSScriptRoot\internal\psini\PsIni.psm1"
    $INIConfiguration = Get-IniContent $InputFilePath

    Write-Host "The following values were updated:"
    Write-Host "_________________________________"
    $inputs | ForEach-Object {
        $INIConfiguration[$_.Section][$_.Key] = $_.Value
        Write-Host $_
    }

    Write-Host "`nOutput to: $OutputFilePath ..."

    $INIConfiguration | Out-IniFile $OutputFilePath -Force
} CATCH {
    Write-Host "Failed to update INI file..."
    Write-Host $_
    exit 42
}
