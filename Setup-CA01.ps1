#Change these to your needs
$password = ConvertTo-SecureString -String "P@ssw0rd" -asPlainText -Force
$username = "administrator" 
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

#make sure to change domain credentials
$DomainPassword = ConvertTo-SecureString -String "P@ssw0rd" -asPlainText -Force
$DomainUsername = "changedomain\administrator" 
$DomainCredential = New-Object System.Management.Automation.PSCredential($DomainUsername,$DomainPassword)

#CHANGE THESE
$webname = "crl.example.com"
$VMNAME = "CA01"
$ADNAME = "ad.example.com"

#renames computer to name found within $VMNAME variable, enables rdp and sets a static ip
Invoke-Command -VMName $VMNAME -Credential $credential -ScriptBlock {
    New-NetIPAddress -IPAddress "192.168.0.16" -PrefixLength 24 -InterfaceAlias "Ethernet"
    Set-DnsClientServerAddress -ServerAddresses "192.168.0.11" -InterfaceAlias "Ethernet"
    Rename-Computer -NewName $VMNAME
    Set-Itemproperty -path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\" -Name 'AutoAdminLogon' -value "0"
    Set-Itemproperty -path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\" -Name 'DefaultUserName' -value $null
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server'-name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    restart-computer -Force 
}

#Join the computer to your AD domain
Invoke-Command -VMName $VMNAME -Credential $credential -ScriptBlock {
    $DomainPassword = ConvertTo-SecureString -String "P@ssw0rd" -asPlainText -Force
    $DomainUsername = "administrator" 
    $DomainCredential = New-Object System.Management.Automation.PSCredential($DomainUsername,$DomainPassword)
    Add-Computer -DomainName $ADNAME -Credential $DomainCredential
    Restart-Computer -Force
}
#Install addcs
Invoke-Command -VMName $VMNAME -Credential $DomainCredential -ScriptBlock {
    Get-WindowsFeature AD-Certificate, Web-Server | Install-WindowsFeature -IncludeManagementTools
    Install-AdcsCertificationAuthority -CAType EnterpriseRootCa -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -KeyLength 2048 -HashAlgorithmName SHA256 -ValidityPeriod Years  -ValidityPeriodUnits 3 -force
    mkdir C:\CRL #to avoid conflicts when setting permissions
    New-WebSite -Name $webname -Port 80 -HostHeader $webname -PhysicalPath "C:\CRL"
    Set-WebConfigurationProperty -filter system.webserver/security/requestFiltering -name allowDoubleEscaping -value True -PSPath IIS:\sites\$webname
    Set-WebConfigurationProperty -Filter system.webserver/directoryBrowse -Name enabled -Value true -PSPath IIS:\Sites\$webname
    Remove-CACrlDistributionPoint -Uri "http://<ServerDNSName>/CertEnroll/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -Force
    Remove-CACrlDistributionPoint -Uri "file://<ServerDNSName>/CertEnroll/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -Force
    Add-CACRLDistributionPoint -Uri "http://$webname/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl" -AddToCertificateCdp -AddToFreshestCrl -Force
    Add-CACRLDistributionPoint -Uri "file://C:\crl\<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl" -PublishDeltaToServer -PublishToServer -Force
    certutil -setreg CACRLPeriod Years
    certutil -setreg CACRLPeriodUnits 20
    Certutil -setreg CAValidityPeriodUnits 10
    Certutil -setreg CAValidityPeriod "Years"
    Write-Host "AD-CERTIFICATE & IIS SERVER SITE INSTALLED AND CONFIGURED" -ForegroundColor Green
    Write-Host "Dont forget to publish crls" -ForegroundColor Red
    Restart-Computer -Force
}
