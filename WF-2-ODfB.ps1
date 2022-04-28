<#
    Name: WF-2-ODfB.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West
    Licensed Under GNU General Public License, version 3 (GPLv3);
.SYNOPSIS
    Set up OneDrive for Business and migrate active Work Folders data to OneDrive 
.DESCRIPTION
    This script will migrate a Windows 10 Endpoint's User data sync settings
    from Work Folders over to OneDrive for Business.  It is targeted to silently run 
    OneDrive Setup (see note below), moves data from Work Folders to OneDrive folder via
    Robocopy /Move, and sets redirection for Known Folders.  Leverages code from 
    Jos Lieben's solution at https://www.lieben.nu/liebensraum/o4bclientautoconfig/
    Requirements: Windows 10, Powershell script should run as an Admin if Script wasn't installed yet
.LINK
    https://github.com/J-DubApps
    #>

###############################################################################################
#
#			WorkFolders-To-OneDrive for Business Migration v 0.4.x
#			    WF-2-ODfB.ps1
#
#	Description 
#		This script will migrate a Windows 10 Endpoint's User data sync settings
#       from Work Folders over to OneDrive for Business.  It is targeted to silently run 
#       OneDrive Setup (see note below), moves data from Work Folders to OneDrive folder via
#       Robocopy /Move, and sets redirection for Known Folders.  
#       
#       This script can be run with or without Admin rights, but needs Admin rights
#       for certain features to work (enabling FilesOnDemand etc). For optimal UX the script is 
#       designed to run HIDDEN (no PS window seen by the user), and can re-run multiple times 
#       for hybrid Remote Workers' PC endpoints (where interruptions may occur).
#
#       The Script can be deployed via a Domain GPO as a Computer or User Logon script, or 
#       in another manner (MECM, etc). How you will deploy it depends on your particular
#       envionrment.  When run with Admin rights, the script will set migration tasks to run as a 
#       local Logon Script & Scheduled Task, for greatest success with Hybrid Remote Worker/VPN users
#       to ensure a successful migration.  
#
#    BACKGROUND: While both OneDrive For Business & Work Folder sync can *both* be used at the  
#       same time, this script strictly disables Work Folder sync during its run. As most 
#       organizations move to Hybrid Management and/or Intune/BYOD scenarios, moving away from
#       on-prem Work Folders is primarily why this script exists.
#       
#		
#	Usage
#		Script has no required Parameters, but does have a REQUIRED section you *must* modify below. 
#       
#       For all OneDrive environment config items, should be run ONCE using Admin rights, which can be 
#       accomplished via GPO Computer Logon script using "-executionpolicy ByPass" PowerShell.exe 
#       script parameters.  You can also sign the script (not in-scope of this documentation).  
#       Script can also first triggered via MECM, existing Logon Script, or manually.
# 
#       During execution, script removes Work Folder redirection (if present) and removes
#       Work Folder sync server settings (this would be in addition to any GPO doing the same).  
#       The script then installs OneDrive, migrates Work Folder data, and redirects Known Folders. 
#         
#       The script runs OneDriveSetup.exe /silent from either the Windows bundled version
#       under %windir$\SysWOW64 folder or the C:\Program Files per-machine install of the
#       standalone version of OneDrive, places OneDrive.exe startup into HKCU...Run in the registry, 
#       and it will move all Work Folders contents to the configured OneDrive path under the 
#       user's profile.
#
#
#       For hybrid/remote work scenarios the script attempts to detect VPN client connection status 
#       and will set itself to run as a Scheduled Task. Script assumes any detected VPN client is NOT 
#       configured for "Always On" operation and runs as a locally-executed process (hence the 
#       Scheduled Task method of launch).  
#
#       NOTE: To leverage automatic sign-in for OneDrive, your Windows Endpoints must be configured 
#           for Hybrid  Azure AD join. 
#           More info here: https://docs.microsoft.com/en-us/azure/active-directory/devices/concept-azure-ad-join-hybrid
#                           https://docs.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-plan  
#
# 	LICENSE: GNU General Public License, version 3 (GPLv3)
#
#  You are free to make any changes to your own copy of this script, provided you agree
#  you cannot hold the original author responsible for any issues resulting from this script.
#  I welcome forks or pulls and will be happy to help improve the script for anyone if I have the time.
#
#  Please do feel free share any deployment success, or script ideas, with me: jdub.writes.some.code(at)gmail(dot)com
#
#  TL;DR*
#
# 1. Anyone can copy, modify and distribute this software.
# 2. You have to include the license and any copyright notice with each and every distribution.
# 3. You can use this software privately.
# 4. You can use this software for commercial purposes.
# 5. If you dare build a business engagement from this code, you risk open-sourcing the whole code base.
# 6. If you modify it, you have to indicate changes made to the code.
# 7. Any modifications of this code base MUST be distributed with the same license, GPLv3.
# 8. This software is provided without warranty.
# 9. The software author or license can not be held liable for any damages inflicted by the software.
# 10. Feel free to reach out to author to share usage, ideas etc jdub.writes.some.code(at)gmail(dot)com
#
###############################################################################################
#
# Mentions / articles used:
# References Functions in PS Module O4BClientAutoConfig written by Jos Lieben @ https://www.lieben.nu/liebensraum/o4bclientautoconfig/
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
#   	04/10/2022   (JW)       Remove original employer specific code
#   	04/20/2022   (JW)       Publish inital commit to Github.
#
###############################################################################################

# ************************************************

### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, required for successful script run.  Set to your own env values - 
#

$TenantID = "<Your Tenant ID here>"
# **required - Set this variable with your Tenant ID 

$WorkFoldersName = "Work Folders"  # <--- Your Work Folders Name Here
# **required - the folder currently used for Work Folder redirection/sync in your enviornment.
# Script execution on Windows endpoints will look for this folder name.
#

