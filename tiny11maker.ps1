<#
.SYNOPSIS
    Scripts to build a trimmed-down Windows 11 image with Visual C++ Runtime auto-installer (RunOnce Method).

.DESCRIPTION
    This is a script created to automate the build of a streamlined Windows 11 image, similar to tiny10.
    My main goal is to use only Microsoft utilities like DISM, and no utilities from external sources.
    The only executable included is oscdimg.exe, which is provided in the Windows ADK and it is used to create bootable ISO images.

.PARAMETER ISO
    Drive letter given to the mounted iso (eg: E)

.PARAMETER SCRATCH
    Drive letter of the desired scratch disk (eg: D)

.EXAMPLE
    .\tiny11maker.ps1 E D
    .\tiny11maker.ps1 -ISO E -SCRATCH D
    .\tiny11maker.ps1 -SCRATCH D -ISO E
    .\tiny11maker.ps1

    *If you ordinal parameters the first one must be the mounted iso. The second is the scratch drive.
    prefer the use of full named parameter (eg: "-ISO") as you can put in the order you want.

.NOTES
    Auteur: ntdevlabs
    Date: 09-07-25
#>

#---------[ Parameters ]---------#
param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH
)

if (-not $SCRATCH) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $SCRATCH + ":"
}

#---------[ Functions ]---------#
function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
        Write-Output "Set registry value: $path\$name"
    } catch {
        Write-Output "Error setting registry value: $_"
    }
}

function Remove-RegistryValue {
    param (
		[string]$path
	)
	try {
		& 'reg' 'delete' $path '/f' | Out-Null
		Write-Output "Removed registry value: $path"
	} catch {
		Write-Output "Error removing registry value: $_"
	}
}

#---------[ Execution ]---------#
# Check if PowerShell execution is restricted
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Output "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Output "The script cannot be run without changing the execution policy. Exiting..."
        exit
    }
}

# Check and run the script as admin if required
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Output "Restarting Tiny11 image creator as admin in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

# Start the transcript and prepare the window
Start-Transcript -Path "$PSScriptRoot\tiny11_$(get-date -f yyyyMMdd_HHmms).log"

$Host.UI.RawUI.WindowTitle = "Tiny11 image creator"
Clear-Host
Write-Output "Welcome to the tiny11 image creator! Release: 09-07-25"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
do {
    if (-not $ISO) {
        $DriveLetter = Read-Host "Please enter the drive letter for the Windows 11 image"
    } else {
        $DriveLetter = $ISO
    }
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "Drive letter set to $DriveLetter"
    } else {
        Write-Output "Invalid drive letter. Please enter a letter between C and Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Output "Found install.esd, converting to install.wim..."
        Get-WindowsImage -ImagePath $DriveLetter\sources\install.esd
        $index = Read-Host "Please enter the image index"
        Write-Output ' '
        Write-Output 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath $ScratchDisk\tiny11\sources\install.wim -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "Can't find Windows OS Installation files in the specified Drive Letter.."
        Write-Output "Please enter the correct DVD Drive Letter.."
        exit
    }
}

Write-Output "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$ScratchDisk\tiny11\sources\install.esd" > $null 2>&1
Write-Output "Copy complete!"
Start-Sleep -Seconds 2
Clear-Host
Write-Output "Getting image information:"
$ImagesIndex = (Get-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim).ImageIndex
while ($ImagesIndex -notcontains $index) {
    Get-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim
    $index = Read-Host "Please enter the image index"
}
Write-Output "Mounting Windows image. This may take a while."
$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
	Write-Error "$wimFilePath not found"
}
New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim -Index $index -Path $ScratchDisk\scratchdir

$imageIntl = & dism /English /Get-Intl "/Image:$($ScratchDisk)\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($languageLine) {
    $languageCode = $Matches[1]
    Write-Output "Default system UI language code: $languageCode"
} else {
    Write-Output "Default system UI language code not found."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($ScratchDisk)\tiny11\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        if ($architecture -eq 'x64') {
            $architecture = 'amd64'
        }
        Write-Output "Architecture: $architecture"
        break
    }
}

