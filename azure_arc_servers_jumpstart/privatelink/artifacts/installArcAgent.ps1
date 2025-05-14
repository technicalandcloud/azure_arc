# Creating Log File
Start-Transcript -Path C:\Temp\ArcInstallScript.log

# Azure Login 
az login --service-principal -u $Env:appId -p $Env:password --tenant $Env:tenantId
az account set -s $Env:SubscriptionId

# Configure hosts file for Private link endpoints resolution
# Configuration
$file = "C:\Windows\System32\drivers\etc\hosts"
$ArcPe = "Arc-PE"
$ArcRG = "arc-azure-rg"
$AMPLSPe = "ampls-pe"
$AMPLSRG = "arc-azure-rg"

# Récupération des enregistrements DNS - Arc PE
try {
    $arcDnsData = az network private-endpoint dns-zone-group list `
        --endpoint-name $ArcPe `
        --resource-group $ArcRG `
        -o json | ConvertFrom-Json

    $gisfqdn   = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[0].fqdn.Replace('.privatelink','')
    $gisIP     = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]

    $hisfqdn   = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[1].fqdn.Replace('.privatelink','')
    $hisIP     = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[1].ipAddresses[0]

    $agentfqdn = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[0].fqdn.Replace('.privatelink','')
    $agentIp   = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[0].ipAddresses[0]

    $gasfqdn   = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[1].fqdn.Replace('.privatelink','')
    $gasIp     = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[1].ipAddresses[0]

    $dpfqdn    = $arcDnsData[0].privateDnsZoneConfigs[2].recordSets[0].fqdn.Replace('.privatelink','')
    $dpIp      = $arcDnsData[0].privateDnsZoneConfigs[2].recordSets[0].ipAddresses[0]
} catch {
    Write-Host "❌ Erreur lors du traitement de $ArcPe : $_"
}

# Récupération des enregistrements DNS - AMPLS PE
try {
    $amplsDnsData = az network private-endpoint dns-zone-group list `
        --endpoint-name $AMPLSPe `
        --resource-group $AMPLSRG `
        -o json | ConvertFrom-Json

    # Exemple avec les deux premiers enregistrements
    $ampls1fqdn = $amplsDnsData[0].privateDnsZoneConfigs[0].recordSets[0].fqdn.Replace('.privatelink','')
    $ampls1ip   = $amplsDnsData[0].privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]

    $ampls2fqdn = $amplsDnsData[0].privateDnsZoneConfigs[0].recordSets[1].fqdn.Replace('.privatelink','')
    $ampls2ip   = $amplsDnsData[0].privateDnsZoneConfigs[0].recordSets[1].ipAddresses[0]
} catch {
    Write-Host "❌ Erreur lors du traitement de $AMPLSPe : $_"
}

# Mise à jour du fichier hosts
try {
    $hostfile = Get-Content $file

    # Arc PE
    $hostfile += "$gisIP $gisfqdn"
    $hostfile += "$hisIP $hisfqdn"
    $hostfile += "$agentIp $agentfqdn"
    $hostfile += "$gasIp $gasfqdn"
    $hostfile += "$dpIp $dpfqdn"

    # AMPLS PE
    $hostfile += "$ampls1ip $ampls1fqdn"
    $hostfile += "$ampls2ip $ampls2fqdn"

    Set-Content -Path $file -Value $hostfile -Force
    Write-Host "✅ Fichier hosts mis à jour."
} catch {
    Write-Host "❌ Erreur lors de la mise à jour du fichier hosts : $_"
}

# Préparer la VM
Write-Host "🛠️ Configuration de la VM pour Azure Arc"
Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
Stop-Service WindowsAzureGuestAgent -Force -Verbose
New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254 

# Télécharger l’agent Azure Arc
Write-Host "📦 Téléchargement de l’agent Azure Arc"
function download() {
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -Uri https://aka.ms/AzureConnectedMachineAgent -OutFile AzureConnectedMachineAgent.msi
}
download

# Installer l’agent
msiexec /i AzureConnectedMachineAgent.msi /l*v installationlog.txt /qn | Out-String

# Connecter la machine à Azure Arc
Write-Host "🔗 Connexion à Azure Arc"
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

# Nettoyage
try {
    Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$False -ErrorAction Stop
    Write-Host "🧹 Tâche planifiée supprimée."
} catch {
    Write-Host "ℹ️ Tâche non trouvée ou déjà supprimée."
}

Stop-Process -Name powershell -Force