$OneDriveFolderName = "<Your Tenant OneDrive Folder Name Here>"  
# **required - this is OneDrive folder name that will exist under %USERPROFILE%
# This folder is usually named from your O365 Tenant Org name by default, or customized in GPO/Registry.
# This default folder name can be confirmed via manual install of OneDrive on a standalone Windows endpoint.

$LogFileName = "ODfB_Mig-$env:username.log"
# This is the Log File name where activites will be logged, by default it includes the current Username 
# in the file name.  It is saved during Runtime to current %userprofile%\$LogFileName
#

$MigrationFlagFileName = "FirstOneDriveComplete.flg"
# This is the Migration Flag File which is created during WF to OneDrive data migration steps
# It is saved during Runtime to current %userprofile%\$MigrationFlagFileName
#

#
##
### End of *REQUIRED* Variables -- 

###############################################################################################

### OPTIONAL CONFIGURATION ###
## *OPTIONAL* Variables, not required for script execution - 
#

$FilesOnDemand = "0" #OneDrive Files On Demand is Default to DISABLED, replace with "1" to enable
$xmlDownloadURL = "https://g.live.com/1rewlive5skydrive/ODSUInsider"
$minimumOfflineVersionRequired = 19
$temporaryInstallerPath = Join-Path $Env:TEMP -ChildPath "OnedriveInstaller.EXE"
$logFileX64 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx64.log"
$logFileX86 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx86.log"

#HKLM\SOFTWARE\Policies\Microsoft\OneDrive]"FilesOnDemandEnabled"="dword:00000001"

#
##
### End of OPTIONAL Variables -- 



###############################################################################################


##########################################################################
##				 Functions Section - DO NOT MODIFY!!
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
Add-content $LogFile -value $LogMessage
}