if (-not $architecture) {
    Write-Output "Architecture information not found."
}

Write-Output "Mounting complete! Performing removal of applications..."

$packages = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'PackageName : (.*)') {
            $matches[1]
        }
    }

$packagePrefixes = 'AppUp.IntelManagementandSecurityStatus',
'Clipchamp.Clipchamp', 
'DolbyLaboratories.DolbyAccess',
'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
'Microsoft.ApplicationCompatibilityEnhancements',
'Microsoft.BingNews',
'Microsoft.BingSearch',
'Microsoft.BingWeather',
'Microsoft.Copilot',
'Microsoft.CrossDeviceExperienceHost',
'Microsoft.Windows.CrossDevice',
'MicrosoftWindows.CrossDevice',
'Microsoft.GamingApp',
'Microsoft.GamingServices',
'Microsoft.GetHelp',
'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer',
'Microsoft.MicrosoftOfficeHub',
'Microsoft.MicrosoftSolitaireCollection',
'Microsoft.MicrosoftStickyNotes',
'Microsoft.MixedReality.Portal',
'Microsoft.MSPaint',
'Microsoft.Office.OneNote',
'Microsoft.OfficePushNotificationUtility',
'Microsoft.OutlookForWindows',
'Microsoft.Paint',
'Microsoft.People',
'Microsoft.PowerAutomateDesktop',
'Microsoft.SkypeApp',
'Microsoft.StartExperiencesApp',
'Microsoft.Todos',
'Microsoft.Wallet',
'Microsoft.Windows.DevHome',
'Microsoft.Windows.Copilot',
'Microsoft.Windows.Teams',
'Microsoft.WindowsAlarms',
'Microsoft.WindowsCamera',
'microsoft.windowscommunicationsapps',
'Microsoft.WindowsFeedbackHub',
'Microsoft.WindowsMaps',
'Microsoft.WindowsSoundRecorder',
'Microsoft.WindowsTerminal',
'Microsoft.Xbox.TCUI',
'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay',
'Microsoft.XboxGamingOverlay',
'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay',
'Microsoft.YourPhone',
'Microsoft.ZuneMusic',
'Microsoft.ZuneVideo',
'MicrosoftCorporationII.MicrosoftFamily',
'MicrosoftCorporationII.QuickAssist',
'MSTeams',
'MicrosoftTeams', 
'Microsoft.WindowsTerminal',
'Microsoft.549981C3F5F10',
'Microsoft.WindowsCalculator',
'Microsoft.Windows.Photos',
'Microsoft.ScreenSketch',
'Microsoft.WindowsStore',
'Microsoft.StorePurchaseApp',
'Microsoft.Windows.VoiceAccess'

$packagesToRemove = $packages | Where-Object {
    $packageName = $_
    $packagePrefixes -contains ($packagePrefixes | Where-Object { $packageName -like "*$_*" })
}
foreach ($package in $packagesToRemove) {
    & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}

# -------------------------------------------------------------
# REMOVE SPECIFIC SYSTEM PACKAGES (PAYLOAD COMPONENTS)
# -------------------------------------------------------------
Write-Output "Removing Specific System Component Payloads (CrossDevice, Xbox, GameOverlay, GamingUI, CaptureService)..."
$systemPackages = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Get-Packages' |
    ForEach-Object {
        if ($_ -match 'Package Identity : (.*(?:crossdevice-webcam|Xbox|GamingOverlay|GameOverlay|gaming-ui|captureservice).*)') {
            $matches[1].Trim()
        }
    }
foreach ($sysPkg in $systemPackages) {
    & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-Package' "/PackageName:$sysPkg"
}

