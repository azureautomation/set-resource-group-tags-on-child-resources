<#
    .DESCRIPTION
        This script iterates through the resource groups and copy the tags to his child resources
        Check for Updates @ https://gallery.technet.microsoft.com/Set-Resource-Group-Tags-On-a3093849

    .PARAMETER SubscriptionId
        Id of the Subscription (optional)

    .NOTES
        AUTHOR: Alexandre Vieira
        LASTEDIT: Jun 13, 2018
#>

param(
    [parameter(Mandatory = $false)]
    [String] $SubscriptionId = ""
)
## To use this Runbook to set Tags on other subscriptions check this article https://blogs.technet.microsoft.com/knightly/2017/05/26/using-azure-automation-with-multiple-subscriptions/
$connectionName = "AzureRunAsConnection"

## List of Resource Type that doesn't support Tags
$resourceTypesConfig = @{"microsoft.insights/alertrules"=""; "microsoft.insights/activityLogAlerts"=""; "Microsoft.OperationsManagement/solutions"=""; "Microsoft.Network/localNetworkGateways"=""; "Microsoft.Web/certificates"=""; "Microsoft.Sql/servers/databases"=""} 

$verbose = $FALSE

try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    if ([string]::IsNullOrEmpty($SubscriptionId)) {
        Write-Output "Logging in to Azure on default Subscription ..."
        $azureaccount = Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    else {
        Write-Output "Logging in to Azure on Subscription: $SubscriptionId ..."
        $azureaccount = Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -Subscription $SubscriptionId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint         
        $subscription = Get-AzureRmSubscription -SubscriptionId $SubscriptionId
        Write-Output ("Subscription Name: '{0}'" -f $subscription.Name)                    
    }

}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$resourceGroupList = Get-AzureRmResourceGroup
foreach ($resourceGroup in $resourceGroupList) {
    if ($resourceGroup.Tags.Count -gt 0) {
        $resourceList = Get-AzureRmResource -ResourceGroupName $resourceGroup.ResourceGroupName
        foreach ($resource in $resourceList) {
            if (-not($resourceTypesConfig.ContainsKey($resource.Type))) {
                if (-not($resource.Tags)) {
                    $resource.Tags = New-Object 'System.Collections.Generic.Dictionary[String,String]'
                }
                $setTags = $FALSE
                foreach ($resourceGroupTag in $resourceGroup.Tags.GetEnumerator()) {
                    if (-NOT(($resource.Tags.ContainsKey($resourceGroupTag.key)) -AND ($resourceGroup.Tags[$resourceGroupTag.key].Equals($resource.Tags[$resourceGroupTag.key])))) {
                        $setTags = $TRUE
                    }                
                }
                if ($setTags) {
                    Write-Output ("[SET-TAGS!] ResourceGroup '{0}' and his child Resource '{1}' of type '{2}' have missing Tags. Setting resource tags!" -f $resourceGroup.ResourceGroupName, $resource.Name, $resource.Type)
                    [hashtable] $resourceTagsInLowerCase = @{}
                    foreach ($resourceTag in $resource.Tags.GetEnumerator()) {                        
                        $resourceTagsInLowerCase.Add($resourceTag.key.ToLower(), $resourceTag.key)
                    }
                    foreach ($resourceGroupTag in $resourceGroup.Tags.GetEnumerator()) {
                        if ($resourceTagsInLowerCase.ContainsKey($resourceGroupTag.key.ToLower())) {
                            ($resource.Tags.Remove($resourceTagsInLowerCase[$resourceGroupTag.key])) | out-null
                        }
                        ($resource.Tags.Add($resourceGroupTag.key, $resourceGroupTag.value)) | out-null
                    }
                    (Set-AzureRmResource -Tag $resource.Tags -ResourceId $resource.ResourceId -Force) | out-null
                }
                else {
                    if ($VERBOSE) {
                        Write-Output ("[SAME-TAGS] ResourceGroup '{0}' and his child Resource '{1}' have the same Tags. Nothing todo!" -f $resourceGroup.ResourceGroupName, $resource.Name)
                    }
                }
            }
            else {
                if ($VERBOSE) {
                    Write-Output ("[SKIP-TAGS] ResourceGroup '{0}' and his child Resource '{1}' of type '{2}' is configured to skip. Nothing todo!" -f $resourceGroup.ResourceGroupName, $resource.Name, $resource.Type)
                }
            }
        }
    }
    else {
        Write-Output ("[ NO-TAGS ] ResourceGroup '{0}' has no Tags defined. Nothing todo!" -f $resourceGroup.ResourceGroupName)
    }
}
