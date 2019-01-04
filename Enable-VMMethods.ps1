

#Credits to @lamw (virtuallyGhetto) for the mob api https://www.virtuallyghetto.com/2016/07/how-to-easily-disable-vmotion-cross-vcenter-vmotion-for-a-particular-virtual-machine.html#comment-55046
#Credits to @cl for parsing vmware-session-nonce via Powershell

function Enable-VMMethods {
    param (
        $vCenter,
        [int]$vlanId,
        $Username,
        $Password,
        $dvSwitch,
        $EnableMethod
    )

    #prepare credentials
    $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($Username, $secpasswd)

    # vSphere MOB URL to private enableMethods
    $mob_url = "https://$vCenter/mob/?moid=AuthorizationManager&method=enableMethods"

# Ingore SSL Warnings
add-type -TypeDefinition  @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    # Initial login to vSphere MOB using GET and store session using $vmware variable
    $results = Invoke-WebRequest -Uri $mob_url -SessionVariable vmware -Credential $credential -Method GET

    #Login to vCenter to get VM info
    Connect-VIServer $vCenter -Credential $credential

    # Extract hidden vmware-session-nonce which must be included in future requests to prevent CSRF error
    # Credit to https://blog.netnerds.net/2013/07/use-powershell-to-keep-a-cookiejar-and-post-to-a-web-form/ for parsing vmware-session-nonce via Powershell
    if($results.StatusCode -eq 200) {
        $null = $results -match 'name="vmware-session-nonce" type="hidden" value="?([^\s^"]+)"'
        $sessionnonce = $matches[1]
    } else {
        Write-host "Failed to login to vSphere MOB"
        exit 1
    }

    #Get vlan info and vm moref IDs
    $vlan = (Get-VDPortgroup -VDSwitch $dvSwitch).where{$_.name -match $vlanId}
    $VMs = $vlan.extensionData.vm.value

    foreach ($vm in $VMs) {
        # The POST data payload must include the vmware-session-nonce variable + URL-encoded
        $body = @"
vmware-session-nonce=$sessionnonce&entity=%3Centity+type%3D%22ManagedEntity%22+xsi%3Atype%3D%22ManagedObjectReference%22%3E$vm%3C%2Fentity%3E%0D%0A&method=%3Cmethod%3E$EnableMethod%3C%2Fmethod%3E
"@

        # Second request using a POST and specifying our session from initial login + body request
        $results = Invoke-WebRequest -Uri $mob_url -WebSession $vmware -Method POST -Body $body
    }

    # Logout out of vSphere MOB
    $mob_logout_url = "https://$vCenter/mob/logout"
    Invoke-WebRequest -Uri $mob_logout_url -WebSession $vmware -Method GET

}

Enable-VMMethods -vCenter 'vc01.url.ext' -vlanId '1000' -Username 'user@domain.ext' -Password '********' -dvSwitch 'dvSwitch' -EnableMethod 'Destroy_Task'

