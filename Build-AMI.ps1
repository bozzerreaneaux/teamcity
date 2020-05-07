<#
    .SYNOPSIS
        Contains AWS AMI creation logic.
    .DESCRIPTION
        Contains AWS AMI creation logic to support creating multiple AMIs with final output AMIs
        being distributed to Ireland (eu-west-1) and NVirginia (us-east-1) regions in AWS
#>

param (
    # teamcity buildID to be associated with the output AMIs
    [Parameter(Mandatory = $TRUE)]
    [int] $buildID,
    # holds S3 artifacts storage path required for proper creation of the 'component' resource in AWS
    # requires the following parameter defined in S3 upload dependent build in TeamCity: param = "s3://%param.aws.s3.bucket%/%teamcity.project.id%/%system.teamcity.buildType.id%/%teamcity.build.id%"
    [Parameter(Mandatory = $TRUE)]
    [string] $S3ArtifactsPath,
    # ';'-delimitted pairs of configuration settings providing input for token replacement in CF file as well as mapping to base Windows OS image to be used
    # Input should be in this form: "WIN12|<aws base image arn>;WIN16|<aws base image arn>;WIN19|<aws base image arn>"
    [Parameter(Mandatory = $TRUE)]
    [string] $inputBaseImageSettings,
    # input for EC2 instance size/type (used in image builder infrastructure configuration for the base EC2 vm)
    [Parameter(Mandatory = $TRUE)]
    [string] $instanceTypes,
    # input for IAM role (used in image builder infrastructure configuration for the base EC2 vm)
    [Parameter(Mandatory = $TRUE)]
    [string] $instanceProfileName,
    # input for aws security group for the base EC2 instance (used in image builder infrastructure configuration for the base EC2 vm)
    [Parameter(Mandatory = $TRUE)]
    [string] $instanceSecGroupId
)

$ErrorActionPreference = "Stop"

# parse input base image ARN value and determine matching name prefix
$prefix       = $inputBaseImageSettings.Split('|')[0]
$baseImageARN = $inputBaseImageSettings.Split('|')[1]

Write-Host "Preparing configuration for building $prefix AMI with AWS source image ARN:`n$baseImageARN"

try {
    # prepare AMI configuration
    $component = aws imagebuilder create-component `
                                                    --uri "$S3ArtifactsPath/component.yaml" `
                                                    --name "$prefix-$buildID" `
                                                    --semantic-version $(Get-Date -Format "yyyy.MM.dd") `
                                                    --platform "Windows" | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0){
        throw "Creating component failed..."
    }

    $recipe = aws imagebuilder create-image-recipe `
                                                    --name "$prefix-$buildID" `
                                                    --semantic-version $(Get-Date -Format "yyyy.MM.dd") `
                                                    --parent-image $baseImageARN.trim() `
                                                    --components @"
                                                    [
                                                        {
                                                            \"componentArn\": \"$($component.componentBuildVersionArn)\"
                                                        }
                                                    ]
"@ | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0){
         throw "Creating recipe failed..."
    }

    $infraConfig = aws imagebuilder create-infrastructure-configuration `
                                                    --name "$prefix-$buildID" `
                                                    --instance-types $instanceTypes `
                                                    --instance-profile-name $instanceProfileName `
                                                    --security-group-ids $instanceSecGroupId | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0){
        throw "Creating infrastructure configuration failed..."
    }

    $distroConfig = aws imagebuilder create-distribution-configuration `
                                                    --name "$prefix-$buildID" `
                                                    --distributions @"
                                                    [
                                                        {
                                                            \"region\": \"eu-west-1\",
                                                            \"amiDistributionConfiguration\": {
                                                                \"name\": \"$prefix-EU-WEST-1 {{imagebuilder:buildDate}}\",
                                                                \"description\": \"poc\",
                                                                \"launchPermission\": {
                                                                    \"userIds\": [
                                                                        \"939719454067\"
                                                                    ]
                                                                }
                                                            }
                                                        },
                                                        {
                                                            \"region\": \"us-east-1\",
                                                            \"amiDistributionConfiguration\": {
                                                                \"name\": \"$prefix-US-EAST-1 {{imagebuilder:buildDate}}\",
                                                                \"description\": \"poc\",
                                                                \"launchPermission\": {
                                                                    \"userIds\": [
                                                                        \"939719454067\"
                                                                    ]
                                                                }
                                                            }
                                                        }
                                                    ]
"@ | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0){
        throw "Creating distribution configuration failed..."
    }
} catch {
    Write-Host "Preparing AMI configuration failed..."
    $_
    Write-Host "Cleaning up leftover configuration data to ensure fresh start after failure..."
    Write-Host "Some of the following commands might fail if the resource doesn't exist. This is expected."
    aws imagebuilder delete-infrastructure-configuration --infrastructure-configuration-arn $infraConfig.infrastructureConfigurationArn
    aws imagebuilder delete-distribution-configuration --distribution-configuration-arn $distroConfig.distributionConfigurationArn
    aws imagebuilder delete-image-recipe --image-recipe-arn $recipe.imageRecipeArn
    aws imagebuilder delete-component --component-build-version-arn $component.componentBuildVersionArn
    exit 666
}

try {
    Write-Host "Starting AMI build..."
    $AMIBuildProcess = aws imagebuilder create-image `
                                                        --image-recipe-arn $recipe.imageRecipeArn `
                                                        --infrastructure-configuration-arn $infraConfig.infrastructureConfigurationArn `
                                                        --distribution-configuration-arn $distroConfig.distributionConfigurationArn | ConvertFrom-Json
        
    # probe the output AMI 'ARN' until it's status changes to 'available' as this is when the AMI id(s) get published
    $time = [System.Diagnostics.Stopwatch]::StartNew()
    while ($TRUE) {
        $status = (((aws imagebuilder get-image --image-build-version-arn $AMIBuildProcess.imageBuildVersionArn) | ConvertFrom-JSON)).image.state.status
        if ($status -eq 'AVAILABLE'){
            $AMIs = (((aws imagebuilder get-image --image-build-version-arn $AMIBuildProcess.imageBuildVersionArn) | ConvertFrom-JSON)).image.outputResources.amis
            break
        } elseif ($status -eq 'FAILED'){
            throw "AMI build process failed  with AWS Image Builder runtime error"
        } else {
            # print elapsed time for both as to not appear hanging and have an idea how much time the AMI build takes.
            $currentTime = $time.Elapsed
            Write-Host $([string]::Format("`rTime: {0:d2}:{1:d2}:{2:d2}",$currentTime.hours,$currentTime.minutes,$currentTime.seconds)) -nonewline
            Start-Sleep 1
        }
    }

    # Right output AMIs in intermediary JSON
    $AMIs | ConvertTo-JSON | Out-File "$PSScriptRoot\output_AMIs_$prefix.json"
} catch {
    $_
    exit 666
} finally {
    # clean-up
    Write-Host "Cleaning up AWS Image Builder configuration data ..."
    aws imagebuilder delete-infrastructure-configuration --infrastructure-configuration-arn $infraConfig.infrastructureConfigurationArn
    aws imagebuilder delete-distribution-configuration --distribution-configuration-arn $distroConfig.distributionConfigurationArn
    aws imagebuilder delete-image-recipe --image-recipe-arn $recipe.imageRecipeArn
    aws imagebuilder delete-component --component-build-version-arn $component.componentBuildVersionArn
}