# -------------------------------------------------------------
# REMOVE OPTIONAL FEATURES & CAPABILITIES (TINY11-RECIPE: XPS, LEGACY, WORKFOLDERS)
# -------------------------------------------------------------
Write-Output "Removing Optional Capabilities (XPS, WordPad, Steps Recorder, Math Recognizer, WorkFolders)..."
$capabilities = @('XPS.Viewer~~~~0.0.1.0', 'Microsoft.Windows.WordPad~~~~0.0.1.0', 'App.StepsRecorder~~~~0.0.1.0', 'MathRecognizer~~~~0.0.1.0')
foreach ($cap in $capabilities) {
    & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-Capability' "/CapabilityName:$cap"
}
& 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Disable-Feature' '/FeatureName:WorkFolders-Client' '/Remove'
# -------------------------------------------------------------

# -------------------------------------------------------------
# NUCLEAR OPTION: FORCE DELETE WINSXS COMPONENT PAYLOADS & PHYSICAL FILES
# -------------------------------------------------------------
Write-Output "Nuking Game Bar, Xbox, Edge, OneDrive, and WinSxS Component Payloads..."

# 1. Hancurkan Component Payload Game Bar langsung dari akar WinSxS (amd64 & wow64)
$winSxsPaths = @(
    "$ScratchDisk\scratchdir\Windows\WinSxS\*windows-gaming-ui-gamebar-component*",
    "$ScratchDisk\scratchdir\Windows\WinSxS\*captureservice*",
    "$ScratchDisk\scratchdir\Windows\WinSxS\*xboxgamingoverlay*"
)

