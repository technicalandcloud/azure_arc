# Creating Log File
Start-Transcript -Path C:\Temp\ArcInstallScript.log

# Azure Login 
az login --service-principal -u $Env:appId -p $Env:password --tenant $Env:tenantId
az account set -s $Env:SubscriptionId

# Configure hosts file for Private link endpoints resolution
$file = "C:\Windows\System32\drivers\etc\hosts"
$hostfile = Get-Content $file

$privateEndpoints = @(
    @{ name = $Env:PEname; label = "Arc-PE" },
    @{ name = $Env:AMPLS_PEname; label = "AMPLS-PE" }
)

foreach ($pe in $privateEndpoints) {
    if (-not $pe.name) { continue }

    Write-Host "`n🔍 Traitement du Private Endpoint : $($pe.label)"

    try {
        $dnsZoneGroups = az network private-endpoint dns-zone-group list `
            --endpoint-name $pe.name `
            --resource-group $Env:resourceGroup `
            -o json | ConvertFrom-Json

        foreach ($zone in $dnsZoneGroups[0].privateDnsZoneConfigs) {
            foreach ($record in $zone.recordSets) {
                $fqdn = $record.fqdn.Replace('.privatelink', '').Trim()
                $ip = $record.ipAddresses[0]

                if ($fqdn -and $ip -and -not ($hostfile -match [regex]::Escape($fqdn))) {
                    Write-Host "➕ Ajout : $ip $fqdn"
                    $hostfile += "$ip $fqdn"
                }
            }
        }
    } catch {
        Write-Host "⚠️ Erreur sur $($pe.label) : $_"
    }
}

Set-Content -Path $file -Value $hostfile -Force
Write-Host "✅ Fichier hosts mis à jour."

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
