<#
    Name: WF-2-ODfB.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West  (using functions from o4bclientautoconfig by Jos Lieben, attribution below)
    Creative Commons Public Attribution license 4.0, non-Commercial use;
.SYNOPSIS
    Set up OneDrive for Business and migrate active Work Folders data to OneDrive 
.DESCRIPTION
    This script will migrate a Windows 10 Endpoint's User data sync settings
    from Work Folders over to OneDrive for Business.  It is targeted to silently run 
    OneDrive Setup (see note below), moves data from Work Folders to OneDrive folder via
    Robocopy /Move, and sets redirection for Known Folders.  Leverages code from 
    Jos Lieben's solution at https://www.lieben.nu/liebensraum/o4bclientautoconfig/
    Requirements: Windows 10, Powershell 5x or above
.LINK
    https://github.com/J-DubApps
    #>

###############################################################################################
#
#			WorkFolders-To-OneDrive for Business Migration v 0.4.x
#			    WF-2-ODfB.ps1
#
#	Description 
#		This script will create a Runtime script to migrate a Windows 10 Endpoint's User Work Folder
#       sync config over to OneDrive for Business.  The Runtime script silently runs OneDrive Setup,
#       automatically signs user into OneDrive (non-MFA, Hybrid Azure AD users only - see note below), 
#       and sets redirection for  Windows Known Folders.  It will also MOVE data from a user's 
#       previous Work Folders Root path over to OneDrive folder via a Robocopy Wrapper function.
#       
#       This Deployment script, and the Runtime sub-script it triggers, can be run without Admin rights;
#       however, if you wish to have the Runtime script perform additional scheduled runs
#       you must run this script itself once with Admin rights (deployed via MECM etc) *or* 
#       you could grant Scheduled Task creation rights to your Windows endpoint users
#       (see notes at end of this documentation section).  
#
#       When run non-Admin rights, the script creates migration tasks to run as a 
#       local Logon Script via the HKCU "Run" key in the registry.
#
#       Scheduled Tasks and Admin Rights are NOT a requirement for this or the Runtime script to 
#       perform a basic OneDrive for Business client install, Known Folder redirection, and Work 
#       Folder data migration.
#
#       For optimal UX the script is designed to run HIDDEN and silent (no PS window is seen by the user), 
#       and can re-run multiple times via Scheduled Tasks (ideal for multiple-user Endpoints, or hybrid 
#       Remote Workers' PC endpoints where interruptions may occur). 
# 
#
#    BACKGROUND: While both OneDrive For Business & Work Folder sync can *both* be used at the  
#       same time, this script strictly disables Work Folder sync during its run. As most 
#       organizations move to Hybrid Management and/or Intune/BYOD scenarios, moving away from
#       on-prem Work Folders is primarily why this script exists.
#
#       During execution, script removes Work Folder redirection (if present) and removes
#       Work Folder sync server settings (this would be in addition to any GPO doing the same).  
#       The script then installs OneDrive, migrates Work Folder data, and redirects Known Folders. 
#		
#	Usage
#		Script has no required Parameters but does have TWO REQUIRED variables you must edit below, for your 
#       O365 Tenant's OneDrive settings. These need to be set before running tests & deployment.
#
#       During its run, this script actually doesn't DO any Data Migration or OneDrive lanuching, it leaves 
#       that to a separate Runtime script that it will stage under C:\ProgramData within a WF-2-ODfB folder.  
#
#       This Script also has a several key OPTIONAL variables you set, including: 
#
#       enableFilesOnDemand - True/False (Default False)
#       enableDataMigration - True/False (Default True)
#       redirectFoldersToOnedriveForBusiness - True/False (Default True)
#
#       Script can ONLY enable FilesOnDemand variable (if set to True) by running once with Admin rights, 
#       *or* if you grant endpoint users rights to modify HKLM:\Software\Policies\Microsoft\Onedrive.  
#       If your deployment scenario is direct to non-Admin users, I recommend ignoring this setting.  If you 
#       need FilesOnDemand mode to be set, you should consider deploying this script onnce to run 
#       with Admin rights via MECM or other deployment tool. Alternatively, you could enable this feature 
#       by publishing the needed registry setting via InTune or GPO (in which case you should leave 
#       the enableFilesOnDemand variable set to 'false').
#       
#       For all OneDrive environment config items, can be run ONCE using Admin rights, which can be
#       accomplished via InTune or GPO Computer Logon script using "-executionpolicy ByPass" PowerShell.exe 
#       script parameters.  You can also sign the script (not in-scope of this documentation).  
#       Script can also first triggered via MECM, existing Logon Script, or manually.
#         
#       The Runtime script this script deploys will run OneDriveSetup.exe /silent from either the Windows 
#       bundled version of OneDrive under %windir$\SysWOW64 folder, or the C:\Program Files per-machine install 
#       of the standalone version of OneDrive.  It places OneDrive.exe startup into HKCU...Run in the registry, 
#       and then can move all Work Folders contents to the configured OneDrive path under the 
#       user's profile.
#
#
#       NOTE1: To leverage automatic sign-in for OneDrive, your Windows Endpoints must be configured 
#           for Hybrid Azure AD join.  Otherwise your users will have to Authenticate to OneDrive the first time.
#
#           More info here: https://docs.microsoft.com/en-us/azure/active-directory/devices/concept-azure-ad-join-hybrid
#                           https://docs.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-plan  
#
#       NOTE2: If MFA is enabled automatic sign-in for OneDrive will not occur, and the only 
#       ‘silent’ behavior of this Migration Script will be the redirection (affter the user finishes sign-in to 
#       OneDrive) and data migration.
#       
#       NOTE3: Additional background migration runs are rarely-needed, but if you want this the background
#       run feature this this script will need to either be run once as with Admin Rights, or you must grant 
#       your non-Admin users the right to create Scheduled Tasks. 
#       By default Non-Admin user accounts do NOT have the ability to manage Scheduled Tasks, and your environment 
#       Policies may require this to not be changed.  
#       For more information on granting non-Admin users Scheduled Task management rights: 
#       https://www.wincert.net/windows-server/how-to-grant-non-admin-users-permissions-for-managing-scheduled-tasks/ 
#
#       Again: this script does NOT require having itself run as a Scheduled Tasks to be successful, 
#       it simply offers the ability to be re-run as a background process so that the user does not need to log out
#       and back in to get the migration steps done.  
#
# 	LICENSE: Creative Commons Public Attribution license 4.0, non-Commercial use.
#
#  You are free to make any changes to your own copy of this script, provided you give Attribution and agree
#  you cannot hold the original author responsible for any issues resulting from this script.
#
#   Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made.
#   You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use. 
#
#  I welcome forks or pulls and will be happy to help improve the script for anyone if I have the time, but please bear
#  in mind that 50% of this script utilizes functions in PS Script O4BClientAutoConfig.ps1 written by Jos Lieben
#  @ https://www.lieben.nu/liebensraum/o4bclientautoconfig/ and any changes to those parts of my script also require a 
#  a communication to that original author.  Those parts of this script are marked with "Jos Lieben Code".  
#  I only utilize this code via my own commercial license purchased from Jos directly.  
#   
#   Until you purchase a similar license, your use of this code is limited to testing, labbing, or other non-commercial use.
#
#   Please feel to contact me at: jdub.writes.some.code(at)gmail(dot)com if you have any questions about the code.
#   Contact Jos Lieben at: https://www.lieben.nu/ for licensing the o4bclientautoconfig section of this script for commercial use.
#
#  TL;DR*
#
# 1. Anyone can copy, modify and use this software non-commercially.
# 2. You have to include the license stated here, and give attribution when makiing any changes to the code.
# 3. You can use this software privately only, for non-commercial use.  Commercial use will require purchasing a license from Jos Lieben.
# 4. You are NOT authorized to use this software for commercial purposes without first purchasing an unlimited license from Jos Lieben.
# 5. If you dare build a business engagement from this code, you risk legal action.
# 6. If you modify it, you have to indicate changes made to the code.
# 7. Any modifications of this code base MUST be distributed with the same license, GPLv3.
# 8. This software is provided without warranty.
# 9. The software authors or license can not be held liable for any damages resulting from use of the software.
#
###############################################################################################
#
# Mentions / articles used:
# References Functions in PS Script O4BClientAutoConfig.ps1 written by Jos Lieben @ https://www.lieben.nu/liebensraum/o4bclientautoconfig/
# @Per Larsen for writing on silent auto config: https://osddeployment.dk/2017/12/18/how-to-silently-configure-onedrive-for-business-with-intune/
# @Aaron Parker for writing on folder redirection using Powershell: https://stealthpuppy.com/onedrive-intune-folder-redirection
# Jason Wasser @wasserja for his great Robocopy Wrapper Function
#
# https://support.office.com/en-us/article/Use-Group-Policy-to-control-OneDrive-sync-client-settings-0ecb2cf5-8882-42b3-a6e9-be6bda30899c
# https://support.office.com/en-us/article/deploy-the-new-onedrive-sync-client-in-an-enterprise-environment-3f3a511c-30c6-404a-98bf-76f95c519668
# 
#
###############################################################################################
#	Change Control (add dates and changes below in your own organization)
###############################################################################################
#
#	Date		Modified by		Description of modification
#----------------------------------------------------------------------------------------------
#
#	02/12/2022	 	 		Initial version by Julian West
#	03/06/2022	 (JW)		Configure variables for location differences
#	03/15/2022	 (JW)		Remove Move/Copy functions and leverage Robocopy (pre-installed on Win10)
#	03/17/2022	 (JW)		Final testing round with GPO/GPP Registry entries for pre-migration settings
#  	03/29/2022   (JW)       Updated to clean up duplicate Desktop Shortcuts (optional, un-comment to run)
#   04/04/2022   (JW)		Updated to log activities to a log file
#	04/04/2022   (JW)		Update for Registry path checks to current redirected Shell folders
#	04/05/2022   (JW)		Trigger OneDrive Setup to run if on VPN and Migration Flagfile < 24 hrs old 
#   04/10/2022	 (JW)		Remove original employer specific code
#
###############################################################################################