foreach ($path in $winSxsPaths) {
    $foundSxS = Get-Item -Path $path -ErrorAction SilentlyContinue
    foreach ($sxsFolder in $foundSxS) {
        Write-Output "Destroying WinSxS Payload: $($sxsFolder.Name)"
        & 'takeown' '/f' $sxsFolder.FullName '/r' '/d' 'Y' | Out-Null
        & 'icacls' $sxsFolder.FullName '/grant' "$($adminGroup.Value):(F)" '/t' '/c' '/q' | Out-Null
        Remove-Item -Path $sxsFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# 2. Hancurkan Folder Aplikasi
$nukePaths = @(
    "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge",
    "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate",
    "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore",
    "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeWebView",
    "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview",
    "$ScratchDisk\scratchdir\Program Files\WindowsApps\Microsoft.XboxGamingOverlay*",
    "$ScratchDisk\scratchdir\Program Files\WindowsApps\Microsoft.XboxGameOverlay*",
    "$ScratchDisk\scratchdir\Program Files\WindowsApps\Microsoft.GamingApp*",
    "$ScratchDisk\scratchdir\Windows\SystemApps\Microsoft.XboxGameCallableUI*"
)

foreach ($path in $nukePaths) {
    $foundFolders = Get-Item -Path $path -ErrorAction SilentlyContinue
    foreach ($folder in $foundFolders) {
        Write-Output "Force Deleting Folder: $($folder.FullName)"
        & 'takeown' '/f' $folder.FullName '/r' '/d' 'Y' | Out-Null
        & 'icacls' $folder.FullName '/grant' "$($adminGroup.Value):(F)" '/t' '/c' '/q' | Out-Null
        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# 3. Hancurkan File Sistem Eksekusi
$sysFiles = @(
    "OneDriveSetup.exe", 
    "bcastdvr.exe", 
    "GameBarPresenceWriter.exe", 
    "CaptureService.dll"
)

foreach ($file in $sysFiles) {
    $target = "$ScratchDisk\scratchdir\Windows\System32\$file"
    if (Test-Path $target) {
        Write-Output "Force Deleting File: $file"
        & 'takeown' '/f' $target | Out-Null
        & 'icacls' $target '/grant' "$($adminGroup.Value):(F)" '/q' | Out-Null
        Remove-Item -Path $target -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
Write-Output "Removal complete!"
Start-Sleep -Seconds 2
Clear-Host

# -------------------------------------------------------------
# REGISTRY TWEAKS
# -------------------------------------------------------------
Write-Output "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM | Out-Null
Write-Output "Bypassing system requirements(on the system image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "Disabling Sponsored Apps:"
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'
Write-Output "Enabling Local Accounts on OOBE:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'

Write-Output "Disabling Reserved Storage:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
Write-Output "Disabling BitLocker Device Encryption"
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
Write-Output "Disabling Chat icon:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
Write-Output "Removing Edge related registries"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView"
Write-Output "Disabling OneDrive folder backup"
Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
Write-Output "Disabling Telemetry:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
## Prevents installation of DevHome and Outlook
Write-Output "Prevents installation of DevHome and Outlook:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
Write-Output "Disabling Copilot"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
Write-Output "Prevents installation of Teams:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
Write-Output "Prevent installation of New Outlook":
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

# ==============================================================
# FSOS-X PLAYBOOK TWEAKS & CUSTOM SETTINGS START
# ==============================================================
Write-Output "Applying FSOS-X Playbook Tweaks, Recipe JSON, & User Custom Settings..."

# [Phase 2 & 3] Security Mitigations, Privacy, SmartScreen, Delivery Optimization
# 1. Disable Security Mitigations (Spectre/Meltdown)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Session Manager\Memory Management' 'FeatureSettingsOverride' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Session Manager\Memory Management' 'FeatureSettingsOverrideMask' 'REG_DWORD' '3'
# 2. Disable SmartScreen
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 'REG_DWORD' '0'
# 3. Disable Delivery Optimization (Phase 6)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\DoSvc' 'Start' 'REG_DWORD' '4'
# 4. Disable Cortana (Phase 3)
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 'REG_DWORD' '0'
# 5. Disable Cloud Sync & Activity History (Phase 3)
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 'REG_DWORD' '0'

# [Phase 4] Gaming Optimized Tweaks (Input Lag, Network, Power)
# 6. Disable Hibernation
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Power' 'HibernateEnabled' 'REG_DWORD' '0'
# 7. Disable Network Throttling for Gaming
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 'REG_DWORD' '4294967295'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 'REG_DWORD' '0'
# 8. Optimize Win32PrioritySeparation
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\PriorityControl' 'Win32PrioritySeparation' 'REG_DWORD' '38'
# 9. Reduce Mouse & Keyboard Data Queue Size (Lower Input Lag)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\mouclass\Parameters' 'MouseDataQueueSize' 'REG_DWORD' '20'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' 'REG_DWORD' '20'

# [Phase 5] UI & Visuals (Dark Mode, Transparency, Animations)
# 10. Enable Dark Mode
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 'REG_DWORD' '0'
# 11. Disable Transparency
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 'REG_DWORD' '0'
# 12. Best Performance Visuals (Disable Animations)
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 'REG_DWORD' '2'

# [User Custom Requests] Specific Services, Accessibilities & Compatibility
# 13. Disable Printing (Print Spooler)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\Spooler' 'Start' 'REG_DWORD' '4'
# 14. Disable Wi-Fi (WLAN AutoConfig)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\WlanSvc' 'Start' 'REG_DWORD' '4'
# 15. Disable Storage Sense
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 'REG_DWORD' '0'
# 16. Disable Location Services
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\lfsvc' 'Start' 'REG_DWORD' '4'

# 17. Disable Auto Update Driver
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 'REG_DWORD' '0'

# 18. Disable Accessibility (Sticky Keys, Toggle Keys, Filter Keys shortcuts)
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Accessibility\StickyKeys' 'Flags' 'REG_SZ' '506'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Accessibility\ToggleKeys' 'Flags' 'REG_SZ' '58'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Accessibility\Keyboard Response' 'Flags' 'REG_SZ' '122'
# 19. Disable Weather/Widgets Taskbar Icon
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 'REG_DWORD' '0'

# 20. Disable Cross Device Experience Host / Connected Devices Platform
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\CDPSvc' 'Start' 'REG_DWORD' '4'
# 21. Disable Application Compatibility Enhancements (Program Compatibility Assistant)
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\PcaSvc' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\AeLookupSvc' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableEngine' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisablePCA' 'REG_DWORD' '1'

# 22. Disable Windows Recall / AI Data Analysis (From tiny11-recipe)
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'REG_DWORD' '1'

# 23. Remove & Disable Xbox Services, Game Bar, Capture Service (ExpertActions)
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\System\GameConfigStore' 'GameDVR_Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'REG_DWORD' '0'

Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\XblAuthManager' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\XblGameSave' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\XboxNetApiSvc' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\XboxGipSvc' 'Start' 'REG_DWORD' '4'
Remove-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\CaptureService'

# 24. Pause Windows Update (Max 2077)
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseFeatureUpdatesStartTime' 'REG_SZ' '2024-01-01T00:00:00Z'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseQualityUpdatesStartTime' 'REG_SZ' '2024-01-01T00:00:00Z'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseUpdatesStartTime' 'REG_SZ' '2024-01-01T00:00:00Z'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseFeatureUpdatesEndTime' 'REG_SZ' '2077-12-31T23:59:59Z'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseQualityUpdatesEndTime' 'REG_SZ' '2077-12-31T23:59:59Z'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseUpdatesExpiryTime' 'REG_SZ' '2077-12-31T23:59:59Z'
# ==============================================================
# FSOS-X PLAYBOOK TWEAKS & CUSTOM SETTINGS END
# ==============================================================

# ==============================================================
# VISUAL RUNTIME AUTO-INSTALLER INTEGRATION (ALTERNATIVE 1 - BATCH SCRIPT)
# ==============================================================
Write-Output "Configuring Visual Runtime auto-installer via RunOnce (Batch Method)..."

# Mengarahkan pencarian ke folder VCRedist dan mencari file spesifik
$vcFolder = "$PSScriptRoot\VCRedist"
$batFile = Get-ChildItem -Path $vcFolder -Filter "install_all_vcredist.bat" -ErrorAction SilentlyContinue | Select-Object -First 1

if ((Test-Path $vcFolder) -and $batFile) {
    Write-Output "Found Visual Runtime folder and batch script: $($batFile.Name)"
    
    # Salin seluruh folder VCRedist beserta isinya ke dalam Setup Windows
    $targetFolder = "$ScratchDisk\scratchdir\Windows\Setup\VCRedist"
    Copy-Item -Path $vcFolder -Destination $targetFolder -Recurse -Force
    Write-Output "Copied VCRedist folder to C:\Windows\Setup\VCRedist inside WIM image."
    
    # Membuat script wrapper .cmd di root Windows untuk menjalankan dan membersihkan
    # Perintah 'start /wait' mencegah 'exit' pada file batch bawaan membunuh proses RunOnce
    $wrapperScript = "$ScratchDisk\scratchdir\Windows\InstallVCRuntime.cmd"
    @"
@echo off
start /wait "" "C:\Windows\Setup\VCRedist\$($batFile.Name)"
rmdir /s /q "C:\Windows\Setup\VCRedist"
del "%~f0"
"@ | Out-File -FilePath $wrapperScript -Encoding ASCII

    # Tambahkan command eksekusi wrapper ke registry RunOnce
    $runOnceCmd = "cmd.exe /c C:\Windows\InstallVCRuntime.cmd"
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'InstallVC' 'REG_SZ' $runOnceCmd
    
    Write-Output "RunOnce registry key added successfully!"
} else {
    Write-Output "------------------------------------------------------------------------"
    Write-Output "WARNING: VCRedist folder or 'install_all_vcredist.bat' not found in $PSScriptRoot\VCRedist"
    Write-Output "Please create a folder named 'VCRedist', put 'install_all_vcredist.bat' and all vcredist .exe files inside."
    Write-Output "------------------------------------------------------------------------"
}
# ==============================================================

Write-Host "Deleting scheduled task definition files..."
$tasksPath = "$ScratchDisk\scratchdir\Windows\System32\Tasks"

# Application Compatibility Appraiser & Experience (removes the entire folder completely)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience" -Recurse -Force -ErrorAction SilentlyContinue

# Customer Experience Improvement Program (removes the entire folder and all tasks within it)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue

# Chkdsk Proxy
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue

# Windows Error Reporting (QueueReporting)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
Write-Host "Task files have been deleted."
Write-Host "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null
Write-Output "Cleaning up image..."
dism.exe /Image:$ScratchDisk\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Output "Cleanup complete."
Write-Output ' '
Write-Output "Unmounting image..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
Write-Host "Exporting image..."
Dism.exe /Export-Image /SourceImageFile:"$ScratchDisk\tiny11\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$ScratchDisk\tiny11\sources\install2.wim" /Compress:recovery
Remove-Item -Path "$ScratchDisk\tiny11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny11\sources\install2.wim" -NewName "install.wim" | Out-Null
Write-Output "Windows image completed. Continuing with boot.wim."
Start-Sleep -Seconds 2
Clear-Host
Write-Output "Mounting boot image:"
$wimFilePath = "$ScratchDisk\tiny11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\boot.wim -Index 2 -Path $ScratchDisk\scratchdir
Write-Output "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM

Write-Output "Bypassing system requirements(on the setup image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "Tweaking complete!"

Write-Output "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Output "Unmounting image..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
Clear-Host
Write-Output "The tiny11 image is now completed. Proceeding with the making of the ISO..."

Write-Output "Creating ISO image..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostarchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Output "Will be using oscdimg.exe from system ADK."
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Output "ADK folder not found. Will be using bundled oscdimg.exe."
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Output "Downloading oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

        if (Test-Path $localOSCDIMGPath) {
            Write-Output "oscdimg.exe downloaded successfully."
        } else {
            Write-Error "Failed to download oscdimg.exe."
            exit 1
        }
    } else {
        Write-Output "oscdimg.exe already exists locally."
    }

    $OSCDIMG = $localOSCDIMGPath
}

& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny11\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" "$PSScriptRoot\tiny11.iso"

# Finishing up
Write-Output "Creation completed! Press any key to exit the script..."
Read-Host "Press Enter to continue"
Write-Output "Performing Cleanup..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null
Write-Output "Ejecting Iso drive"
Get-Volume -DriveLetter $DriveLetter[0] | Get-DiskImage | Dismount-DiskImage
Write-Output "Iso drive ejected"
Write-Output "Removing oscdimg.exe..."
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue

Write-Output "Cleanup check :"
if (Test-Path -Path "$ScratchDisk\tiny11") {
    Write-Output "tiny11 folder still exists. Attempting to remove it again..."
    Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\tiny11") {
        Write-Output "Failed to remove tiny11 folder."
    } else {
        Write-Output "tiny11 folder removed successfully."
    }
} else {
    Write-Output "tiny11 folder does not exist. No action needed."
}
if (Test-Path -Path "$ScratchDisk\scratchdir") {
    Write-Output "scratchdir folder still exists. Attempting to remove it again..."
    Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\scratchdir") {
        Write-Output "Failed to remove scratchdir folder."
    } else {
        Write-Output "scratchdir folder removed successfully."
    }
} else {
    Write-Output "scratchdir folder does not exist. No action needed."
}
if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
    Write-Output "oscdimg.exe still exists. Attempting to remove it again..."
    Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
        Write-Output "Failed to remove oscdimg.exe."
    } else {
        Write-Output "oscdimg.exe removed successfully."
    }
} else {
    Write-Output "oscdimg.exe does not exist. No action needed."
}

# Stop the transcript
Stop-Transcript

exit
