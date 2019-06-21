<#
.SYNOPSIS
Resets local build counter for all configurations within a specific project in TeamCity
Author: bozzerreaneux@github
.PARAMETER teamcityServerURL
TeamCity server URL
.PARAMETER projectID
Project ID
.PARAMETER user
User authorised properly to execute configuration changes in TeamCity
.PARAMETER password
#>
[CmdletBinding()]
PARAM (
	[Parameter(Mandatory = $TRUE)]
    [string]$teamcityServerURL,
	
	[Parameter(Mandatory = $TRUE)]
    [string]$projectID,
	
    [Parameter(Mandatory = $TRUE)]
    [string]$user,
	
	[Parameter(Mandatory = $TRUE)]
	[string]$password
	)

###########################
#### BEWARE, C# AHEAD! ####
###########################


$Source = @" 
using System;
using System.Net;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

#Defining ResetBuildCounter function
namespace WebReq
{
    public static class WebRequest
    {
        public static void ResetBuildCounter(string id)
        {
            string xml = @"<property name=""buildNumberCounter"" value=""1""/>";
            byte[] arr = System.Text.Encoding.UTF8.GetBytes(xml);
            Uri myUri = new Uri(String.Format("$teamcityServerURL/app/rest/buildTypes/id:{0}/settings/buildNumberCounter", id));
            HttpWebRequest request = (HttpWebRequest)HttpWebRequest.Create(myUri);
            NetworkCredential myNetworkCredential = new NetworkCredential($user, $password);
            CredentialCache myCredentialCache = new CredentialCache
            {
                { myUri, "Basic", myNetworkCredential }
            };
            request.Credentials = myCredentialCache;
            request.Method = "PUT";
            request.ContentType = "application/xml";
            request.ContentLength = arr.Length;
            Stream dataStream = request.GetRequestStream();
            dataStream.Write(arr, 0, arr.Length);
            dataStream.Close();
            HttpWebResponse response = (HttpWebResponse)request.GetResponse();
        }
    }
}
"@ 

#Sourcing the newly defined method
Add-Type -TypeDefinition $Source -Language CSharp

$xml = Invoke-RestMethod -Method GET -Uri "$teamcityServerURL/app/rest/buildTypes?locator=affectedProject:(id:$projectID)" -UseDefaultCredentials

$xml.buildTypes.buildType | FOREACH {[WebReq.WebRequest]::ResetBuildCounter("$_.id")}