##########################################################################
##	Returns a string value - for parsing online content 
##########################################################################
Function returnEnclosedValue{
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

##########################################################################
##	Runs a new process hidden or visible
##########################################################################

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
## Retrieve Known Folder Path
##########################################################################
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

##########################################################################
## Set Known Folder Path
##########################################################################
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


##########################################################################
## Redirect Known Folder
##########################################################################
Function Redirect-Folder {
    Param (
        `$GetFolder,
        `$SetFolder,
        `$Target,
        `$CopyContents
    )

    `$Folder = Get-KnownFolderPath -KnownFolder `$GetFolder
    If (`$Folder -ne `$Target) {
        Write-Verbose `"Redirecting `$SetFolder to `$Target`"
        Set-KnownFolderPath -KnownFolder `$SetFolder -Path `$Target
        if(`$CopyContents -and `$Folder){
            Get-ChildItem -Path `$Folder -ErrorAction Continue | Copy-Item -Destination `$Target -Recurse -Container -Force -Confirm:`$False -ErrorAction Continue
        }
        Attrib +h `$Folder
    } Else {
        Write-Verbose `"Folder `$GetFolder matches target. Skipping redirection.`"
    }
}

##########################################################################
# Function to check whether a given username matches the list of Domain Admins
##########################################################################
function validateDomainAdmin{
    
    if ((Get-ADUser "$env:UserName" -Properties memberof).memberof -like “*Domain Admins*” ){
         #Write-Host "$username is a Domain Admin"
         return $true;
         }else{
        #Write-Host "$username not a Domain Admin."
        return $false;

        }
 }


##########################################################################
# PowerShell wrapper function for robocopy by Jason Wasser @wasserja 
##########################################################################
<# 
.Synopsis 
   PowerShell wrapper function for robocopy. 
.DESCRIPTION 
   PowerShell wrapper function for robocopy. 
.NOTES 
    Created by: Jason Wasser @wasserja 
    Modified: 4/7/2016 11:16:12 AM 
 
    Version 1.0 
 
.PARAMETER Source 
    The source folder you wish to copy. 
.PARAMETER Destination 
    The destination folder to which you are copying. 
.PARAMETER RobocopyPath 
    The path to the robocopy binary (exe) 
.PARAMETER RobocopyParameters 
    Specify the robocopy parameters you wish to you. 
 
    robocopy /? 
     
------------------------------------------------------------------------------- 
   ROBOCOPY :: Robust File Copy for Windows 
------------------------------------------------------------------------------- 
 
  Started : Thursday, April 7, 2016 11:18:11 AM 
              Usage :: ROBOCOPY source destination [file [file]...] [options] 
 
             source :: Source Directory (drive:\path or \\server\share\path). 
        destination :: Destination Dir (drive:\path or \\server\share\path). 
               file :: File(s) to copy (names/wildcards: default is "*.*"). 
 
:: 
:: Copy options : 
:: 
                 /S :: copy Subdirectories, but not empty ones. 
                 /E :: copy subdirectories, including Empty ones. 
             /LEV:n :: only copy the top n LEVels of the source directory tree. 
 
                 /Z :: copy files in restartable mode. 
                 /B :: copy files in Backup mode. 
                /ZB :: use restartable mode; if access denied use Backup mode. 
                 /J :: copy using unbuffered I/O (recommended for large files). 
            /EFSRAW :: copy all encrypted files in EFS RAW mode. 
 
  /COPY:copyflag[s] :: what to COPY for files (default is /COPY:DAT). 
                       (copyflags : D=Data, A=Attributes, T=Timestamps). 
                       (S=Security=NTFS ACLs, O=Owner info, U=aUditing info). 
 
 
               /SEC :: copy files with SECurity (equivalent to /COPY:DATS). 
           /COPYALL :: COPY ALL file info (equivalent to /COPY:DATSOU). 
            /NOCOPY :: COPY NO file info (useful with /PURGE). 
            /SECFIX :: FIX file SECurity on all files, even skipped files. 
            /TIMFIX :: FIX file TIMes on all files, even skipped files. 
 
             /PURGE :: delete dest files/dirs that no longer exist in source. 
               /MIR :: MIRror a directory tree (equivalent to /E plus /PURGE). 
 
               /MOV :: MOVe files (delete from source after copying). 
              /MOVE :: MOVE files AND dirs (delete from source after copying). 
 
     /A+:[RASHCNET] :: add the given Attributes to copied files. 
     /A-:[RASHCNET] :: remove the given Attributes from copied files. 
 
            /CREATE :: CREATE directory tree and zero-length files only. 
               /FAT :: create destination files using 8.3 FAT file names only. 
               /256 :: turn off very long path (> 256 characters) support. 
 
             /MON:n :: MONitor source; run again when more than n changes seen. 
             /MOT:m :: MOnitor source; run again in m minutes Time, if changed. 
 
      /RH:hhmm-hhmm :: Run Hours - times when new copies may be started. 
                /PF :: check run hours on a Per File (not per pass) basis. 
 
             /IPG:n :: Inter-Packet Gap (ms), to free bandwidth on slow lines. 
 
                /SL :: copy symbolic links versus the target. 
 
            /MT[:n] :: Do multi-threaded copies with n threads (default 8). 
                       n must be at least 1 and not greater than 128. 
                       This option is incompatible with the /IPG and /EFSRAW options. 
                       Redirect output using /LOG option for better performance. 
 
 /DCOPY:copyflag[s] :: what to COPY for directories (default is /DCOPY:DA). 
                       (copyflags : D=Data, A=Attributes, T=Timestamps). 
 
           /NODCOPY :: COPY NO directory info (by default /DCOPY:DA is done). 
 
         /NOOFFLOAD :: copy files without using the Windows Copy Offload mechanism. 
 
:: 
:: File Selection Options : 
:: 
                 /A :: copy only files with the Archive attribute set. 
                 /M :: copy only files with the Archive attribute and reset it. 
    /IA:[RASHCNETO] :: Include only files with any of the given Attributes set. 
    /XA:[RASHCNETO] :: eXclude files with any of the given Attributes set. 
 
 /XF file [file]... :: eXclude Files matching given names/paths/wildcards. 
 /XD dirs [dirs]... :: eXclude Directories matching given names/paths. 
 
                /XC :: eXclude Changed files. 
                /XN :: eXclude Newer files. 
                /XO :: eXclude Older files. 
                /XX :: eXclude eXtra files and directories. 
                /XL :: eXclude Lonely files and directories. 
                /IS :: Include Same files. 
                /IT :: Include Tweaked files. 
 
             /MAX:n :: MAXimum file size - exclude files bigger than n bytes. 
             /MIN:n :: MINimum file size - exclude files smaller than n bytes. 
 
          /MAXAGE:n :: MAXimum file AGE - exclude files older than n days/date. 
          /MINAGE:n :: MINimum file AGE - exclude files newer than n days/date. 
          /MAXLAD:n :: MAXimum Last Access Date - exclude files unused since n. 
          /MINLAD:n :: MINimum Last Access Date - exclude files used since n. 
                       (If n < 1900 then n = n days, else n = YYYYMMDD date). 
 
                /XJ :: eXclude Junction points. (normally included by default). 
 
               /FFT :: assume FAT File Times (2-second granularity). 
               /DST :: compensate for one-hour DST time differences. 
 
               /XJD :: eXclude Junction points for Directories. 
               /XJF :: eXclude Junction points for Files. 
 
:: 
:: Retry Options : 
:: 
               /R:n :: number of Retries on failed copies: default 1 million. 
               /W:n :: Wait time between retries: default is 30 seconds. 
 
               /REG :: Save /R:n and /W:n in the Registry as default settings. 
 
               /TBD :: wait for sharenames To Be Defined (retry error 67). 
 
:: 
:: Logging Options : 
:: 
                 /L :: List only - don't copy, timestamp or delete any files. 
                 /X :: report all eXtra files, not just those selected. 
                 /V :: produce Verbose output, showing skipped files. 
                /TS :: include source file Time Stamps in the output. 
                /FP :: include Full Pathname of files in the output. 
             /BYTES :: Print sizes as bytes. 
 
                /NS :: No Size - don't log file sizes. 
                /NC :: No Class - don't log file classes. 
               /NFL :: No File List - don't log file names. 
               /NDL :: No Directory List - don't log directory names. 
 
                /NP :: No Progress - don't display percentage copied. 
               /ETA :: show Estimated Time of Arrival of copied files. 
 
          /LOG:file :: output status to LOG file (overwrite existing log). 
         /LOG+:file :: output status to LOG file (append to existing log). 
 
       /UNILOG:file :: output status to LOG file as UNICODE (overwrite existing log). 
      /UNILOG+:file :: output status to LOG file as UNICODE (append to existing log). 
 
               /TEE :: output to console window, as well as the log file. 
 
               /NJH :: No Job Header. 
               /NJS :: No Job Summary. 
 
           /UNICODE :: output status as UNICODE. 
 
:: 
:: Job Options : 
:: 
       /JOB:jobname :: take parameters from the named JOB file. 
      /SAVE:jobname :: SAVE parameters to the named job file 
              /QUIT :: QUIT after processing command line (to view parameters). 
              /NOSD :: NO Source Directory is specified. 
              /NODD :: NO Destination Directory is specified. 
                /IF :: Include the following Files. 
 
:: 
:: Remarks : 
:: 
       Using /PURGE or /MIR on the root directory of the volume will 
       cause robocopy to apply the requested operation on files inside 
       the System Volume Information directory as well. If this is not 
       intended then the /XD switch may be used to instruct robocopy 
       to skip that directory. 
 
 
.PARAMETER LogFileName 
    The path to the log file for the robocopy results. 
.PARAMETER Tee 
    Use this parameter if you wish to see tee the output from robocopy 
    to the screen as well as the log file. 
 
.EXAMPLE 
   Start-Robocopy -Source C:\Temp -Destination D:\Temp2 
   Starts robocopy from c:\temp to D:\Temp2. 
.EXAMPLE 
   Start-Robocopy -Source C:\Temp -Destination D:\Temp2 -RobocopyParameters '/E /Z /MIR /COPYALL' 
#>

Function Start-Robocopy
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory,
                    Position=0)]
        [string]$Source,

        [Parameter(Mandatory,
                    Position=1)]
        [string]$Destination,

        [string]$IncludeFile = '*.*',
        
        [string]$RobocopyPath = 'c:\Windows\system32\robocopy.exe',
        
        [string]$RobocopyParameter = '/E /Z /MIR /V /NP /R:3 /W:5 /MT',
        
        [string]$LogFileName = "C:\Logs\Start-Robocopy-$(Get-Date -Format 'yyyyMMddhhmmss').log",

        [switch]$Tee = $false
    )

    Begin
    {
        # Turn on verbose
        $VerbosePreference = 'Continue'

        # Start Log
        # Begin Logging
        Add-Content -Value "Beginning $($MyInvocation.InvocationName) on $($env:COMPUTERNAME) by $env:USERDOMAIN\$env:USERNAME" -Path $LogFileName

        $RobocopyParameter = "$RobocopyParameter /LOG+:$LogFileName"
        if ($Tee) {
            $RobocopyParameter = "$RobocopyParameter /TEE"
            }
        
        Write-Verbose "Robocopy Parameters: $RobocopyParameter"

    }
    Process
    {
        
        # Build robocopy command line
        $RobocopyExecute = "$RobocopyPath $Source $Destination $IncludeFile $RobocopyParameter"       
        Write-Verbose "Executing Robocopy Command Line: $RobocopyExecute"
        Add-Content "Executing Robocopy Command Line: $RobocopyExecute" -Path $LogFileName
        Invoke-Expression $RobocopyExecute
        
    }
    End
    {

    }
}



##
##########################################################################
##					End of Functions Section
##########################################################################
##           		Start of Script Operations
##########################################################################
###
###  SCRIPT OPERATIONS BEGIN

#Add User Profile path to customized variables

WriteLog "Setting User Profile paths based on configured required variables..."

$LogFilePath = "$env:userprofile\$LogFileName"
$OneDriveUserPath = "$env:userprofile\$OneDriveFolderName"
$WorkFoldersPath = "$env:userprofile\$WorkFoldersName"
$FirstOneDriveComplete = "$env:userprofile\$MigrationFlagFileName"

	#Reset Logfile & set the Error Action to Continue
	Get-ChildItem -Path $LogFilePath | Remove-Item -Force
	$ErrorActionPreference = "Continue"

    WriteLog "Configured Required Variable for This Logfile: $LogFilePath"
    WriteLog "Configured Required Variable for Tenant ID: $TenantID"
    WriteLog "Configured Required Variable for current Work Folder Root: $WorkFoldersPath"
    WriteLog "Configured Required Variable for OneDrive Folder Root: $OneDriveUserPath"
    WriteLog "Configured Required Variable for Migration Flag File: $FirstOneDriveComplete"
    
	#Log the SCript Runtime start
	WriteLog "OneDrive Migration Script Run Start"

    $isDomainAdmin = validateDomainAdmin

#Set system.io variable for operations on Migration Flag file
[System.IO.DirectoryInfo]$FirstOneDriveCompletePath = $FirstOneDriveComplete

#Set system.io Variable to check for centralized/single Runtime of OneDrive vs Windows Bundled version
$OneDriveProgFiles = "C:\Program Files\Microsoft OneDrive"
[System.IO.DirectoryInfo]$OneDriveProgFilesPath = $OneDriveProgFiles


#Restart self in x64
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

#CREATE SILENT RUNNER (SO USER DOESN'T SEE A PS WINDOW)
WriteLog "Creating Silent Launch of script (so User doesn't see a PS windows)."
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
$desiredBootScriptPath = Join-Path $desiredBootScriptFolder -ChildPath "WF-2-ODfB.ps1"
$desiredVBSScriptPath = Join-Path $desiredBootScriptFolder -ChildPath "WF-2-ODfB.vbs"

if(![System.IO.Directory]::($desiredBootScriptFolder)){
    New-Item -Path $desiredBootScriptFolder -Type Directory -Force
}

$vbsSilentPSRunner | Out-File $desiredVBSScriptPath -Force

#ENSURE CONFIG REGISTRY KEYS ARE CREATED
try{
    Write-Output "Adding registry keys for Onedrive"
    $res = New-Item -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Confirm:$False -ErrorAction SilentlyContinue
    $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name SilentAccountConfig -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    if($enableFilesOnDemand){
        $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    }else{
        $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 0 -PropertyType DWORD -Force -ErrorAction Stop
    }
    Write-Output "Registry keys for Onedrive added"
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

WriteLog "Creating scheduled task to run the script once."
$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$desiredVBSScriptPath`" `"$desiredBootScriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Compatibility Win8
$principal = New-ScheduledTaskPrincipal -GroupId S-1-5-32-545
$task = New-ScheduledTask -Action $action -Settings $settings -Principal $principal
Register-ScheduledTask -InputObject $task -TaskName "OnedriveAutoConfig"


#######################################################
#
# Begin Placement of code for Local Script Sched Task
#
#######################################################

$localScriptContent = "
<#
    Name: WF-2-ODfB.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West
    Licensed Under GNU General Public License, version 3 (GPLv3);
.SYNOPSIS
    Migrate any active Work Folders to OneDrive for Business
.DESCRIPTION
    This script will migrate a Windows 10 Endpoint's User data sync settings
    from Work Folders over to OneDrive for Business.  It is targeted to silently run 
    OneDrive Setup (see note below), moves data from Work Folders to OneDrive folder via
    Robocopy /Move, and sets redirection for Known Folders.  Leverages code from 
    Jos Lieben's solution at https://www.lieben.nu/liebensraum/o4bclientautoconfig/
    Requirements: Windows 10, Powershell script should run as an Admin if Script wasn't installed yet
.LINK
    https://github.com/J-DubApps
#>

`$redirectFoldersToOnedriveForBusiness = `$$redirectFoldersToOnedriveForBusiness
`$listOfFoldersToRedirectToOnedriveForBusiness = @("
$listOfFoldersToRedirectToOnedriveForBusiness | % {
        $localScriptContent += "@{`"knownFolderInternalName`"=`"$($_.knownFolderInternalName)`";`"knownFolderInternalIdentifier`"=`"$($_.knownFolderInternalIdentifier)`";`"desiredSubFolderNameInOnedrive`"=`"$($_.desiredSubFolderNameInOnedrive)`";`"copyContents`"=`"$($_.copyContents)`"},"
}
$localScriptContent = $localScriptContent -replace ".$"
$localScriptContent += ")
`$logFile = Join-Path `$Env:TEMP -ChildPath `"OnedriveAutoConfig.log`"
`$xmlDownloadURL = `"$xmlDownloadURL`"
`$temporaryInstallerPath = `"$temporaryInstallerPath`"
`$minimumOfflineVersionRequired = `"$minimumOfflineVersionRequired`"
`$onedriveRootKey = `"HKCU:\Software\Microsoft\OneDrive\Accounts\Business`"
`$desiredBootScriptFolder = `"$desiredBootScriptFolder`"
`$desiredBootScriptPath = `"$desiredBootScriptPath`"
Start-Transcript -Path `$logFile
#ENSURE CONFIG REGISTRY KEYS ARE CREATED
try{
    Write-Output `"Adding registry keys for Onedrive`"
    `$res = New-Item -Path `"HKCU:\Software\Microsoft\Onedrive`" -Confirm:`$False -ErrorAction SilentlyContinue
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name DefaultToBusinessFRE -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name DisablePersonalSync -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name EnableEnterpriseTier -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    `$res = New-ItemProperty -Path `"HKCU:\Software\Microsoft\Onedrive`" -Name EnableADAL -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
    Write-Output `"Registry keys for Onedrive added`"
}catch{
    Write-Error `"Failed to add Onedrive registry keys, installation may not be consistent`" -ErrorAction Continue
    Write-Error `$_ -ErrorAction Continue
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

`$isOnedriveUpToDate = `$False
#GET ONLINE VERSION INFO
try{
    `$xmlInfo = Invoke-WebRequest -UseBasicParsing -Uri `$xmlDownloadURL -Method GET
    `$version = returnEnclosedValue -sourceString `$xmlInfo.Content -searchString `"currentversion=```"`"
    `$downloadURL = returnEnclosedValue -sourceString `$xmlInfo.Content -searchString `"url=```"`"
    write-output `"Microsoft's XML shows the latest Onedrive version is `$version and can be downloaded from `$downloadURL`"
}catch{
    write-error `"Failed to download / read version info for Onedrive from `$xmlDownloadURL`" -ErrorAction Continue
    write-error `$_ -ErrorAction Continue
}

#GET LOCAL INSTALL STATUS AND VERSION
try{
    `$installedVersion = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"Version`" -ErrorAction Stop).Version
    `$installedVersionPath = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"OneDriveTrigger`" -ErrorAction Stop).OneDriveTrigger
    Write-Output `"Detected `$installedVersion in registry`"
    if(`$installedVersion -le `$minimumOfflineVersionRequired -or (`$version -and `$version -gt `$installedVersion)){
        Write-Output `"Onedrive is not up to date!`"
    }else{
        `$isOnedriveUpToDate = `$True
        Write-Output `"Installed version of Onedrive is newer or the same as advertised version`"
    }
}catch{
    write-error `"Failed to read Onedrive version information from the registry, assuming Onedrive is not installed`" -ErrorAction Continue
    write-error `$_ -ErrorAction Continue
}

#DOWNLOAD ONEDRIVE INSTALLER AND RUN IT
try{
    if(!`$isOnedriveUpToDate -and `$downloadURL){
        Write-Output `"downloading from download URL: `$downloadURL`"
        Invoke-WebRequest -UseBasicParsing -Uri `$downloadURL -Method GET -OutFile `$temporaryInstallerPath
        Write-Output `"downloaded finished from download URL: `$downloadURL`"
        if([System.IO.File]::Exists(`$temporaryInstallerPath)){
            Write-Output `"Starting client installer`"
            Sleep -s 5 #let A/V scan the file so it isn't locked
            #first kill existing instances
            get-process | where {`$_.ProcessName -like `"onedrive*`"} | Stop-Process -Force -Confirm:`$False
            Sleep -s 5
            runProcess `$temporaryInstallerPath `"/silent`"
            Sleep -s 5
            Write-Output `"Install finished`"
        }
        `$installedVersionPath = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\OneDrive`" -Name `"OneDriveTrigger`" -ErrorAction Stop).OneDriveTrigger
    }
}catch{
    Write-Error `"Failed to download or install from `$downloadURL`" -ErrorAction Continue
    Write-Error `$_ -ErrorAction Continue
}

#WAIT FOR CLIENT CONFIGURATION AND REDETERMINE PATH
`$maxWaitTime = 600
`$waited = 0
Write-Output `"Checking existence of client folder`"
:detectO4B while(`$true){
    if(`$waited -gt `$maxWaitTime){
        Write-Output `"Waited too long for client folder to appear. Running auto updater, then exiting`"
        `$updaterPath = Join-Path `$Env:LOCALAPPDATA -ChildPath `"Microsoft\OneDrive\OneDriveStandaloneUpdater.exe`"
        runProcess `$updaterPath
        Sleep -s 60
        runProcess `$installedVersionPath
        Sleep -s 60
    }

    `$checks = 5
    for(`$i=1;`$i -le `$checks;`$i++){
        #check if a root path for the key exists
        `$subPath = `"`$(`$onedriveRootKey)`$(`$i)`"
        if(Test-Path `$subPath){
            `$detectedTenant = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -ErrorAction SilentlyContinue).ConfiguredTenantId
            #we've found a business key with the correct TenantID, Onedrive has been started, check for the folder path
            `$detectedFolderPath = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"UserFolder`" -ErrorAction SilentlyContinue).UserFolder
            if(`$detectedFolderPath -and [System.IO.Directory]::Exists(`$detectedFolderPath)){
                Write-Output `"detected user folder at `$detectedFolderPath, linked to tenant `$detectedTenant`"
                break detectO4B
            }
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
    }catch{
        write-error `"Failed to read Onedrive version information from the registry`" -ErrorAction Continue
        `$installedVersionPath = Join-Path `$Env:LOCALAPPDATA -ChildPath `"Microsoft\OneDrive\OneDrive.exe`"
        Write-output `"Will use auto-guessed value of `$installedVersionPath`"
    }

    #RUN THE LOCAL CLIENT IF ALREADY INSTALLED
    Write-Output `"Starting client...`"
    & `$installedVersionPath
}

if(!`$redirectFoldersToOnedriveForBusiness){
    Stop-Transcript
    Exit
}

