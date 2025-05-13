# Creating Log File
Start-Transcript -Path C:\Temp\ArcInstallScript.log

# Azure Login 

az login --service-principal -u $Env:appId -p $Env:password --tenant $Env:tenantId
az account set -s $Env:SubscriptionId

# Configure hosts file for Private link endpoints resolution
Write-Host "`n🔧 Mise à jour du fichier hosts avec toutes les entrées Private DNS nécessaires à Azure Arc..."

$file = "C:\Windows\System32\drivers\etc\hosts"
$hostfile = Get-Content $file

# Liste des suffixes DNS utiles à injecter
$dnsSuffixes = @(
  "monitor.azure.com",
  "guestconfiguration.azure.com",
  "his.arc.azure.com",
  "dp.kubernetesconfiguration.azure.com"
)

# Récupération complète des DNS zone groups du PE
$dnsZoneGroups = az network private-endpoint dns-zone-group list `
  --endpoint-name $Env:PEname `
  --resource-group $Env:resourceGroup `
  --output json | ConvertFrom-Json

foreach ($zoneGroup in $dnsZoneGroups) {
  foreach ($zone in $zoneGroup.privateDnsZoneConfigs) {
    foreach ($record in $zone.recordSets) {
      foreach ($suffix in $dnsSuffixes) {
        if ($record.fqdn -like "*$suffix") {
          $fqdn = $record.fqdn.Trim()
          $ip = $record.ipAddresses[0]
          if ($fqdn -and $ip -and -not ($hostfile -match $fqdn)) {
            Write-Host "➕ Ajout : $ip $fqdn"
            $hostfile += "$ip $fqdn"
          }
        }
      }
    }
  }
}

# Enregistrement final dans le fichier hosts
Set-Content -Path $file -Value $hostfile -Force




## Configure the OS to allow Azure Arc Agent to be deploy on an Azure VM

Write-Host "Configure the OS to allow Azure Arc connected machine agent to be deploy on an Azure VM"
Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
Stop-Service WindowsAzureGuestAgent -Force -Verbose
New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254 

## Azure Arc agent Installation

Write-Host "Onboarding to Azure Arc"
# Download the package
function download() {$ProgressPreference="SilentlyContinue"; Invoke-WebRequest -Uri https://aka.ms/AzureConnectedMachineAgent -OutFile AzureConnectedMachineAgent.msi}
download


# Install the package
msiexec /i AzureConnectedMachineAgent.msi /l*v installationlog.txt /qn | Out-String

# Run connect command
& "$Env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
--resource-group $Env:resourceGroup `
--tenant-id $Env:tenantId `
--location $Env:Location `
--subscription-id $Env:SubscriptionId `
--cloud "AzureCloud" `
--private-link-scope $Env:PLscope `
--service-principal-id $Env:appId `
--service-principal-secret $Env:password `
--correlation-id "e5089a61-0238-48fd-91ef-f67846168001" `
--tags "Project=jumpstart_azure_arc_servers" 

# Remove schedule task
Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$False
Stop-Process -Name powershell -Force