# ************************************************

### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, needed for successful script run.  Set to your own env values - 
#

$OneDriveFolderName = "OneDrive - McKool Smith" # 
# **required - this is the OneDrive folder name that will exist under %USERPROFILE%
# This folder is usually named from your O365 Tenant's Org name by default, or is customized in GPO/Registry.
# This default folder name can be confirmed via a single manual install of OneDrive on a standalone Windows endpoint
#
$PrimaryTenantDomain = "mckoolsmith.com"
# **required - this your Primary Office 365 domain that is used in your User Principal Names / UPN.
# The script will use this to obtain your TenantID and perform other OneDrive setup functions.

#
##
### End of *REQUIRED* Variables -- 

###############################################################################################

### OPTIONAL CONFIGURATION ###
## *OPTIONAL* Variables, not required for script execution - 
#

$enableDataMigration = $True # <---- If you don't want to migrate data from Work Folders, and only set up OneDrive
$redirectFoldersToOnedriveForBusiness = $True # <--- Set to "False" if you do not wish to have Known Folders redirected.  Default is True & controlled by the "KNOWN FOLDERS ARRAY" section few lines down
$enableFilesOnDemand = $False # <---- Requires this script to run once with Admin rights to succeed.  Setting Requires Windows 10 1709 or higher
$cleanDesktopDuplicates = $False # <---- Set to True if you want the data migration to also clean up duplicate Desktop Shortcuts
$xmlDownloadURL = "https://g.live.com/1rewlive5skydrive/ODSUInsider"
$minimumOfflineVersionRequired = 19
$logFileX64 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx64.log"
$logFileX86 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx86.log"

#$WorkFoldersName = "Work Folders" # <--- You manually set this to the exact name of your Work Folders if you want. Script attempts to get this from Registry if not set.
# Script execution will check & populate $WorkFoldersName from HKCU\Software\Policies\Microsoft\Windows\WorkFolders and "LocalFolderPath" REG_SZ value
# Your own environment's "LocalFolderPath" value should have an entry similar to: %USERPROFILE%\WorkFolderPathName
# This value string is loaded and santized to remove %USERPROFILE%\ from the string,  then assigned to $WorkFoldersName variable.
# If the script cannot automatically do the above, just un-remark the $WorkFoldersName variable and set it to your own value.

$LogFileName = "ODfB_MigChecks-$env:username.log"
# This is the Log File name where activites will be logged, by default it includes the current Username 
# in the file name.  It is saved during Runtime to current %userprofile%\$LogFileName
#

$MigrationFlagFileName = "FirstOneDriveComplete.flg"
# This is the Migration Flag File which is created during WF to OneDrive data migration steps
# It is saved during Runtime to: %userprofile%\$OneDriveFolderName\$MigrationFlagFileName
#

###KNOWN FOLDERS ARRAY### <-- This is the list of known folders that will be checked for redirection

#Here we will enable Redirection for Known Folders and select individual folders (which will be referenced as an Array)
#Default is to redirect only 4 KNown Folders (Desktop, Documents, Favorites, and Pictures)
#You will need to review and: add any additional folders or subtract from these folders (or simply set the $redirectFoldersToOnedriveForBusiness variable to $False)

$listOfFoldersToRedirectToOnedriveForBusiness = @(#One line for each folder you want to redirect. For knownFolderInternalName choose from Get-KnownFolderPath function, for knownFolderInternalIdentifier choose from Set-KnownFolderPath function
    @{"knownFolderInternalName" = "Desktop";"knownFolderInternalIdentifier"="Desktop";"desiredSubFolderNameInOnedrive"="Desktop"},
    @{"knownFolderInternalName" = "MyDocuments";"knownFolderInternalIdentifier"="Documents";"desiredSubFolderNameInOnedrive"="Documents"},
    @{"knownFolderInternalName" = "Favorites";"knownFolderInternalIdentifier"="Favorites";"desiredSubFolderNameInOnedrive"="Favorites"},
    @{"knownFolderInternalName" = "MyPictures";"knownFolderInternalIdentifier"="Pictures";"desiredSubFolderNameInOnedrive"="Pictures"} #note that the last entry does NOT end with a comma
)

#
##
### End of OPTIONAL Variables -- 


##########################################################################
##		Functions Section - DO NOT MODIFY!!
##########################################################################

Function Log-InformationalEvent($Message){
#########################################################################
#	Writes an informational event to the event log
#########################################################################
$QualifiedMessage = $ClientName + " Script: " + $Message
Write-EventLog -LogName Application -Source Winlogon -Message $QualifiedMessage -EventId 1001 -EntryType Information
}

Function Log-WarningEvent($Message){
#########################################################################
# Writes a warning event to the event log
#########################################################################
$QualifiedMessage = $ClientName + " Script:" + $Message
Write-EventLog -LogName Application -Source Winlogon -Message $QualifiedMessage -EventId 1001 -EntryType Warning
}

Function WriteLog($LogString){
##########################################################################
##	Writes Run info to a logfile set in $LogFile variable 
##########################################################################

#Param ([string]$LogString)
$Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
$LogMessage = "$Stamp $LogString"
Add-content $LogFilePath -value $LogMessage
}