###DEFINE EXTERNAL FUNCTIONS
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
        `$Target,
        `$CopyContents
    )

    `$Folder = Get-KnownFolderPath -KnownFolder `$GetFolder
    If (`$Folder -ne `$Target) {
        Write-Verbose `"Redirecting `$SetFolder to `$Target`"
        Set-KnownFolderPath -KnownFolder `$SetFolder -Path `$Target
        if(`$CopyContents -and `$Folder){
            Get-ChildItem -Path `$Folder -ErrorAction Continue | Copy-Item -Destination `$Target -Recurse -Container -Force -Confirm:`$False -ErrorAction Continue
        }
        Attrib +h `$Folder
    } Else {
        Write-Verbose `"Folder `$GetFolder matches target. Skipping redirection.`"
    }
}

if(`$detectedFolderPath -and `$redirectFoldersToOnedriveForBusiness){
    `$listOfFoldersToRedirectToOnedriveForBusiness | % {
        Write-Output `"Redirecting `$(`$_.knownFolderInternalName) to `$detectedFolderPath\`$(`$_.desiredSubFolderNameInOnedrive)`"
        try{
            `$Target = Join-Path `$detectedFolderPath -ChildPath `$_.desiredSubFolderNameInOnedrive
            Redirect-Folder -GetFolder `$_.knownFolderInternalName -SetFolder `$_.knownFolderInternalIdentifier -Target `$Target -CopyContents = `$_.copyContents
            Write-Output `"Redirection succeeded`"
        }catch{
            Write-Error `"Failed to redirect this folder!`" -ErrorAction Continue
            Write-Error `$_ -ErrorAction Continue     
        }
    }
}
Stop-Transcript
Exit
"

#######################################################
#
# End ofcode for Local Script for scheduled task to 
# run the script once
#
#######################################################

WriteLog "Determining connection type - VPN vs office, and if on Wired/Wireless LAN"

#Get Connection Type
$WirelessConnected = $null
$WiredConnected = $null
$VPNConnected = $null

# Detecting PowerShell version, and call the best cmdlets
if ($PSVersionTable.PSVersion.Major -gt 2)
{
    # Using Get-CimInstance for PowerShell version 3.0 and higher
    $WirelessAdapters =  Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        'NdisPhysicalMediumType = 9'
    $WiredAdapters = Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        "NdisPhysicalMediumType = 0 and `
        (NOT InstanceName like '%pangp%') and `
        (NOT InstanceName like '%cisco%') and `
        (NOT InstanceName like '%juniper%') and `
        (NOT InstanceName like '%vpn%') and `
        (NOT InstanceName like 'Hyper-V%') and `
        (NOT InstanceName like 'VMware%') and `
        (NOT InstanceName like 'VirtualBox Host-Only%')"
    $ConnectedAdapters =  Get-CimInstance -Class win32_NetworkAdapter -Filter `
        'NetConnectionStatus = 2'
    $VPNAdapters =  Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter `
        "Description like '%pangp%' `
        or Description like '%cisco%'  `
        or Description like '%juniper%' `
        or Description like '%vpn%'"
}
else
{
    # Needed this script to work on PowerShell 2.0 (don't ask)
    $WirelessAdapters = Get-WmiObject -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        'NdisPhysicalMediumType = 9'
    $WiredAdapters = Get-WmiObject -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        "NdisPhysicalMediumType = 0 and `
        (NOT InstanceName like '%pangp%') and `
        (NOT InstanceName like '%cisco%') and `
        (NOT InstanceName like '%juniper%') and `
        (NOT InstanceName like '%vpn%') and `
        (NOT InstanceName like 'Hyper-V%') and `
        (NOT InstanceName like 'VMware%') and `
        (NOT InstanceName like 'VirtualBox Host-Only%')"
    $ConnectedAdapters = Get-WmiObject -Class win32_NetworkAdapter -Filter `
        'NetConnectionStatus = 2'
    $VPNAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter `
        "Description like '%pangp%' `
        or Description like '%cisco%'  `
        or Description like '%juniper%' `
        or Description like '%vpn%'"
}


Foreach($Adapter in $ConnectedAdapters) {
    If($WirelessAdapters.InstanceName -contains $Adapter.Name)
    {
        $WirelessConnected = $true
    }
}

Foreach($Adapter in $ConnectedAdapters) {
    If($WiredAdapters.InstanceName -contains $Adapter.Name)
    {
        $WiredConnected = $true
    }
}

Foreach($Adapter in $ConnectedAdapters) {
    If($VPNAdapters.Index -contains $Adapter.DeviceID)
    {
        $VPNConnected = $true
    }
}

If(($WirelessConnected -ne $true) -and ($WiredConnected -eq $true)){$ConnectionType="WIRED"}
If(($WirelessConnected -eq $true) -and ($WiredConnected -eq $true)){$ConnectionType="WIRED AND WIRELESS"}
If(($WirelessConnected -eq $true) -and ($WiredConnected -ne $true)){$ConnectionType="WIRELESS"}

WriteLog "Connection type for this PC is: $ConnectionType"

If($VPNConnected -eq $true){$ConnectionType="VPN"}

#Write-Output "Connection type is: $ConnectionType"

### Check to see if this endpoint is using the Centralized/single-runtime installation of OneDrive or not
### If machine has the Centralized/single-runtime then check registry for the OneDriveSetup.exe location
### If machine does NOT have the Centralized/single-runtime of OneDrive, assume Windows-bundled OneDriveSetup.exe


If (Test-Path -Path $OneDriveProgFilesPath.FullName) {
	
    $OneDriveVersion = Get-ItemPropertyValue -Path HKLM:\Software\Microsoft\OneDrive -Name Version

    $OneDriveSetupLocation = "C:\Program Files\Microsoft OneDrive\" + $OneDriveVersion + "\OneDriveSetup.exe"
	$OneDriveExe = "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
	#"Path exists!"
	
} else {
	
    $OneDriveSetupLocation = "C:\Windows\SysWOW64\OneDriveSetup.exe"
	$OneDriveExe = $env:localappdata + "\Microsoft\OneDrive\OneDrive.exe"
	#"Path doesn't exist."
}
 
 
 ###Cleans up duplicate Desktop Shortcuts - Comment out to disable this section
 ###
 ### This section cleans up any duplicate Chrome, Teams, or MS Edge shortcuts.
 ###  
 ### To check for other App shortcut duplicate names, add named-entries to the 
 ### $DuplicateNames variable.
 ###
 ### Can also be used to clean up duplicate .url shortcuts as well.
 
$DesktopPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath "*"


$DuplicateNames = @(
    "*Edge*",
    "*Teams*",
    "*Chrome*"
)

Get-ChildItem -Path $DesktopPath -Filter *.lnk -Include $DuplicateNames | Where {$_.Name -like "*-*.lnk"} | Remove-Item -Force
Get-ChildItem -Path $DesktopPath -Filter *.url -Include $DuplicateNames | Where {$_.Name -like "*-*.url"} | Remove-Item -Force
 

 ### If the Migration Flag File is not present, perform the Full One Drive Setup in silent mode, 
 ### migrate Worl Folder data, and Set Registry to run OneDrive 
 ###
 ### Else - check if on VPN and if Migration Flag File is < 24 hrs old, perform re-run of OneDrive Setup
 ### without any migration of WF Data
 ###
    $MigrateWorkFolders = $null
 
	If (Test-Path -Path $FirstOneDriveCompletePath.FullName) {
		
		## Are we on VPN?  

		If(($ConnectionType -eq "VPN")){
	
		WriteLog "ConnectionType is:  $ConnectionType"
		#	$ConnectionType
		$fileObj = Get-Item -Path $FirstOneDriveComplete
		# Creation Date
		if (($fileObj.CreationTime) -lt (Get-Date).AddHours(-24)) {
			
			#Write-Output "Old file"
			
		} else {
			#Write-Output "New file"
		WriteLog "Connection type is: $ConnectionType"
		Start-Process -FilePath $OneDriveSetupLocation -ArgumentList "/silent"
		Start-Sleep -Seconds 15
		$OneDriveUserRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
		$OneDriveUserRegValName = "OneDrive"
		$OneDriveRegVal = $OneDriveExe + " /background"
		New-ItemProperty -Path $OneDriveUserRegPath -Name $OneDriveUserRegValName -Value $OneDriveRegVal -PropertyType String -Force 
		Start-Process -FilePath $OneDriveExe -ArgumentList "/background"
	
		
		}
	
			} Else {
		
			WriteLog "Connection type is: $ConnectionType"
			WriteLog "Not on VPN"
			#Make sure OneDrive Autorun is set, trigger OneDrive to run, then move on to Shell Folder Chk
			
			$fileObj = Get-Item -Path $FirstOneDriveComplete
			# Creation Date
		  if (($fileObj.CreationTime) -lt (Get-Date).AddHours(-24)) {
			
			#Write-Output "Old file"
			
		  } else {
			#Write-Output "New file"
			$OneDriveUserRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
			$OneDriveUserRegValName = "OneDrive"
			$OneDriveRegVal = $OneDriveExe + " /background"
			New-ItemProperty -Path $OneDriveUserRegPath -Name $OneDriveUserRegValName -Value $OneDriveRegVal -PropertyType String -Force 
			Start-Process -FilePath $OneDriveExe -ArgumentList "/background"
		  }
			#	$ConnectionType

		WriteLog "OneDrive Migration Flagfile exists, will not perform migration tasks."
		Log-InformationalEvent("First OneDrive flag file exists for " + $env:USERNAME + "")
		
		Exit (0)
}
		
		WriteLog "OneDrive Migration Flagfile exists, will not perform migration tasks."
		Log-InformationalEvent("First OneDrive flag file exists for " + $env:USERNAME + "")
		
		
	} Else {
		
		WriteLog "ConnectionType is $ConnectionType"
		WriteLog "Beginning OneDrive Migration tasks..."
		
		# Ensure that OneDrive sync is not disabled

		$OneDriveEnabledRegPath1 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
		$OneDriveEnabledRegValName1 = "DisableFileSyncNGSC"
		$OneDriveEnabledRegVal1 = "00000000"
		New-ItemProperty -Path $OneDriveEnabledRegPath1 -Name $OneDriveEnabledRegValName1 -Value $OneDriveEnabledRegVal1 -PropertyType DWord -Force 

		$OneDriveEnabledRegPath2 = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\OneDrive"
		$OneDriveEnabledRegValName2 = "DisableFileSyncNGSC"
		$OneDriveEnabledRegVal2 = "00000000"
		New-ItemProperty -Path $OneDriveEnabledRegPath2 -Name $OneDriveEnabledRegValName2 -Value $OneDriveEnabledRegVal2 -PropertyType DWord -Force

		# Using $OneDriveSetupLocation variable set earlier, launch OneDriveSetup.exe in silent mode

		Start-Process -FilePath $OneDriveSetupLocation -ArgumentList "/silent"
		Start-Sleep -Seconds 15
		Start-Process -FilePath $OneDriveExe -ArgumentList "/background"
		#Path is " + $OneDriveLocation
    	New-Item -Path $FirstOneDriveComplete -type file -force
		$OneDriveUserRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
		$OneDriveUserRegValName = "OneDrive"
		$OneDriveRegVal = $OneDriveExe + " /background"
		New-ItemProperty -Path $OneDriveUserRegPath -Name $OneDriveUserRegValName -Value $OneDriveRegVal -PropertyType String -Force 
		
        #robocopy "$WorkFoldersPath" "$OneDriveUserPath" /S /Move
        $MigrateWorkFolders = True
		#Start-Sleep -Seconds 5
		gpupdate /target:user
	}

# Remove Work Folders Sync URL and Set AutoProvision to Zero (0)

$WorkFoldersRegPath = "HKCU:\Software\Policies\Microsoft\Windows\WorkFolders"
$WorkFoldersSyncURL = "SyncUrl"
$WorkFoldersAutoProvisionVal = "0"

Remove-ItemProperty -Path $WorkFoldersRegPath -Name $WorkFoldersSyncURL -Force 

New-ItemProperty -Path $WorkFoldersRegPath -Name "AutoProvision" -Value $WorkFoldersAutoProvisionVal -PropertyType DWord -Force 


# Set (or Re-tatoo if GPO is being used) OneDrive Folder-Redirection Settings to ensure OneDrive Path is used by Windows Explorer 
# Known Folders and integrated shortcuts - instead of WF Paths
# 
# Set Windows Profile Settings variables

$UserShellRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

$RedirectDocumentsRegVal = "$OneDriveUserPath\Documents"
$LocalDocumentsRegValName = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"
$DocumentsRegValName = "Documents"
$PersonalRegValName = "Personal"
$LocalPicturesRegValName = "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
$PicturesRegValName = "My Pictures"
$RedirectPicturesRegVal = "$OneDriveUserPath\Pictures"
$RedirectDesktopRegVal  = "$OneDriveUserPath\Desktop"
$LocalDesktopRegValName = "{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}"
$DesktopRegValName = "Desktop"
$ReDirectFavoritesRegVal = "$OneDriveUserPath\Favorites"
$FavoritesRegValName = "Favorites"

# Read the current Registry Values into Variables

$LocalDocumentsRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $LocalDocumentsRegValName
$DocumentsRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $DocumentsRegValName
$LocalDesktopRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $LocalDesktopRegValName
$DesktopRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $DesktopRegValName
$LocalPicuturesRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $LocalPicturesRegValName
$PicuturesRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $PicturesRegValName
$FavoritesRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $FavoritesRegValName
$PersonalRegData = Get-ItemProperty -Path $UserShellRegPath | Select-Object -ExpandProperty $PersonalRegValName

# Begin Checks to see if any Windows Shell registry entries are set to "Work Folders" path, and correct to OneDrive path if needed

If ($PersonalRegData = "$env:userprofile\Work Folders\Documents") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $PersonalRegValName -Value $RedirectDocumentsRegVal -PropertyType ExpandString -Force 
	WriteLog "Setting Personal Reg Documents Path"	
		
} Else {
	
	WriteLog "Personal Reg Documents Path is set to OneDrive"	
}

If ($DocumentsRegData = "$WorkFoldersPath\Documents") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $DocumentsRegValName -Value $RedirectDocumentsRegVal -PropertyType ExpandString -Force 
		WriteLog "Setting Documents Registry Path Redirection Settings"	
		
} Else {

	WriteLog "Documents Registry Path Redirection is set to OneDrive"		
}


If ($LocalDocumentsRegData = "$WorkFoldersPath\Documents") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $LocalDocumentsRegValName -Value $RedirectDocumentsRegVal -PropertyType ExpandString -Force 
		WriteLog "Setting Documents Folder Redirection Path"	
		
} Else {
	
	WriteLog "Documents Folder Redirection Path is set to OneDrive"
}

If ($LocalDesktopRegData = "$WorkFoldersPath\Desktop") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $LocalDesktopRegValName -Value $RedirectDesktopRegVal -PropertyType ExpandString -Force 
		
		WriteLog "Setting Desktop Folder Redirection Path"	
		
} Else {

	WriteLog "Desktop Folder Redirection Path is set to OneDrive"		
}

If ($DesktopRegData = "$WorkFoldersPath\Desktop") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $DesktopRegValName -Value $RedirectDesktopRegVal -PropertyType ExpandString -Force 
		
		WriteLog "Setting Personal Reg Desktop Path"
		
} Else {

	WriteLog "Personal Reg Desktop Path is set to OneDrive"
}

If ($PicuturesRegData = "$WorkFoldersPath\Pictures") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $PicturesRegValName -Value $RedirectPicturesRegVal -PropertyType ExpandString -Force 
		
		WriteLog "Setting Pictures Reg Desktop Path"
		
} Else {

	WriteLog "Pictures Reg Desktop Path is set to OneDrive"
}

If ($LocalPicuturesRegData = "$WorkFoldersPath\Pictures") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $LocalPicturesRegValName -Value $RedirectPicturesRegVal -PropertyType ExpandString -Force 
		
		WriteLog "Setting Pictures Folder Redirection Path"	
		
} Else {
	
	WriteLog "Pictures Folder Redirection Path is set to OneDrive"	
}

If ($FavoritesRegData = "$WorkFoldersPath\Favorites") {
	
	New-ItemProperty -Path $UserShellRegPath -Name $FavoritesRegValName -Value $ReDirectFavoritesRegVal -PropertyType ExpandString -Force 

	WriteLog "Setting Favorites Folder Redirection Path"	
		
} Else {

	WriteLog "Favorites Folder Redirection Path is set to OneDrive"
}
	

#Exit Script
	Log-InformationalEvent("Work Folders to OneDrive Migration Script-run completed for " + $env:UserName)
	
	WriteLog "WF to OneDrive Migration Script-Run Complete"


	#Start-ScheduledTask -TaskName "OnedriveAutoConfig"
	
	#	$wshell = New-Object -ComObject Wscript.Shell	
	#	$wshell.Popup("Script completed",0,"Done",0x1)

	Exit (0)