##########################################################################
##	Check users Admin rights 
##########################################################################
function Test-IsLocalAdministrator {
    <#
.SYNOPSIS
    Function to verify if the current user is a local Administrator on the current system
.DESCRIPTION
    Function to verify if the current user is a local Administrator on the current system
.EXAMPLE
    Test-IsLocalAdministrator

    True
.NOTES
    Francois-Xavier Cat
    @lazywinadmin
    lazywinadmin.com
    github.com/lazywinadmin
#>
    [CmdletBinding()]
    PARAM()
    try {
        ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

##########################################################################
##	Remove Registry Value if it exists
##########################################################################

function Remove-RegistryKeyValue
{
    <# 
    .SYNOPSIS 
    Removes a value from a registry key, if it exists. 
     
    .DESCRIPTION 
    If the given key doesn't exist, nothing happens. 
     
    .EXAMPLE 
    Remove-RegistryKeyValue -Path hklm:\Software\App\Test -Name 'InstallPath' 
     
    Removes the `InstallPath` value from the `hklm:\Software\App\Test` registry key. 
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the registry key where the value should be removed.
        $Path,
        
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the value to remove.
        $Name
    )
    
    Set-StrictMode -Version 'Latest'

    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if( (Test-RegistryKeyValue -Path $Path -Name $Name) )
    {
        if( $pscmdlet.ShouldProcess( ('Item: {0} Property: {1}' -f $Path,$Name), 'Remove Property' ) )
        {
            Remove-ItemProperty -Path $Path -Name $Name
        }
    }
}


##
##########################################################################
##                  End of Functions Section
##########################################################################
##           		Start of Script Operations
##########################################################################
###
###  SCRIPT OPERATIONS BEGIN


#Add User Profile path to customized variables

$LogFilePath = "$env:userprofile\$LogFileName"
$OneDriveUserPath = "$env:userprofile\$OneDriveFolderName"
$FirstOneDriveComplete = "$OneDriveUserPath\$MigrationFlagFileName"

	#Reset Logfile & set the Error Action to Continue
	Get-ChildItem -Path $LogFilePath | Remove-Item -Force
	$ErrorActionPreference = "Continue"
    
	#Log the SCript Runtime start
	WriteLog "OneDrive Migration Checklist and Script Staging"

    Write-Output "Set User Profile paths based on configured required variables"
    WriteLog "Set User Profile paths based on configured required variables..."


#Set PS Transcript Logfile & Restart self in x64 if we're on a 64-bit OS

## --> Jos Lieben Code" <-- UNMODIFIED
WriteLog "Setting Power Shell Transcript Logfile and checking Runtime Environment"
If (!([Environment]::Is64BitProcess)){ 
    Start-Transcript -Path $logFileX86
    if([Environment]::Is64BitOperatingSystem){
        Write-Output "Running 32 bit Powershell on 64 bit OS, restarting as 64 bit process..."
        $arguments = "-NoProfile -ExecutionPolicy ByPass -WindowStyle Hidden -File `"" + $myinvocation.mycommand.definition + "`""
        $path = (Join-Path $Env:SystemRoot -ChildPath "\sysnative\WindowsPowerShell\v1.0\powershell.exe")
        Start-Process $path -ArgumentList $arguments -Verb Open -Wait
        Write-Output "finished x64 version of PS"
        Stop-Transcript
        Exit
    }else{
        Write-Output "Running 32 bit Powershell on 32 bit OS"
    }
}else{
    Start-Transcript -Path $logFileX64
}
## --> End Jos Lieben Code" <--

WriteLog "Checking to see if 'WorkFoldersName' variable was set by a human, or is null & needs to be extracted."

If($WorkFoldersName -eq $null){

    WriteLog "Attempting to obtain the Work Folders Path from the Registry, format it, and asdsign to the `$WorkFoldersName variable."
    
$WFRegPath = "HKCU:\Software\Policies\Microsoft\Windows\WorkFolders"
$WFNameRegVal = "LocalFolderPath"

$WorkFoldersName = Get-ItemProperty -Path $WFRegPath | Select-Object -ExpandProperty $WFNameRegVal

if($WorkFoldersName -like '*%userprofile%*'){

    $WorkFoldersName = $WorkFoldersName -replace '%userprofile%', ''
}

$WorkFoldersName = $WorkFoldersName.replace('\', '')

}

$WorkFoldersPath = "$env:userprofile\$WorkFoldersName"

# Write-Host "Value of Work Folders Variable is $WorkFoldersName"

# Write-Host "Value of Work Folders Variable is $WorkFoldersPath"

$PrimaryTenantDomainTLD = $PrimaryTenantDomain.LastIndexOf('.')

$PrimaryTenantSubDomain = $PrimaryTenantDomain.Substring(0,$PrimaryTenantDomainTLD)


WriteLog "Primary Domain Name without TLD is $PrimaryTenantSubDomain"

WriteLog "Configured Required Variable for This Logfile: $LogFilePath"
WriteLog "Configured Required Variable for current Work Folder Root: $WorkFoldersPath"
WriteLog "Configured Required Variable for OneDrive Folder Root: $OneDriveUserPath"
WriteLog "Configured Required Variable for Primary Tenant Domain: $PrimaryTenantDomain"

WriteLog "Configured Required Variable for Migration Flag File: $FirstOneDriveComplete"

#Check for Local Admin Rights (expect that user is non-Admin, but check anyway)

    $isDomainAdmin = Test-IsLocalAdministrator

    Write-Output "Local Administrator Rights True or False: $isDomainAdmin"

#If user is a non-Admin as-expected, check to see if user has Scheduled Task creation rights

    If($isDomainAdmin -eq $false){
  
        #User running this process is a non-Admin user, therefore check Scheduled Task creation rights

        $STaskFolder = $env:windir + '\tasks'
        $UserSTCheck = $env:USERNAME
        $STpermission = (Get-Acl $STaskFolder).Access | ?{$_.IdentityReference -match $UserSTCheck} | Select IdentityReference,FileSystemRights
       
        If ($STpermission){
        $STpermission | % {Write-Host "User $($_.IdentityReference) has '$($_.FileSystemRights)' rights on folder $STaskfolder"}
        $SchedTasksRights = $true

        }Else{
        
            Write-Host "$UserSTCheck Doesn't have any permission on $STaskFolder"
            $SchedTasksRights = $false
        }
    }Else{

        #User running this process has Admin rights, therefore can create Scheduled Tasks
        $SchedTasksRights = $true
    }

#Set system.io variable for operations on Migration Flag file
[System.IO.DirectoryInfo]$FirstOneDriveCompletePath = $FirstOneDriveComplete

#Set system.io Variable to check for centralized/single Runtime of OneDrive vs Windows Bundled version
$OneDriveProgFiles = "C:\Program Files\Microsoft OneDrive"
[System.IO.DirectoryInfo]$OneDriveProgFilesPath = $OneDriveProgFiles


## --> Jos Lieben Code" <-- UNMODIFIED
#CREATE SILENT RUNNER (SO USER DOESN'T SEE A PS WINDOW)
WriteLog "Creating Silent Launch of script (so User doesn't see a PS window)."
$desiredBootScriptFolder = Join-Path $Env:ProgramData -ChildPath "WF-2-ODfB"
$vbsSilentPSRunner = "
Dim objShell,objFSO,objFile

Set objShell=CreateObject(`"WScript.Shell`")
Set objFSO=CreateObject(`"Scripting.FileSystemObject`")

strPath=WScript.Arguments.Item(0)

If objFSO.FileExists(strPath) Then
    set objFile=objFSO.GetFile(strPath)
    strCMD=`"powershell -nologo -executionpolicy ByPass -command `" & Chr(34) & `"&{`" &_
     objFile.ShortPath & `"}`" & Chr(34) 
    objShell.Run strCMD,0
Else
    WScript.Echo `"Failed to find `" & strPath
    WScript.Quit
End If
"
$desiredBootScriptPath = Join-Path $desiredBootScriptFolder -ChildPath "WF-2-ODfB-Mig.ps1"
$desiredVBSScriptPath = Join-Path $desiredBootScriptFolder -ChildPath "WF-2-ODfB-Mig.vbs"

if(![System.IO.Directory]::($desiredBootScriptFolder)){
    New-Item -Path $desiredBootScriptFolder -Type Directory -Force
}

$vbsSilentPSRunner | Out-File $desiredVBSScriptPath -Force

#ENSURE CONFIG REGISTRY KEYS ARE CREATED
try{
    Write-Output "Adding registry keys for Onedrive"
    $res = New-Item -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Confirm:$False -ErrorAction SilentlyContinue
    $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name SilentAccountConfig -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    If($isDomainAdmin -eq $true){
        if($enableFilesOnDemand -eq $true){
            $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
        }else{
            $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 0 -PropertyType DWORD -Force -ErrorAction Stop
        }
        #Delete Registry value "DisableFileSyncNGSC" if it exists
        Remove-RegistryKeyValue -Path HKLM:\Software\Policies\Microsoft\Windows\OneDrive -Name 'DisableFileSyncNGSC' 
    }
    Write-Output "Required Registry keys for Onedrive created or modified"
}catch{
    Write-Error "Failed to add Onedrive registry keys, installation may not be consistent" -ErrorAction Continue
    Write-Error $_ -ErrorAction Continue
}

#REGISTER SCRIPT TO RUN AT LOGON
WriteLog "Registering Script to run at logon"
$wscriptPath = Join-Path $env:SystemRoot -ChildPath "System32\wscript.exe"
$fullRunPath = "$wscriptPath `"$desiredVBSScriptPath`" `"$desiredBootScriptPath`""
try{
    Write-Output "Adding logon registry key"
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name OnedriveAutoConfig -Value $fullRunPath -PropertyType String -Force -ErrorAction Stop
    Write-Output "logon registry key added"
}catch{
    Write-Error "Failed to add logon registry keys, user config will likely fail" -ErrorAction Continue
    Write-Error $_ -ErrorAction Continue
}

#######################################################
# Create a scheduled task to run the script once
#######################################################

If($SchedTasksRights -eq $true){
WriteLog "Creating scheduled task to run the script once."
$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$desiredVBSScriptPath`" `"$desiredBootScriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Compatibility Win8
$principal = New-ScheduledTaskPrincipal -GroupId S-1-5-32-545
$task = New-ScheduledTask -Action $action -Settings $settings -Principal $principal
Register-ScheduledTask -InputObject $task -TaskName "OnedriveAutoConfig"
}

## --> End Jos Lieben Code" <--

#######################################################
#
# Begin Placement of code for Local Script Sched Task
#
#######################################################

WriteLog "Staging local Powershell script for Migration activities under Scheduled-task"

## --> Jos Lieben Code" <--  MODIFIED

$localScriptContent = "
<#
    Name: WF-2-ODfB-Mig.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West
    Licensed Under Creative Commons Public Attribution license 4.0 (non-Commercial use);
.SYNOPSIS
    Migrate any active Work Folders to OneDrive for Business
.DESCRIPTION
    This script is created by WF-2-ODfB.ps1 (Master Script) and is placed into a user's Scheduled Tasks to ensure that
    a silent migration of a Windows 10 Endpoint's User data sync settings from Work Folders 
    over to OneDrive for Business can occur automatically.  
    It is targeted to silently run OneDrive Setup and auto sign-in (if Hybrid joined to Azure AD), 
    sets redirection for Known Folders, and moves data from Work Folders to OneDrive folder via Robocopy /Move.  
    Leverages code from Jos Lieben's solution at https://www.lieben.nu/liebensraum/o4bclientautoconfig/
    Requirements: Windows 10, Powershell 5x or above.
.LINK
    https://github.com/J-DubApps
#>

### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, required for successful script run.  These are set by the Master Script.  
#

# User Profile paths and customized variables set by Master Script - you can Adjust to your own env values if needed - 

`$OneDriveFolderName = `"$OneDriveFolderName`"
`$WorkFoldersName = `"$WorkFoldersName`"
`$PrimaryTenantDomain = `"$PrimaryTenantDomain`"
`$PrimaryTenantSubDomain = `"$PrimaryTenantSubDomain`"
`$LogFileName = `"ODfB_Config_Run_`$env:username.log`"
`$MigrationFlagFileName = `"$MigrationFlagFileName`" 
`$LogFilePath = `"`$env:userprofile\`$LogFileName`"
`$OneDriveUserPath = `"`$env:userprofile\`$OneDriveFolderName`"
`$WorkFoldersPath = `"`$env:userprofile\`$WorkFoldersName`"
`$FirstOneDriveComplete = `"`$OneDriveUserPath\`$MigrationFlagFileName`"
`$enableDataMigration = `$$enableDataMigration
`$cleanDesktopDuplicates = `$$cleanDesktopDuplicates

#Use system.io variable for File & Directory operations to check for Migration Flag file & Work Folders Path
If([System.IO.Directory]::Exists(`$WorkFoldersPath)){`$WorkFoldersExist = `$true}else{`$WorkFoldersExist = `$false}
if(![System.IO.File]::Exists(`$FirstOneDriveComplete)){`$ODFlagFileExist = `$false}else{`$ODFlagFileExist  = `$true}

#Set variable if we encounter both OneDrive Flag File and Work Folders paths at the same time
`$WF_and_Flagfile_Exist = `$null
If((`$ODFlagFileExist -eq `$true)  -and (`$WorkFoldersExist -eq `$true)){`$WF_and_Flagfile_Exist = `$true}else{`$WF_and_Flagfile_Exist = `$false}
    

`$redirectFoldersToOnedriveForBusiness = `$$redirectFoldersToOnedriveForBusiness
`$listOfFoldersToRedirectToOnedriveForBusiness = @("
$listOfFoldersToRedirectToOnedriveForBusiness | % {
        $localScriptContent += "@{`"knownFolderInternalName`"=`"$($_.knownFolderInternalName)`";`"knownFolderInternalIdentifier`"=`"$($_.knownFolderInternalIdentifier)`";`"desiredSubFolderNameInOnedrive`"=`"$($_.desiredSubFolderNameInOnedrive)`"},"
}
$localScriptContent = $localScriptContent -replace ".$"
$localScriptContent += ")
`$logFile = Join-Path `$Env:TEMP -ChildPath `"OnedriveAutoConfig.log`"
`$xmlDownloadURL = `"$xmlDownloadURL`"
`$temporaryInstallerPath = Join-Path `$Env:TEMP -ChildPath `"OnedriveInstaller.EXE`"
`$minimumOfflineVersionRequired = `"$minimumOfflineVersionRequired`"
`$onedriveRootKey = `"HKCU:\Software\Microsoft\OneDrive\Accounts\Business`"
`$desiredBootScriptFolder = `"$desiredBootScriptFolder`"
`$desiredBootScriptPath = `"$desiredBootScriptPath`" 
Start-Transcript -Path `$logFile
 

#Reset Logfile & set the Error Action to Continue
Get-ChildItem -Path `$LogFilePath | Remove-Item -Force
`$ErrorActionPreference = `"Continue`"

##########################################################################
##		Main Functions Section - DO NOT MODIFY!!
##########################################################################

Function Log-InformationalEvent(`$Message){
#########################################################################
#	Writes an informational event to the event log
#########################################################################
`$QualifiedMessage = `$ClientName + `" Script: `" + `$Message
Write-EventLog -LogName Application -Source Winlogon -Message `$QualifiedMessage -EventId 1001 -EntryType Information
}

Function Log-WarningEvent(`$Message){
#########################################################################
# Writes a warning event to the event log
#########################################################################
`$QualifiedMessage = `$ClientName + `" Script:`" + `$Message
Write-EventLog -LogName Application -Source Winlogon -Message `$QualifiedMessage -EventId 1001 -EntryType Warning
}

Function WriteLog(`$LogString){
##########################################################################
##	Writes Run info to a logfile set in `$LogFile variable 
##########################################################################

#Param ([string]`$LogString)
`$Stamp = (Get-Date).toString(`"yyyy/MM/dd HH:mm:ss`")
`$LogMessage = `"`$Stamp `$LogString`"
Add-content `$LogFilePath -value `$LogMessage
}


function returnEnclosedValue{
    Param(
        [Parameter(Mandatory = `$True)]`$sourceString,
        [Parameter(Mandatory = `$True)]`$searchString
    )
    try{
        `$endString = `"```"`"
        `$start = `$searchString
        `$startLoc = `$sourceString.IndexOf(`$start)+`$start.Length
        if(`$startLoc -eq `$start.Length-1){
            Throw `"Not Found`"
        }
        `$searchLength = `$sourceString.IndexOf(`$endString,`$startLoc)-`$startLoc
        if(`$searchLength -eq `$startLoc-1){
            Throw `"Not Found`"
        }
        return(`$sourceString.Substring(`$startLoc,`$searchLength))
    }catch{Throw}
}

function runProcess (`$cmd, `$params, `$windowStyle=1) {
    `$p = new-object System.Diagnostics.Process
    `$p.StartInfo = new-object System.Diagnostics.ProcessStartInfo
    `$exitcode = `$false
    `$p.StartInfo.FileName = `$cmd
    `$p.StartInfo.Arguments = `$params
    `$p.StartInfo.UseShellExecute = `$False
    `$p.StartInfo.RedirectStandardError = `$True
    `$p.StartInfo.RedirectStandardOutput = `$True
    `$p.StartInfo.WindowStyle = `$windowStyle; #1 = hidden, 2 =maximized, 3=minimized, 4=normal
    `$null = `$p.Start()
    `$output = `$p.StandardOutput.ReadToEnd()
    `$exitcode = `$p.ExitCode
    `$p.Dispose()
    `$exitcode
    `$output
}


##########################################################################
##	Delete Empty Folders
##########################################################################

# Set to true to test the script
`$whatIf = `$true

# Remove hidden files, like thumbs.db
`$removeHiddenFiles = `$true

# Get hidden files or not. Depending on removeHiddenFiles setting
`$getHiddelFiles = !`$removeHiddenFiles

# Remove empty directories locally
Function Delete-EmptyFolder(`$path)
{
    # Go through each subfolder, 
    Foreach (`$subFolder in Get-ChildItem -Force -Literal `$path -Directory) 
    {
        # Call the function recursively
        Delete-EmptyFolder -path `$subFolder.FullName
    }

    # Get all child items
    `$subItems = Get-ChildItem -Force:`$getHiddelFiles -LiteralPath `$path

    # If there are no items, then we can delete the folder
    # Exlude folder: If ((`$subItems -eq `$null) -and (-Not(`$path.contains(`"DfsrPrivate`")))) 
    If (`$subItems -eq `$null) 
    {
        Write-Host `"Removing empty folder '`${path}'`"
        WriteLog `"Removing empty folder '`${path}'`"
        Remove-Item -Force -Recurse:`$removeHiddenFiles -LiteralPath `$Path -WhatIf:`$whatIf
    }
}



##
##########################################################################
##                  End of Functions Section
##########################################################################
##           		Start of Script Operations
##########################################################################
###
###  SCRIPT OPERATIONS BEGIN

WriteLog `"Script Operations Starting...`"

WriteLog `"One Drive Flag File Exists: `$ODFlagFileExist `"
WriteLog `"Work Folders Exist: `$WorkFoldersExist `"

WriteLog `"One Drive Flag File & Work Folders Status: `$WF_and_Flagfile_Exist `"


If(`$cleanDesktopDuplicates -eq `$true){
###Clean up duplicate Desktop Shortcuts - Comment out to disable this section
###
### This section cleans up any duplicate Chrome, Teams, or MS Edge shortcuts.
###  
### To check for other App shortcut duplicate names, add named-entries to the 
### `$DuplicateNames variable.
###
### Can also be used to clean up duplicate .url shortcuts as well.

`$DesktopPath = Join-Path -Path ([Environment]::GetFolderPath(`"Desktop`")) -ChildPath `"*`"

`$DuplicateNames = @(
   `"*Edge*`",
   `"*Teams*`",
   `"*Chrome*`"
)

WriteLog `"Cleaning duplicate Desktop Shortcuts`"

Get-ChildItem -Path `$DesktopPath -Filter *.lnk -Include `$DuplicateNames | Where-Object {`$_.Name -like `"*-*.lnk`"} | Remove-Item -Force
Get-ChildItem -Path `$DesktopPath -Filter *.url -Include `$DuplicateNames | Where-Object {`$_.Name -like `"*-*.url`"} | Remove-Item -Force

}

#Attempt to auto-fill TenantID

`$TenantID = (Invoke-WebRequest https://login.windows.net/`$PrimaryTenantSubDomain.onmicrosoft.com/.well-known/openid-configuration | ConvertFrom-Json).token_endpoint.Split('/')[3]

#ENSURE ONEDRIVE CONFIG REGISTRY KEYS ARE CREATED
try{
    Write-Output `"Adding registry keys for Onedrive`"
    WriteLog `"Adding registry keys for Onedrive`"
    `$res = New-Item -Path `"HKCU:\Software\Microsoft\Onedrive`" -Confirm:`$False -ErrorAction SilentlyContinue
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name DefaultToBusinessFRE -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name DisablePersonalSync -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name EnableEnterpriseTier -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name EnableADAL -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    Write-Output `"Registry keys for Onedrive added`"
}catch{
    Write-Error `"Failed to add Onedrive registry keys, installation may not be consistent`" -ErrorAction Continue
    Write-Error `$_ -ErrorAction Continue
    WriteLog `"Failed to add Onedrive registry keys, installation may not be consistent`"
}


`$isOnedriveUpToDate = `$False
#GET ONLINE VERSION INFO
try{
    `$xmlInfo = Invoke-WebRequest -UseBasicParsing -Uri `$xmlDownloadURL -Method GET
    `$version = returnEnclosedValue -sourceString `$xmlInfo.Content -searchString `"currentversion=```"`"
    `$downloadURL = returnEnclosedValue -sourceString `$xmlInfo.Content -searchString `"url=```"`"
    write-output `"Microsoft's XML shows the latest Onedrive version is `$version and can be downloaded from `$downloadURL`"
    WriteLog `"Microsoft's XML shows the latest Onedrive version is `$version and can be downloaded from `$downloadURL`"
}catch{
    write-error `"Failed to download / read version info for Onedrive from `$xmlDownloadURL`" -ErrorAction Continue
    write-error `$_ -ErrorAction Continue
    WriteLog `"Failed to download / read version info for Onedrive from `$xmlDownloadURL`"
}

#GET LOCAL INSTALL STATUS AND VERSION
try{
    `$installedVersion = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"Version`" -ErrorAction Stop).Version
    `$installedVersionPath = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"OneDriveTrigger`" -ErrorAction Stop).OneDriveTrigger
    Write-Output `"Detected `$installedVersion in registry`"
    WriteLog `"Detected `$installedVersion in registry`"
    if(`$installedVersion -le `$minimumOfflineVersionRequired -or (`$version -and `$version -gt `$installedVersion)){
        Write-Output `"Onedrive is not up to date!`"
        WriteLog `"Onedrive is not up to date!`"
    }else{
        `$isOnedriveUpToDate = `$True
        Write-Output `"Installed version of Onedrive is newer or the same as advertised version`"
        If(!(Get-Process | where {`$_.ProcessName -like `"onedrive*`"})){
            Write-Output `"OneDrive process is not running...`"
            WriteLog `"OneDrive process is not running...`"
            `$OD4BusinessArgs = `" /background /configure_business:`$(`$TenantID) /silentConfig`"
            Start-Process `"`$(`$installedVersionPath)`" -ArgumentList `$OD4BusinessArgs
        }
    }
}catch{
    write-error `"Failed to read Onedrive version information from the registry, assuming Onedrive is not installed`" -ErrorAction Continue
    write-error `$_ -ErrorAction Continue
    WriteLog `"Failed to read Onedrive version information from the registry, assuming Onedrive is not installed`"
}

#DOWNLOAD ONEDRIVE INSTALLER AND RUN IT
try{
    if(!`$isOnedriveUpToDate -and `$downloadURL){
        Write-Output `"downloading from download URL: `$downloadURL`"
        WriteLog `"downloading from download URL: `$downloadURL`"
        Invoke-WebRequest -UseBasicParsing -Uri `$downloadURL -Method GET -OutFile `$temporaryInstallerPath
        Write-Output `"downloaded finished from download URL: `$downloadURL`"
        WriteLog `"downloaded finished from download URL: `$downloadURL`"
        if([System.IO.File]::Exists(`$temporaryInstallerPath)){
            Write-Output `"Starting client installer`"
            WriteLog `"Starting client installer`"
            Sleep -s 5 #let A/V scan the file so it isn't locked
            #first kill existing instances
            get-process | where {`$_.ProcessName -like `"onedrive*`"} | Stop-Process -Force -Confirm:`$False
            Sleep -s 5
            #runProcess `$temporaryInstallerPath `"/silent`"
            If(`$TenantID -ne `$null){
                `$OD4BusinessArgs = `" /background /configure_business:`$(`$TenantID) /silentConfig`"
                Start-Process `"`$(`$installedVersionPath)`" -ArgumentList `$OD4BusinessArgs
            Sleep -s 5
            Write-Output `"Install finished`"
            WriteLog `"Install finished`"
            }
        }
        `$installedVersionPath = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"OneDriveTrigger`" -ErrorAction Stop).OneDriveTrigger
    }
}catch{
    Write-Error `"Failed to download or install from `$downloadURL`" -ErrorAction Continue
    Write-Error `$_ -ErrorAction Continue
    WriteLog `"Failed to download or install from `$downloadURL`"
}

#WAIT FOR CLIENT CONFIGURATION AND REDETERMINE PATH
`$maxWaitTime = 30
`$waited = 0
Write-Output `"Checking existence of client folder`"
WriteLog `"Checking existence of client folder`"
:detectO4B while(`$true){
    if(`$waited -gt `$maxWaitTime){
        Write-Output `"Waited too long for client folder to appear. Running auto updater, then exiting`"
        WriteLog `"Waited too long for client folder to appear. Running auto updater, then exiting`"
        `$updaterPath = Join-Path `$Env:LOCALAPPDATA -ChildPath `"Microsoft\OneDrive\OneDriveStandaloneUpdater.exe`"
        runProcess `$updaterPath
        Sleep -s 30
        If(`$TenantID -ne `$null){
            `$OD4BusinessArgs = `" /background /configure_business:`$(`$TenantID) /silentConfig`"
            Start-Process `"`$(`$installedVersionPath)`" -ArgumentList `$OD4BusinessArgs
        }
        Sleep -s 15
    }

    `$checks = 5
    for(`$i=1;`$i -le `$checks;`$i++){
        #check if a root path for the key exists
        `$subPath = `"`$(`$onedriveRootKey)`$(`$i)`"
        if(Test-Path `$subPath){
            `$detectedTenant = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -ErrorAction SilentlyContinue).ConfiguredTenantId
            #Added by Julian West
            If(`$detectedTenant -eq `$null){
                New-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -Value `$TenantID -PropertyType String -Force
                `$detectedTenant = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -ErrorAction SilentlyContinue).ConfiguredTenantId
            }
            Write-Output `"Detected tenant `$detectedTenant`"
            WriteLog `"Detected tenant `$detectedTenant`"
            #we've either found a registry key with the correct TenantID or populated it, Onedrive has been started, let's now check for the folder path
            `$detectedFolderPath = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"UserFolder`" -ErrorAction SilentlyContinue).UserFolder
            #Added by Julian West
            If(`$detectedFolderPath -eq `$null){
             New-ItemProperty -Path `"`$(`$subPath)\`" -Name `"UserFolder`" -Value `$OneDriveUserPath -PropertyType String -Force
             `$detectedFolderPath = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"UserFolder`" -ErrorAction SilentlyContinue).UserFolder
            }
            Write-Output `"Detected UserFolder Path in Registry `$detectedFolderPath`"
            WriteLog `"Detected UserFolder Path in Registry `$detectedFolderPath`"
 
             if(`$detectedFolderPath -and [System.IO.Directory]::Exists(`$detectedFolderPath)){
                    Write-Output `"Found OneDrive user folder at `$detectedFolderPath`"
                    WriteLog `"Found OneDrive user folder at `$detectedFolderPath`"
                    #break detectO4B
                    
                    If((Get-Process | Where-Object {`$_.ProcessName -like `"onedrive*`"}) -and (`$WorkFoldersExist -eq `$true)){

                        #Work Folders and OneDrive Registry entries / User Folder exist simultaneously and OneDrive Client is running - let's do one protective sync of any non-existent files 
                        # from WF --> OD4B just in case it's needed
                        #You need to check your environment to determine why Work Folder path still exists after this script would have deleted it: likely GPOs are still published and
                        #re-enabling Work Folders settings (leaving OneDrive and Work Folders sync both simultaneously enabled).   
                        WriteLog `"Work Folders and OneDrive deployment both exist at the same time, prepare to move any orphan WF contents`"
                        Write-Host `"Work Folders and OneDrive deployment both exist at the same time, performing one-way sync/move  of any orphan WF contents via Robocopy with /X CNO options to sync-up OD4B folder`"

                        robocopy `"`"`$(`$WorkFoldersPath)`"`" `"`"`$(`$OneDriveUserPath)`"`" /E /MOVE /XC /XN /XO /LOG+:`$env:userprofile\Start-Robocopy-`$(Get-Date -Format 'yyyyMMddhhmmss').log
                        break detectO4B
                    }else{
                        
                        #OneDrive Registry entries / User Folder exist without any Work Folders presence.  Assume all is well with the OneDrive client, and break.

                        break detectO4B
                    }
             }else{
                 #If it doesn't exist let's go ahead and create this folder because we'll be doing another pass to ensure OneDrive client runs anyway.
                 New-Item -Path `$OneDriveUserPath -ItemType Directory -Force -ErrorAction SilentlyContinue
             }
         }else{
         
                Write-Output `"didn't find root path for OneDrive`"
         }
     }

    if(`$waited -gt `$maxWaitTime){
        break
    }
    Write-Output `"failed to detect user folder! Sleeping for 30 seconds`"
    Sleep -Seconds 30
    `$waited+=30   
     
    #GET LOCAL INSTALL PATH
    try{
        `$installedVersionPath = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"OneDriveTrigger`" -ErrorAction Stop).OneDriveTrigger
        Write-Output `"Detected Onedrive at `$installedVersionPath`"
        WriteLog `"Detected Onedrive at `$installedVersionPath`"
    }catch{
        write-error `"Failed to read Onedrive version information from the registry`" -ErrorAction Continue
        WriteLog `"Failed to read Onedrive version information from the registry`"
        `$installedVersionPath = Join-Path `$Env:LOCALAPPDATA -ChildPath `"Microsoft\OneDrive\OneDrive.exe`"
        Write-output `"Will use auto-guessed value of `$installedVersionPath`"
        WriteLog `"Will use auto-guessed value of `$installedVersionPath`"
    }

    #RUN THE LOCAL CLIENT IF ALREADY INSTALLED
    Write-Output `"Starting OneDrive client...`"
    WriteLog `"Starting OneDrive client...`"
    #& `$installedVersionPath

    `$OneDriveUserRegPath = `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`"
    `$OneDriveUserRegValName = `"OneDrive`"
    `$OneDriveRegVal = `$installedVersionPath + `" /background`"
    New-ItemProperty -Path `$OneDriveUserRegPath -Name `$OneDriveUserRegValName -Value `$OneDriveRegVal -PropertyType String -Force 
    
    `$OD4BusinessArgs = `" /background /configure_business:`$(`$detectedTenant) /silentConfig`"
    Start-Process `"`$(`$installedVersionPath)`" -ArgumentList `$OD4BusinessArgs

}


#DATA MIGRATION SECTION

#Clean Up any old Robocopy Log Files older than 3 days

Get-ChildItem -Path `"`$env:userprofile\Start-Robocopy-*`" | Where-Object {(`$_.LastWriteTime -lt (Get-Date).AddDays(-3))} | Remove-Item

# Perform Migrations if MIGRATION FLAG FILE <> Exist + Work Folders Path Exists

If((`$ODFlagFileExist -eq `$false) -and (`$WorkFoldersExist -eq `$true)){
    
    If(`$enableDataMigration -eq `$true){
        
    #OneDrive Flag File does not exist and WF Folder exists, perform First Migration pass
    WriteLog `"OneDrive Flag File does not exist and WF Folder exists, perform First Migration pass`"
    Write-Host `"OneDrive Flag File does not exist and WF Folder exists, perform first Migration pass`"

        robocopy `"`"`$(`$WorkFoldersPath)`"`" `"`"`$(`$OneDriveUserPath)`"`" /E /MOVE /LOG+:`$env:userprofile\Start-Robocopy-`$(Get-Date -Format 'yyyyMMddhhmmss').log
    }

    #Create our Flag File for initial One Drive data Migration
    New-Item -Path `$FirstOneDriveComplete -type file -force

}else{

    #Leaving this Else stmt here, in case there is anything else we want to do when the OneDrive Migration Flag File exists
}

If (`$WF_and_Flagfile_Exist = `$false) {

    #Work Folders or Flag File do not exist together at the same time, nothing to migrate or sync to OneDrive
    WriteLog `"Work Folders or Flag File do not exist together at the same time, nothing to migrate or sync to OneDrive`"

} Else {

    #Work Folders and Flag File exist at the same time, prepare to move any present files in WF folder & remove WF
    WriteLog `"Work Folders and Flag File exist at the same time, prepare to move any present files in WF folder & remove WF`"
    Write-Host `"Work Folders and Flag File exists at the same time, performing one-way Sync to OD4B from WF using Robocopy with /X CNO options`"
    #Perform WF File Clean-up Migration

    If(`$enableDataMigration -eq `$true){
   

        robocopy `"`"`$(`$WorkFoldersPath)`"`" `"`"`$(`$OneDriveUserPath)`"`" /E /MOVE /XC /XN /XO /LOG+:`$env:userprofile\Start-Robocopy-`$(Get-Date -Format 'yyyyMMddhhmmss').log

         #Delete-EmptyFolder -path `"`$WorkFoldersPath`"
         #Disabled Delete-Emptyfolder run as Robocopy /MOVE does this.  If Work Folders path comes back, it's a GPO or other mechanism that is bringng WF back.

    }

}

If(!`$redirectFoldersToOnedriveForBusiness){
    Stop-Transcript
    Exit
}
### FOLDER REDIRECTION FUNCTIONS
Function Set-KnownFolderPath {
    Param (
            [Parameter(Mandatory = `$true)][ValidateSet('AddNewPrograms', 'AdminTools', 'AppUpdates', 'CDBurning', 'ChangeRemovePrograms', 'CommonAdminTools', 'CommonOEMLinks', 'CommonPrograms', `
            'CommonStartMenu', 'CommonStartup', 'CommonTemplates', 'ComputerFolder', 'ConflictFolder', 'ConnectionsFolder', 'Contacts', 'ControlPanelFolder', 'Cookies', `
            'Desktop', 'Documents', 'Downloads', 'Favorites', 'Fonts', 'Games', 'GameTasks', 'History', 'InternetCache', 'InternetFolder', 'Links', 'LocalAppData', `
            'LocalAppDataLow', 'LocalizedResourcesDir', 'Music', 'NetHood', 'NetworkFolder', 'OriginalImages', 'PhotoAlbums', 'Pictures', 'Playlists', 'PrintersFolder', `
            'PrintHood', 'Profile', 'ProgramData', 'ProgramFiles', 'ProgramFilesX64', 'ProgramFilesX86', 'ProgramFilesCommon', 'ProgramFilesCommonX64', 'ProgramFilesCommonX86', `
            'Programs', 'Public', 'PublicDesktop', 'PublicDocuments', 'PublicDownloads', 'PublicGameTasks', 'PublicMusic', 'PublicPictures', 'PublicVideos', 'QuickLaunch', `
            'Recent', 'RecycleBinFolder', 'ResourceDir', 'RoamingAppData', 'SampleMusic', 'SamplePictures', 'SamplePlaylists', 'SampleVideos', 'SavedGames', 'SavedSearches', `
            'SEARCH_CSC', 'SEARCH_MAPI', 'SearchHome', 'SendTo', 'SidebarDefaultParts', 'SidebarParts', 'StartMenu', 'Startup', 'SyncManagerFolder', 'SyncResultsFolder', `
            'SyncSetupFolder', 'System', 'SystemX86', 'Templates', 'TreeProperties', 'UserProfiles', 'UsersFiles', 'Videos', 'Windows')]
            [string]`$KnownFolder,
            [Parameter(Mandatory = `$true)][string]`$Path
    )

    # Define known folder GUIDs
    `$KnownFolders = @{
        'AddNewPrograms' = 'de61d971-5ebc-4f02-a3a9-6c82895e5c04';'AdminTools' = '724EF170-A42D-4FEF-9F26-B60E846FBA4F';'AppUpdates' = 'a305ce99-f527-492b-8b1a-7e76fa98d6e4';
        'CDBurning' = '9E52AB10-F80D-49DF-ACB8-4330F5687855';'ChangeRemovePrograms' = 'df7266ac-9274-4867-8d55-3bd661de872d';'CommonAdminTools' = 'D0384E7D-BAC3-4797-8F14-CBA229B392B5';
        'CommonOEMLinks' = 'C1BAE2D0-10DF-4334-BEDD-7AA20B227A9D';'CommonPrograms' = '0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8';'CommonStartMenu' = 'A4115719-D62E-491D-AA7C-E74B8BE3B067';
        'CommonStartup' = '82A5EA35-D9CD-47C5-9629-E15D2F714E6E';'CommonTemplates' = 'B94237E7-57AC-4347-9151-B08C6C32D1F7';'ComputerFolder' = '0AC0837C-BBF8-452A-850D-79D08E667CA7';
        'ConflictFolder' = '4bfefb45-347d-4006-a5be-ac0cb0567192';'ConnectionsFolder' = '6F0CD92B-2E97-45D1-88FF-B0D186B8DEDD';'Contacts' = '56784854-C6CB-462b-8169-88E350ACB882';
        'ControlPanelFolder' = '82A74AEB-AEB4-465C-A014-D097EE346D63';'Cookies' = '2B0F765D-C0E9-4171-908E-08A611B84FF6';'Desktop' = @('B4BFCC3A-DB2C-424C-B029-7FE99A87C641');
        'Documents' = @('FDD39AD0-238F-46AF-ADB4-6C85480369C7','f42ee2d3-909f-4907-8871-4c22fc0bf756');'Downloads' = @('374DE290-123F-4565-9164-39C4925E467B','7d83ee9b-2244-4e70-b1f5-5393042af1e4');
        'Favorites' = '1777F761-68AD-4D8A-87BD-30B759FA33DD';'Fonts' = 'FD228CB7-AE11-4AE3-864C-16F3910AB8FE';'Games' = 'CAC52C1A-B53D-4edc-92D7-6B2E8AC19434';
        'GameTasks' = '054FAE61-4DD8-4787-80B6-090220C4B700';'History' = 'D9DC8A3B-B784-432E-A781-5A1130A75963';'InternetCache' = '352481E8-33BE-4251-BA85-6007CAEDCF9D';
        'InternetFolder' = '4D9F7874-4E0C-4904-967B-40B0D20C3E4B';'Links' = 'bfb9d5e0-c6a9-404c-b2b2-ae6db6af4968';'LocalAppData' = 'F1B32785-6FBA-4FCF-9D55-7B8E7F157091';
        'LocalAppDataLow' = 'A520A1A4-1780-4FF6-BD18-167343C5AF16';'LocalizedResourcesDir' = '2A00375E-224C-49DE-B8D1-440DF7EF3DDC';'Music' = @('4BD8D571-6D19-48D3-BE97-422220080E43','a0c69a99-21c8-4671-8703-7934162fcf1d');
        'NetHood' = 'C5ABBF53-E17F-4121-8900-86626FC2C973';'NetworkFolder' = 'D20BEEC4-5CA8-4905-AE3B-BF251EA09B53';'OriginalImages' = '2C36C0AA-5812-4b87-BFD0-4CD0DFB19B39';
        'PhotoAlbums' = '69D2CF90-FC33-4FB7-9A0C-EBB0F0FCB43C';'Pictures' = @('33E28130-4E1E-4676-835A-98395C3BC3BB','0ddd015d-b06c-45d5-8c4c-f59713854639');
        'Playlists' = 'DE92C1C7-837F-4F69-A3BB-86E631204A23';'PrintersFolder' = '76FC4E2D-D6AD-4519-A663-37BD56068185';'PrintHood' = '9274BD8D-CFD1-41C3-B35E-B13F55A758F4';
        'Profile' = '5E6C858F-0E22-4760-9AFE-EA3317B67173';'ProgramData' = '62AB5D82-FDC1-4DC3-A9DD-070D1D495D97';'ProgramFiles' = '905e63b6-c1bf-494e-b29c-65b732d3d21a';
        'ProgramFilesX64' = '6D809377-6AF0-444b-8957-A3773F02200E';'ProgramFilesX86' = '7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E';'ProgramFilesCommon' = 'F7F1ED05-9F6D-47A2-AAAE-29D317C6F066';
        'ProgramFilesCommonX64' = '6365D5A7-0F0D-45E5-87F6-0DA56B6A4F7D';'ProgramFilesCommonX86' = 'DE974D24-D9C6-4D3E-BF91-F4455120B917';'Programs' = 'A77F5D77-2E2B-44C3-A6A2-ABA601054A51';
        'Public' = 'DFDF76A2-C82A-4D63-906A-5644AC457385';'PublicDesktop' = 'C4AA340D-F20F-4863-AFEF-F87EF2E6BA25';'PublicDocuments' = 'ED4824AF-DCE4-45A8-81E2-FC7965083634';
        'PublicDownloads' = '3D644C9B-1FB8-4f30-9B45-F670235F79C0';'PublicGameTasks' = 'DEBF2536-E1A8-4c59-B6A2-414586476AEA';'PublicMusic' = '3214FAB5-9757-4298-BB61-92A9DEAA44FF';
        'PublicPictures' = 'B6EBFB86-6907-413C-9AF7-4FC2ABF07CC5';'PublicVideos' = '2400183A-6185-49FB-A2D8-4A392A602BA3';'QuickLaunch' = '52a4f021-7b75-48a9-9f6b-4b87a210bc8f';
        'Recent' = 'AE50C081-EBD2-438A-8655-8A092E34987A';'RecycleBinFolder' = 'B7534046-3ECB-4C18-BE4E-64CD4CB7D6AC';'ResourceDir' = '8AD10C31-2ADB-4296-A8F7-E4701232C972';
        'RoamingAppData' = '3EB685DB-65F9-4CF6-A03A-E3EF65729F3D';'SampleMusic' = 'B250C668-F57D-4EE1-A63C-290EE7D1AA1F';'SamplePictures' = 'C4900540-2379-4C75-844B-64E6FAF8716B';
        'SamplePlaylists' = '15CA69B3-30EE-49C1-ACE1-6B5EC372AFB5';'SampleVideos' = '859EAD94-2E85-48AD-A71A-0969CB56A6CD';'SavedGames' = '4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4';
        'SavedSearches' = '7d1d3a04-debb-4115-95cf-2f29da2920da';'SEARCH_CSC' = 'ee32e446-31ca-4aba-814f-a5ebd2fd6d5e';'SEARCH_MAPI' = '98ec0e18-2098-4d44-8644-66979315a281';
        'SearchHome' = '190337d1-b8ca-4121-a639-6d472d16972a';'SendTo' = '8983036C-27C0-404B-8F08-102D10DCFD74';'SidebarDefaultParts' = '7B396E54-9EC5-4300-BE0A-2482EBAE1A26';
        'SidebarParts' = 'A75D362E-50FC-4fb7-AC2C-A8BEAA314493';'StartMenu' = '625B53C3-AB48-4EC1-BA1F-A1EF4146FC19';'Startup' = 'B97D20BB-F46A-4C97-BA10-5E3608430854';
        'SyncManagerFolder' = '43668BF8-C14E-49B2-97C9-747784D784B7';'SyncResultsFolder' = '289a9a43-be44-4057-a41b-587a76d7e7f9';'SyncSetupFolder' = '0F214138-B1D3-4a90-BBA9-27CBC0C5389A';
        'System' = '1AC14E77-02E7-4E5D-B744-2EB1AE5198B7';'SystemX86' = 'D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27';'Templates' = 'A63293E8-664E-48DB-A079-DF759E0509F7';
        'TreeProperties' = '5b3749ad-b49f-49c1-83eb-15370fbd4882';'UserProfiles' = '0762D272-C50A-4BB0-A382-697DCD729B80';'UsersFiles' = 'f3ce0f7c-4901-4acc-8648-d5d44b04ef8f';
        'Videos' = @('18989B1D-99B5-455B-841C-AB7C74E4DDFC','35286a68-3c57-41a1-bbb1-0eae73d76c95');'Windows' = 'F38BF404-1D43-42F2-9305-67DE0B28FC23';
    }

    `$Type = ([System.Management.Automation.PSTypeName]'KnownFolders').Type
    If (-not `$Type) {
        `$Signature = @'
[DllImport(`"shell32.dll`")]
public extern static int SHSetKnownFolderPath(ref Guid folderId, uint flags, IntPtr token, [MarshalAs(UnmanagedType.LPWStr)] string path);
'@
        `$Type = Add-Type -MemberDefinition `$Signature -Name 'KnownFolders' -Namespace 'SHSetKnownFolderPath' -PassThru
    }

	If (!(Test-Path `$Path -PathType Container)) {
		New-Item -Path `$Path -Type Directory -Force -Verbose
    }

    If (Test-Path `$Path -PathType Container) {
        ForEach (`$guid in `$KnownFolders[`$KnownFolder]) {
            Write-Verbose `"Redirecting `$KnownFolders[`$KnownFolder]`"
            `$result = `$Type::SHSetKnownFolderPath([ref]`$guid, 0, 0, `$Path)
            If (`$result -ne 0) {
                `$errormsg = `"Error redirecting `$(`$KnownFolder). Return code `$(`$result) = `$((New-Object System.ComponentModel.Win32Exception(`$result)).message)`"
                Throw `$errormsg
            }
        }
    } Else {
        Throw New-Object System.IO.DirectoryNotFoundException `"Could not find part of the path `$Path.`"
    }
	
	Attrib +r `$Path
    Return `$Path
}

Function Get-KnownFolderPath {
    Param (
            [Parameter(Mandatory = `$true)]
            [ValidateSet('AdminTools','ApplicationData','CDBurning','CommonAdminTools','CommonApplicationData','CommonDesktopDirectory','CommonDocuments','CommonMusic',`
            'CommonOemLinks','CommonPictures','CommonProgramFiles','CommonProgramFilesX86','CommonPrograms','CommonStartMenu','CommonStartup','CommonTemplates',`
            'CommonVideos','Cookies','Downloads','Desktop','DesktopDirectory','Favorites','Fonts','History','InternetCache','LocalApplicationData','LocalizedResources','MyComputer',`
            'MyDocuments','MyMusic','MyPictures','MyVideos','NetworkShortcuts','Personal','PrinterShortcuts','ProgramFiles','ProgramFilesX86','Programs','Recent',`
            'Resources','SendTo','StartMenu','Startup','System','SystemX86','Templates','UserProfile','Windows')]
            [string]`$KnownFolder
    )
    if(`$KnownFolder -eq `"Downloads`"){
        Return `$Null
    }else{
        Return [Environment]::GetFolderPath(`$KnownFolder)
    }
}

Function Redirect-Folder {
    Param (
        `$GetFolder,
        `$SetFolder,
        `$Target
    )

    `$Folder = Get-KnownFolderPath -KnownFolder `$GetFolder
    If (`$Folder -ne `$Target) {
        Write-Verbose `"Redirecting `$SetFolder to `$Target`"
        Set-KnownFolderPath -KnownFolder `$SetFolder -Path `$Target
        #if(`$CopyContents -and `$Folder){
        #    Get-ChildItem -Path `$Folder -ErrorAction Continue | Copy-Item -Destination `$Target -Recurse -Container -Force -Confirm:`$False -ErrorAction Continue
        #}
        #Attrib +h `$Folder
    } Else {
        Write-Verbose `"Folder `$GetFolder matches target. Skipping redirection.`"
    }
}


# Remove Work Folders Sync URL and Set AutoProvision to Zero (0)

if(`$redirectFoldersToOnedriveForBusiness -eq `$true){
WriteLog `"Removing Work Folders Sync URL and disabling AutoProvision`"

 `$WorkFoldersRegPath = `"HKCU:\Software\Policies\Microsoft\Windows\WorkFolders`"
 `$WorkFoldersSyncURL = `"SyncUrl`"
 `$WorkFoldersAutoProvisionVal = `"0`"

    Remove-ItemProperty -Path `$WorkFoldersRegPath -Name `$WorkFoldersSyncURL -Force 

    New-ItemProperty -Path `$WorkFoldersRegPath -Name `"AutoProvision`" -Value `$WorkFoldersAutoProvisionVal -PropertyType DWord -Force 
}


# Redirect Folders
if(`$detectedFolderPath -and `$redirectFoldersToOnedriveForBusiness){
    `$listOfFoldersToRedirectToOnedriveForBusiness | % {
        Write-Output `"Redirecting `$(`$_.knownFolderInternalName) to `$detectedFolderPath\`$(`$_.desiredSubFolderNameInOnedrive)`"
        WriteLog `"Redirecting `$(`$_.knownFolderInternalName) to `$detectedFolderPath\`$(`$_.desiredSubFolderNameInOnedrive)`"
        try{
            `$Target = Join-Path `$detectedFolderPath -ChildPath `$_.desiredSubFolderNameInOnedrive
            Redirect-Folder -GetFolder `$_.knownFolderInternalName -SetFolder `$_.knownFolderInternalIdentifier -Target `$Target 
            Write-Output `"Redirection succeeded`"
            WriteLog `"Redirection succeeded`"
        }catch{
            Write-Error `"Failed to redirect this folder!`" -ErrorAction Continue
            WriteLog `"Failed to redirect this folder!`"
            Write-Error `$_ -ErrorAction Continue     
        }
    }
}



Stop-Transcript

Log-InformationalEvent(`"Work Folders to OneDrive Migration Script-run completed for `" + `$env:UserName)
	
WriteLog `"WF to OneDrive Config & Data Migration Script-Run Complete`"

Exit (0)
"

$localScriptContent | Out-File $desiredBootScriptPath -Force

## --> End Jos Lieben Code" <-- 

#######################################################
#
# End of code for Local Script for scheduled task to 
# run the script once
#
#######################################################

#End of Script - cleanup & Exit

Stop-Transcript

   Log-InformationalEvent("Work Folders to OneDrive Migration Script-run completed for " + $env:UserName)
   
   WriteLog "WF to OneDrive Migration Setup Script-Run Complete"
   WriteLog "A Config & Migration script will been established in Scheduled Tasks if the user had Scheduled Task Mgmt Permissions" 

   $SchedTaskName = "OnedriveAutoConfig"
   $SchedTaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $SchedTaskName }

If($SchedTaskExists) {
   WriteLog "WF to OneDrive Config & Migration Scheduled Task will now be run"
  Start-ScheduledTask -TaskName "OnedriveAutoConfig"

} else {
  # Do Nothing
}

	Exit (0)


