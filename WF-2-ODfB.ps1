#Requires -Version 5.1
#Requires -PSEdition Desktop
<#
    Name: WF-2-ODfB.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West
    Creative GNU General Public License, version 3 (GPLv3);
.SYNOPSIS
    Set up OneDrive for Business and migrate active Work Folders data to OneDrive 
.DESCRIPTION
    This script will migrate a Windows 10 Endpoint's User data sync settings
    from Work Folders over to OneDrive for Business.  It is targeted to silently run 
    OneDrive Setup (see note below), moves data from Work Folders to OneDrive folder via
    Robocopy /Move, and sets redirection for Known Folders. 
    Requirements: Windows 10, Powershell 5.1 or above
.LINK
    https://github.com/J-DubApps
    #>

###############################################################################################
#
#			WorkFolders-To-OneDrive for Business Migration v 0.4.x
#			    WF-2-ODfB.ps1
#
#	Description 
#		This script is designed to be run against an endpoint with or without Admin rights (it will run differently
#       based on an "IsAdmin" check).   This script sets OneDrive HKLM settings, then creates a Runtime script to 
#       Install OneDrive for each user on a Windows 10 Endpoint, and can also igrate each user's Work Folder sync 
#       configuration (and data) over to OneDrive for Business, and lastly the Runtime script can redirect any 
#       Known Folders that you require to be redirected (set below). The Configuration / Runtime script uses 
#       Robocopy to MOVE data from the user's previous Work Folders Root over to their OneDrive folder via Robocopy.
#       
#       This Deployment (Main) script, and the Runtime script it creates, are designed to be run non-elevated and
#       without Admin rights; however, if you wish to have the Runtime script perform as a Scheduled Task on
#       and endpoint, you must run this Deployment script itself once with Admin rights (deployed via MECM etc).
#
#       When run with non-Admin rights, the Config / Runtime script will set itself to be run as a 
#       via the Windows "Run" registry key under HKCU.  Runtime script can still perform a OneDrive for 
#       Business client install, Known Folder redirection, and Work Folder data migration this way; however: the 
#       Runtime script is more reliable if this Deployment script is run elevated or deployed and run once
#       as SYSTEM (via MECM, etc).
#
#       The Config / Runtime script runs HIDDEN and silent (no PS window is seen by the user), 
#       and can run multiple times via Scheduled Tasks (ideal for hybrid Remote Worker PCs, Endpoint PCs
#       with multiple-users, or other scenarios where interruptions may occur).  
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
#       You should have working-understanding of how OneDrive for Business, Powershell, and Scheduled Tasks work
#       to fully-understand how to use this script, and the Config / Runtime script it generates.
#       YOU ARE WARNED that you must fully-test this script on an isolated PC endpoint in a lab/test setting,
#       before ever running it in a production environment. By using this code you agree to the terms of the LICENSE
#       below, including waiving any liability for any and all effects caused by using this script. 
#
#       REQUIREMENTS: Script has no required Parameters but does have REQUIRED variables you must edit below, for your 
#       O365 Tenant's OneDrive settings. These need to be set before running tests & deployment. Script
#       will not work without these variables set!
#
#       PS VERSION NOTE: Script was developed in, and targeted for, PowerShell 5.1 and Windows 10 1709 and higher. 
#       It will not wrun on earlier versions of PS, and is intended to operate in the "sweet spot" of Win10 and 
#       the version of PS that ships with it.   This script may work in PS 6+, but it is not guaranteed.
#
#       GPO NOTE:  
#       If you configured Work Folders and OneDrive settings via GPOs in your environment, it is important that you
#       un-commment & set a REQUIRED variable below, "$WorkFoldersName".  See notes below next to the variable.
#
#       During its run, this Deploy script "paves the way" for the Config / Runtime Script.  So this script doesn't 
#       perform any Data Migration or OneDrive lanuching, it leaves that to the separate Runtime script, which it
#       stages under C:\ProgramData within a "WF-2-ODfB" folder.  
#
#       This Script also has a several OPTIONAL variables you can set to control what it will do, including: 
#
#       enableFilesOnDemand - True/False (Default False)
#       enableDataMigration - True/False (Default True)
#       redirectFoldersToOnedriveForBusiness - True/False (Default True)
#
#       This script will ONLY enable OneDrive's FilesOnDemand option if run with elevated rights, as  
#       the Config / Runtime Script ALWAYS runs non-elevated for the PC endpoint user (non-Admin).
#       If your deployment scenario is to non-Admin users, I recommend ignoring this setting.  If you need
#       FilesOnDemand mode to be enabled, consider deploying this script onnce to run with Admin rights via MECM
#       or other deployment tool.  While this script *can* be run without Admin rights, you lose the ability to set
#       FilesOnDemand this way.  Alternatively, you could enable this feature by publishing the needed registry 
#       setting via InTune or GPO (in which case you should leave enableFilesOnDemand set to 'false' in this script).
#       
#       For all OneDrive environment config items under HKLM area of the Registry, they are performed here in this
#       Deployment script only if it is run at least ONCE using Admin rights. 
#
#       The Config / Runtime script is launched using "-executionpolicy ByPass" PowerShell.exe 
#       script parameters.  You can also sign the script (not in-scope of this documentation).  
#
#       This script can also be deployed via GPO Logon Script, or be called by an existing PS Logon Script, but bear in mind it 
#       can not run Elevated this way.  
#
#       NOTE1: To leverage automatic sign-in for OneDrive, your Windows Endpoints must be configured 
#           for Hybrid Azure AD join.  Otherwise your users must enter credentials into OneDrive the first time.
#
#           More info here: https://docs.microsoft.com/en-us/azure/active-directory/devices/concept-azure-ad-join-hybrid
#                           https://docs.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-plan  
#
#       NOTE2: If MFA is enabled, automatic sign-in for OneDrive will not occur during the OneDrive client setup. 
#       This means as a "last step", after data is silently migrated, your users must enter their credentials into 
#       the OneDrive Client to sign in.  With MFA enabled, redirection and data migration remain a ‘silent’ background process,
#       with the user needing to sign-in to OneDrive at the end.
#       
#       NOTE3: Additional background migration runs are rarely-needed, but if you need repeated runs of the Config / Runtime 
#       script, this Deployment script must be run once with Admin Rights.  
#
#       Again: the Config / Runtime script does NOT require having itself run as a Scheduled Tasks to be successful, 
#       it simply offers the ability to be re-run as a background process so that the user does not need to log out
#       and back in to get the migration steps done.  
#
# 	LICENSE: GNU General Public License, version 3 (GPLv3); http://www.gnu.org/licenses/gpl-3.0.html
#
#   You are free to make any changes to your own copy of this script, provided you give attribution of the original source
#   and you agree that you cannot hold the original author responsible for any issues resulting from this script.
#
#  I welcome forks or pulls and will be happy to help improve the script for anyone if I have the time.
#
#    Please do feel free share any deployment success, or script ideas, with me: jdub.writes.some.code(at)gmail(dot)com
#
#  TL;DR*
#
# 1. Anyone can copy, modify and distribute this software.
# 2. You have to include the license stated here, and any copyright notices with each and every distribution.
# 3. You can use this software privately or commercially.  
# 4. You are NOT authorized to use this software in any sealed-source software.
# 5. If you dare build a business engagement from this code, you open-source all mods.
# 6. If you modify it, you have to indicate changes made to the code.
# 7. Any modifications of this code base MUST be distributed with the same license, GPLv3.
# 8. This software is provided without warranty.
# 9. The software author or license can not be held liable for any damages inflicted by the software.
# 10. Feel free to reach out to author to share usage, ideas etc jdub.writes.some.code(at)gmail(dot)com
#
###############################################################################################
#
# Mentions / articles used:
# References Some common techniques and methods utilized in O4BClientAutoConfig.ps1 written by Jos Lieben @ https://www.lieben.nu/liebensraum/o4bclientautoconfig/
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
#   02/12/2022              Initial version by Julian West
#   03/06/2022  (JW)        Configure variables for location differences
#   03/15/2022  (JW)        Remove Move/Copy functions and leverage Robocopy (pre-installed on Win10)
#   03/17/2022  (JW)        Final testing round with GPO/GPP Registry entries for pre-migration settings
#   03/29/2022  (JW)        Updated to clean up duplicate Desktop Shortcuts (optional, un-comment to run)
#   04/04/2022  (JW)        Updated to log activities to a log file
#   04/04/2022  (JW)        Update for Registry path checks to current redirected Shell folders
#   04/05/2022  (JW)        Trigger OneDrive Setup to run if on VPN and Migration Flagfile < 24 hrs old 
#   04/10/2022  (JW)        Remove original employer specific code
#   04/15/2022  (JW)        Update for "Deployment Mode" (trigger Migration Runtime Script for other PC Endpoint users)
#   05/05/2022  (JW)        Update allow "Secondary PCs" to "catch-up" when a user is migrated on their Primary PC.
#   05/09/2022  (JW)        Runtime tests for MECM, Intune, and GPO-based deployments of this script
#   05/11/2022  (JW)        Final Testing "Runtime Migration Script" operation on Windows 10 Domain member PCs 
#
###############################################################################################

#-----------------------------------------------------------[Execution]------------------------------------------------------------
[CmdletBinding()]
PARAM(	
	[parameter(ValueFromPipeline=$true,
				ValueFromPipelineByPropertyName=$true,
				Mandatory=$false)]
	[switch]$DeployRunTimeScriptOnly=$false
)

### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, needed for successful script run.  Set to your own env values - 
#

$OneDriveFolderName = "OneDrive - Tenant Name" #  <--- This is your Tenant OneDrive folder name (can be confirmed via manual install of ODfB client)
# **required - this is the OneDrive folder name that will exist under %USERPROFILE%
# This folder is usually named from your O365 Tenant's Org name by default, or is customized in GPO/Registry.
# This default folder name can be confirmed via a single manual install of OneDrive on a standalone Windows endpoint
#
$PrimaryTenantDomain = "yourO365domain.com"
# **required - this is your Primary Office 365 domain used in your User Principal Names / UPN.
# The script will use this domain to obtain your TenantID and perform other OneDrive setup functions.
#
#$WorkFoldersName = "Work Folders"  # <--- Your Work Folders root folder name, which you can set or let script auto-populate from HKCU of the Endpoint user. 
# **required - You can set this manually, and this is recommended.  Otherwise script attempts to determine Work Folders root folder from 
# HKCU\Software\Policies\Microsoft\Windows\WorkFolders @ "LocalFolderPath" REG_SZ value -- to populate the $WorkFoldersName variable.   
# The WF root folder is typically found at the root of %USERPROFILE% on your endpoints.  When manually setting the above variable do not include 
# any DRIVE / PATH info, only the FOLDER NAME should be used.   
# You absolutely should manually set this if you are using the following GPO setting during your migration, as it speeds along disabling Work Folders:
# User Configuration --> Admin Templates --> Windows Components --> Work Folders --> ENTRY "Specify Work Folders Settings" set to "Disabled" 
# This script will otherwise "Auto" set this variable in environments where GPO was not used to manage Work Folder settings.

#
##
### End of *REQUIRED* Variables -- 

###############################################################################################

### OPTIONAL CONFIGURATION ###
## *OPTIONAL* Variables - please review & configure for optimum operation in your environment! 
#

$enableDataMigration = $True # <---- Set to "False" if you don't want to migrate any WF data: Work Folders are IGNORED even if they exist, only OneDrive Client setup & folder redirection is performed.
$redirectFoldersToOnedriveForBusiness = $True # <--- Set to "False" if you do not wish to have Known Folders redirected.  Default is True & controlled by the "KNOWN FOLDERS ARRAY" section few lines down.
#   NOTE: If the you get an "access denied error" during the Folder Redirection phase of the Runtime Script, your environment may have a GPO to "Prohibit User from manually redirecting Profile Folders" 
#       in place.  If Known Folders cannot be redirected, the script will fallback to "Basic" redirection via Registry mods for only the 4 Default folders: Desktop, Documents, Favorites, and Pictures.
$attemptKFM = $False # <--- Leave $False unless you want this solution to attempt to Known Folder redirection, instead of basic direct Folder Redirection.  NOT recommended unless you are deploying to new Endpoints that have never
#   had previous folder redirection configured (in GPO or otherwise).  Managed Endpoints using Work Folders shouldn't attempt KFM as the success-rate is variable and less reliable - which is why this script exists!
$skipScheduledTaskCreation = $False # <---- Set to "True" if you do NOT want this script to create a Scheduled Task during run.  DeployRunTimeScriptOnly variable below renders this setting to "True".
$triggerRuntimeScriptHere = $False # <---- Default = "False". Set to "True" if want this Deployment / Main Script to also launch the Runtime Script at the end (rare). DeployRunTimeScriptOnly variable below renders this setting to "False". 
$DeployMode = $True # <---- Set to "True" to stage the Runtime Script & deploy the Scheduled Task -or- Registry Run entry to run it, and NOT run any migration-attempt for the account running *THIS* (Main) script.  
#   NOTE: DeployMode setting is intended for scenarios like MECM Deployment to remote PC endpoints, or when you want migration to run for other users of a PC endpoint, etc. 
$enableFilesOnDemand = $False # <---- Default = "False" and setting to "True" will requires this Main Script to run ONCE with Admin rights to enable this OneDrive feature.  This setting requires Win 10 1709 minimum or higher.
$cleanDesktopDuplicates = $False # <---- Set to True if you want the Runtime script to clean up a user's duplicate Desktop Shortcuts before Work Folders data migration.
$GPO_Refresh = $True # <---- Set to "True" if you want to the Config / Runtime Script to perform a refresh of Group Policies at the end of its setup/config/migration run.  Helps get GPOs in place if needed. Default is "True".
#   NOTE: Because GPO has a variable "time-to-live" to disable Work Folders ~90 minutes, I recommend leaving GPO_Refresh enabled if you're  also using GPO to disable or remove Work Folders settings.

#$TenantID = "00000000-0000-0000-0000-000000000000" # <--- Your Tenant ID, which is a GUID you can find at the link below and populate, or just let the Runtime Script attempt to 
# auto-detect it based off of the $PrimaryTenantDomain variable above. Just set it manually if you already know your Office 365 Tenant ID.  This is not a required variable yet, but may be in the future.
#
# https://docs.microsoft.com/en-us/onedrive/find-your-office-365-tenant-id
#

$xmlDownloadURL = "https://g.live.com/1rewlive5skydrive/ODSUInsider"
$minimumOfflineVersionRequired = 19
$logFileX64 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx64.log"    #Tracelog file for x64
$logFileX86 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx86.log"    #Tracelog file for x86

$LogFileName = "ODfB_MigChecks-$env:username.log"   # <-- General Log file name (less detail than TraceLog, audience is IT or end user)
# This is the Log File name where activites will be logged, saved to current %userprofile%\$LogFileName.
# In addition to the above logs, a Robocopy log is generated @ %userprofile%Start-Robocopy-timestamp.log for any data migrated.
#

$MigrationFlagFileName = "FirstOneDriveComplete.flg"
# This is the Migration Flag File which is created during WF to OneDrive data migration steps
# It is saved during Runtime to: %userprofile%\$OneDriveFolderName\$MigrationFlagFileName
#

# $DeployRunTimeScriptOnly = $true  # Outputs the Runtime/migration script ONLY, and does nothing else.  
# Un-comment the above when Debugging/Testing Runtime script, or run the script manually with Parameter Switch "-DeployRunTimeScriptOnly"  
# Script does nothing execept ONLY writing the WF-2-ODfB-Mig.ps1 Runtime script then exits.  Script will not set OD Registry entires, nor will it 
# disable Work Folder sync or create a Scheduled Task or Registry Run entry.  This option allows you to create the Runtime Script, without Deployment Script doing anything else.  
# Intended for Sandbox testing on multiple PCs or environments prior to prod deployment.
# Script will place the Runtime Script in the same directory it is run from ( $PSScriptRoot ).   

If($DeployRunTimeScriptOnly -eq $true){
    $DeployMode = $false
    $enableFilesOnDemand = $false
    $skipScheduledTaskCreation = $true
    $triggerRuntimeScriptHere = $False 
}

# Set Variables for Location for the Config / Runtime script-placement and script-names
If($DeployRunTimeScriptOnly -ne $true){
    $setRuntimeScriptFolder = Join-Path $Env:ProgramData -ChildPath "WF-2-ODfB"
}else{
    $setRuntimeScriptFolder = $PSScriptRoot
}

$setRuntimeScriptPath = Join-Path $setRuntimeScriptFolder -ChildPath "WF-2-ODfB-Mig.ps1"
$setPSRuntimeLauncherPath = Join-Path $setRuntimeScriptFolder -ChildPath "WF-2-ODfB-Mig.vbs"

###KNOWN FOLDERS ARRAY### <-- Below is the list of known folders that will be checked for redirection: MODIFY AS NEEDED!

#Here you enable Redirection for the listed Known Folders below
#Default is to redirect only 4 "well-known" Known Folders (Desktop, Documents, Favorites, and Pictures) so you will need to modify as needed.
#You can disable Known Fodler recirection by setting the $redirectFoldersToOnedriveForBusiness variable to $False.

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

Function LogInformationalEvent($Message){
#########################################################################
#	Writes an informational event to the event log
#########################################################################
$QualifiedMessage = $ClientName + " Script: " + $Message
Write-EventLog -LogName Application -Source Winlogon -Message $QualifiedMessage -EventId 1001 -EntryType Information
}

Function LogWarningEvent($Message){
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
    #Will only return true if the script is also running in script is running in an elevated PowerShell session.
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
##	Return True/False on Registry value 
##########################################################################

function Test-RegistryKeyValue {

    param (
    
     [parameter(Mandatory=$true)]
     [ValidateNotNullOrEmpty()]$Path,
    
    [parameter(Mandatory=$true)]
     [ValidateNotNullOrEmpty()]$Name
    )
    
    try {
    
    Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Name -ErrorAction Stop | Out-Null
     return $true
     }
    
    catch {
    
    return $false
    
     }
    
    }
    


##########################################################################
##	Function to Create a new Scheduled Task definition
##########################################################################
function New-Task
{
    <# 
    .Synopsis 
        Creates a new task definition. 
    .Description 
        Creates a new task definition. 
        Tasks are not scheduled until Register-ScheduledTask is run. 
        To add triggers use Add-TaskTrigger. 
        To add actions, use Add-TaskActions 
    .Link 
        Add-TaskTrigger 
        Add-TaskActions 
        Register-ScheduledTask 
    .Example 
        An example of using the command 
    #>
    param(
    # The name of the computer to connect to.
    $ComputerName,
    
    # The credential used to connect
    [Management.Automation.PSCredential]
    $Credential,
    
    # If set, the task will wake the computer to run
    [Switch]
    $WakeToRun,
    
    # If set, the task will run on batteries and will not stop when going on batteries
    [Switch]
    $RunOnBattery,
    
    # If set, the task will run only if connected to the network
    [Switch]
    $RunOnlyIfNetworkAvailable,
    
    # If set, the task will run only if the computer is idle
    [Switch]
    $RunOnlyIfIdle,
    
    # If set, the task will run after its scheduled time as soon as it is possible
    [Switch]
    $StartWhenAvailable,
    
    # The maximum amount of time the task should run
    [Timespan]
    $ExecutionTimeLimit = (New-TimeSpan),
    
    # Sets how the task should behave when an existing instance of the task is running.
    # By default, a 2nd instance of the task will not be started
    [ValidateSet("Parallel", "Queue", "IgnoreNew", "StopExisting")]
    [String]
    $MultipleInstancePolicy = "IgnoreNew",

    # The priority of the running task 
    [ValidateRange(1, 10)]
    [int]
    $Priority = 6,
    
    # If set, the new task will be a hidden task
    [Switch]
    $Hidden,
    
    # If set, the task will be disabled 
    [Switch]
    $Disabled,
    
    # If set, the task will not be able to be started on demand
    [Switch]
    $DoNotStartOnDemand,
    
    # If Set, the task will not be able to be manually stopped
    [Switch]
    $DoNotAllowStop,
    
    # If set, runs the task elevated
    [Switch]
    $Elevated
    )
        
    $scheduler = Connect-ToTaskScheduler -ComputerName $ComputerName -Credential $Credential            
    $task = $scheduler.NewTask(0)
    $task.Settings.Priority = $Priority
    $task.Settings.WakeToRun = $WakeToRun
    $task.Settings.RunOnlyIfNetworkAvailable = $RunOnlyIfNetworkAvailable
    $task.Settings.StartWhenAvailable = $StartWhenAvailable
    $task.Settings.Hidden = $Hidden
    $task.Settings.RunOnlyIfIdle = $RunOnlyIfIdle
    $task.Settings.Enabled = -not $Disabled
    if ($RunOnBattery) {
        $task.Settings.StopIfGoingOnBatteries = $false
        $task.Settings.DisallowStartIfOnBatteries = $false
    }
    $task.Settings.AllowDemandStart = -not $DoNotStartOnDemand
    $task.Settings.AllowHardTerminate = -not $DoNotAllowStop
    if ($elevated) {
        $task.Principal.RunLevel = (-not $Elevated) -as [uint32]
    }
    switch ($MultipleInstancePolicy) {
        Parallel { $task.Settings.MultipleInstances = 0 }
        Queue { $task.Settings.MultipleInstances = 1 }
        IgnoreNew { $task.Settings.MultipleInstances = 2}
        StopExisting { $task.Settings.MultipleInstances = 3 } 
    }
    $task
}

##########################################################################
##	Function to Add Additional Trigger to Existing Scheduled Task
##########################################################################

function Add-TaskTrigger
{
    <# 
    .Synopsis 
        Adds a trigger to an existing task. 
    .Description 
        Adds a trigger to an existing task. 
        The task is outputted to the pipeline, so that additional triggers can be added. 
    .Example 
        New-task | 
            Add-TaskTrigger -DayOfWeek Monday, Wednesday, Friday -WeeksInterval 2 -At "3:00 PM" | 
            Add-TaskAction -Script { Get-Process | Out-GridView } | 
            Register-ScheduledTask TestTask 
    .Link 
        Add-TaskAction 
    .Link 
        Register-ScheduledTask 
    .Link 
        New-Task 
    #>
    [CmdletBinding(DefaultParameterSetName="OneTime")]
    param(
    # The Scheduled Task Definition. A New definition can be created by using New-Task
    [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true)]
    [Alias('Definition')]
    $Task,
    
    # The At parameter is used as the start time of the task for several different trigger types.
    [Parameter(Mandatory=$true,ParameterSetName="Daily")]        
    [Parameter(Mandatory=$true,ParameterSetName="DayInterval")]    
    [Parameter(Mandatory=$true,ParameterSetName="Monthly")]
    [Parameter(Mandatory=$true,ParameterSetName="MonthlyDayOfWeek")]
    [Parameter(Mandatory=$true,ParameterSetName="OneTime")]    
    [Parameter(Mandatory=$true,ParameterSetName="Weekly")]
    [DateTime]
    $At,
    
    # Day of Week Trigger
    [Parameter(Mandatory=$true, ParameterSetName="Weekly")]
    [Parameter(Mandatory=$true, ParameterSetName="MonthlyDayOfWeek")]
    [ValidateSet("Sunday","Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")]
    [string[]]
    $DayOfWeek,
    
    # If set, will only run the task N number of weeks
    [Parameter(ParameterSetName="Weekly")]
    [Int]
    $WeeksInterval = 1,
    
    # Months of Year
    [Parameter(Mandatory=$true, ParameterSetName="Monthly")]
    [Parameter(Mandatory=$true, ParameterSetName="MonthlyDayOfWeek")]
    [ValidateSet("January","February", "March", "April", "May", "June", 
        "July", "August", "September","October", "November", "December")]
    [string[]]
    $MonthOfYear,
    
    # The day of the month to run the task on
    [Parameter(Mandatory=$true, ParameterSetName="Monthly")]
    [ValidateRange(1,31)]
    [int[]]
    $DayOfMonth,
    
    # The weeks of the month to run the task on. 
    [Parameter(Mandatory=$true, ParameterSetName="MonthlyDayOfWeek")]    
    [ValidateRange(1,6)]
    [int[]]
    $WeekOfMonth,
    
    # The timespan to run the task in.
    [Parameter(Mandatory=$true,ParameterSetName="In")]
    [Timespan]
    $In,
        
    # If set, the task will trigger at a specific time every day
    [Parameter(ParameterSetName="Daily")]
    [Switch]
    $Daily,

    # If set, the task will trigger every N days
    [Parameter(ParameterSetName="DaysInterval")]    
    [Int]
    $DaysInterval,             
    
    # If set, a registration trigger will be created
    [Parameter(Mandatory=$true,ParameterSetName="Registration")]
    [Switch]
    $OnRegistration,
    
    # If set, the task will be triggered on boot
    [Parameter(Mandatory=$true,ParameterSetName="Boot")]
    [Switch]
    $OnBoot,
    
    # If set, the task will be triggered on logon.
    # Use the OfUser parameter to only trigger the task for certain users
    [Parameter(Mandatory=$true,ParameterSetName="Logon")]
    [Switch]
    $OnLogon,
    
    # In Session State tasks or logon tasks, determines what type of users will launch the task
    [Parameter(ParameterSetName="Logon")]
    [Parameter(ParameterSetName="StateChanged")]
    [string]
    $OfUser,
    
    # In Session State triggers, this parameter is used to determine what state change will trigger the task
    [Parameter(Mandatory=$true,ParameterSetName="StateChanged")]
    [ValidateSet("Connect", "Disconnect", "RemoteConnect", "RemoteDisconnect", "Lock", "Unlock")]
    [string]
    $OnStateChanged,
    
    # If set, the task will be triggered on Idle
    [Parameter(Mandatory=$true,ParameterSetName="Idle")]
    [Switch]
    $OnIdle,
    
    # If set, the task will be triggered whenever the event occurs. To get an event record, use Get-WinEvent
    [Parameter(Mandatory=$true, ParameterSetName="Event")]    
    $OnEvent,
    
    # If set, the task will be triggered whenever the event query occurs. The query is in xpath.
    [Parameter(Mandatory=$true, ParameterSetName="EventQuery")]
    [string]
    $OnEventQuery,

    # The interval the task should be repeated at.
    [Timespan]
    $Repeat,
    
    # The amount of time to repeat the task for
    [Timespan]
    $For,
    
    # The time the task should stop being valid
    [DateTime]
    $Until    
    )
    
    begin {
        Set-StrictMode -Off
    }
    process {
        if ($Task.Definition) {  $Task = $Task.Definition }
        
        switch ($psCmdlet.ParameterSetName) {
            StateChanged {
                $Trigger = $Task.Triggers.Create(11)
                if ($OfUser) {
                    $Trigger.UserID = $OfUser
                }
                switch ($OnStateChanged) {
                    Connect { $Trigger.StateChange = 1 }
                    Disconnect { $Trigger.StateChange = 2 }
                    RemoteConnect { $Trigger.StateChange = 3 }
                    RemoteDisconnect { $Trigger.StateChange = 4 }
                    Lock { $Trigger.StateChange = 7 }
                    Unlock { $Trigger.StateChange = 8 } 
                }
            }
            Logon {
                $Trigger = $Task.Triggers.Create(9)
                if ($OfUser) {
                    $Trigger.UserID = $OfUser
                }
            }
            Boot {
                $Trigger = $Task.Triggers.Create(8)
            }
            Registration {
                $Trigger = $Task.Triggers.Create(7)
            }
            OneTime {
                $Trigger = $Task.Triggers.Create(1)
                $Trigger.StartBoundary = $at.ToString("s")
            }            
            Daily {
                $Trigger = $Task.Triggers.Create(2)
                $Trigger.StartBoundary = $at.ToString("s")
                $Trigger.DaysInterval = 1
            }
            DaysInterval {
                $Trigger = $Task.Triggers.Create(2)
                $Trigger.StartBoundary = $at.ToString("s")
                $Trigger.DaysInterval = $DaysInterval                
            }
            Idle {
                $Trigger = $Task.Triggers.Create(6)
            }
            Monthly {
                $Trigger =  $Task.Triggers.Create(4)
                $Trigger.StartBoundary = $at.ToString("s")
                $value = 0
                foreach ($month in $MonthOfYear) {
                    switch ($month) {
                        January { $value = $value -bor 1 }
                        February { $value = $value -bor 2 }
                        March { $value = $value -bor 4 }
                        April { $value = $value -bor 8 }
                        May { $value = $value -bor 16 }
                        June { $value = $value -bor 32 }
                        July { $value = $value -bor 64 }
                        August { $value = $value -bor 128 }
                        September { $value = $value -bor 256 }
                        October { $value = $value -bor 512 } 
                        November { $value = $value -bor 1024 } 
                        December { $value = $value -bor 2048 } 
                    } 
                }
                $Trigger.MonthsOfYear = $Value
                $value = 0
                foreach ($day in $DayofMonth) {
                    $value = $value -bor ([Math]::Pow(2, $day - 1))
                }
                $Trigger.DaysOfMonth  = $value
            }
            MonthlyDayOfWeek {
                $Trigger =  $Task.Triggers.Create(5)
                $Trigger.StartBoundary = $at.ToString("s")
                $value = 0
                foreach ($month in $MonthOfYear) {
                    switch ($month) {
                        January { $value = $value -bor 1 }
                        February { $value = $value -bor 2 }
                        March { $value = $value -bor 4 }
                        April { $value = $value -bor 8 }
                        May { $value = $value -bor 16 }
                        June { $value = $value -bor 32 }
                        July { $value = $value -bor 64 }
                        August { $value = $value -bor 128 }
                        September { $value = $value -bor 256 }
                        October { $value = $value -bor 512 } 
                        November { $value = $value -bor 1024 } 
                        December { $value = $value -bor 2048 } 
                    } 
                }
                $Trigger.MonthsOfYear = $Value
                $value = 0
                foreach ($week in $WeekofMonth) {
                    $value = $value -bor ([Math]::Pow(2, $week - 1))
                }
                $Trigger.WeeksOfMonth = $value            
                $value = 0
                foreach ($day in $DayOfWeek) {
                    switch ($day) {
                        Sunday { $value = $value -bor 1 }
                        Monday { $value = $value -bor 2 }
                        Tuesday { $value = $value -bor 4 }
                        Wednesday { $value = $value -bor 8 }
                        Thursday { $value = $value -bor 16 }
                        Friday { $value = $value -bor 32 }
                        Saturday { $value = $value -bor 64 }
                    }   
                }
                $Trigger.DaysOfWeek = $value

            }
            Weekly {
                $Trigger = $Task.Triggers.Create(3)
                $Trigger.StartBoundary = $at.ToString("s")
                $value = 0
                foreach ($day in $DayOfWeek) {
                    switch ($day) {
                        Sunday { $value = $value -bor 1 }
                        Monday { $value = $value -bor 2 }
                        Tuesday { $value = $value -bor 4 }
                        Wednesday { $value = $value -bor 8 }
                        Thursday { $value = $value -bor 16 }
                        Friday { $value = $value -bor 32 }
                        Saturday { $value = $value -bor 64 }
                    }   
                }
                $Trigger.DaysOfWeek = $value
                $Trigger.WeeksInterval = $WeeksInterval
            }
            In {
                $Trigger = $Task.Triggers.Create(1)
                $at = (Get-Date) + $in
                $Trigger.StartBoundary = $at.ToString("s")
            }
            Event {
                $Query = $Task.Triggers.Create(0)
                $Query.Subscription = " 
<QueryList> 
    <Query Id='0' Path='$($OnEvent.LogName)'> 
        <Select Path='$($OnEvent.LogName)'> 
            *[System[Provider[@Name='$($OnEvent.ProviderName)'] and EventID=$($OnEvent.Id)]] 
        </Select> 
    </Query> 
</QueryList> 
                "
            }
            EventQuery {
                $Query = $Task.Triggers.Create(0)
                $Query.Subscription = $OnEventQuery
            }
        }
        if ($Until) {
            $Trigger.EndBoundary = $until.ToString("s")
        }
        if ($Repeat.TotalSeconds) {
            $Trigger.Repetition.Interval = "PT$([Math]::Floor($Repeat.TotalHours))H$($Repeat.Minutes)M"
        }
        if ($For.TotalSeconds) {
            $Trigger.Repetition.Duration = "PT$([Math]::Floor($For.TotalHours))H$([int]$For.Minutes)M$($For.Seconds)S"
        }
        $Task
    }
}

##########################################################################
##	Function to Add Additional Action to a task definition
##########################################################################
function Add-TaskAction
{
    <# 
    .Synopsis 
        Adds an action to a task definition 
    .Description 
        Adds an action to a task definition. 
        You can create a task definition with New-Task, or use an existing definition from Get-ScheduledTask 
    .Example 
        New-Task -Disabled | 
            Add-TaskTrigger $EVT[0] | 
            Add-TaskAction -Path Calc | 
            Register-ScheduledTask "$(Get-Random)" 
    .Link 
        Register-ScheduledTask 
    .Link 
        Add-TaskTrigger 
    .Link 
        Get-ScheduledTask 
    .Link 
        New-Task 
    #>
    [CmdletBinding(DefaultParameterSetName="Script")]
    param(
    # The Scheduled Task Definition
    [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true)]
    $Task,
 
    # The script to run 
    [Parameter(Mandatory=$true,ParameterSetName="Script")]
    [ScriptBlock]
    $Script,
    
    # If set, will run PowerShell.exe with -WindowStyle Minimized
    [Parameter(ParameterSetName="Script")]
    [Switch]
    $Hidden,
    
    # If set, will run PowerShell.exe
    [Parameter(ParameterSetName="Script")]    
    [Switch]
    $Sta,
    
    # The path to the program.
    [Parameter(Mandatory=$true,ParameterSetName="Path")]
    [string]
    $Path,
    
    # The arguments to pass to the program.
    [Parameter(ParameterSetName="Path")]
    [string]
    $Arguments,    
    
    # The working directory the action will run in. 
    # By default, this will be the current directory
    [String]
    $WorkingDirectory = $PWD,
    
    # If set, the powershell script will not exit when it is completed
    [Parameter(ParameterSetName="Script")]
    [Switch]
    $NoExit,
    
    # The identifier of the task
    [String]
    $Id
    )
    
    begin {
        Set-StrictMode -Off
    }

    process {
        if ($Task.Definition) {  $Task = $Task.Definition }

        $Action = $Task.Actions.Create(0)
        if ($Id) { $Action.ID = $Id }
        $Action.WorkingDirectory = $WorkingDirectory
        switch ($psCmdlet.ParameterSetName) {
            Script {
                $action.Path = Join-Path $psHome "PowerShell.exe"
                $action.WorkingDirectory = $WorkingDirectory
                $action.Arguments = ""
                if ($Hidden) {
                    $action.Arguments += " -WindowStyle Hidden"
                }
                if ($sta) {
                    $action.Arguments += " -Sta"
                }
                if ($NoExit) {
                    $Action.Arguments += " -NoExit"
                }
                $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
                $action.Arguments+= " -encodedCommand $encodedCommand"
            }
            Path {
                $action.Path = $Path
                $action.Arguments = $Arguments
            }
        }
        $Task
    }
}



function Test-Permission
{
    <# 
    .SYNOPSIS 
    Tests if permissions are set on a file, directory, registry key, or certificate's private key/key container. 
 
    .DESCRIPTION 
    Sometimes, you don't want to use `Grant-Permission` on a big tree. In these situations, use `Test-Permission` to see if permissions are set on a given path. 
 
    This function supports file system, registry, and certificate private key/key container permissions. You can also test the inheritance and propogation flags on containers, in addition to the permissions, with the `ApplyTo` parameter. See [Grant-Permission](Grant-Permission.html) documentation for an explanation of the `ApplyTo` parameter. 
 
    Inherited permissions on *not* checked by default. To check inherited permission, use the `-Inherited` switch. 
 
    By default, the permission check is not exact, i.e. the user may have additional permissions to what you're checking. If you want to make sure the user has *exactly* the permission you want, use the `-Exact` switch. Please note that by default, NTFS will automatically add/grant `Synchronize` permission on an item, which is handled by this function. 
 
    When checking for permissions on certificate private keys/key containers, if a certificate doesn't have a private key, `$true` is returned. 
 
    .OUTPUTS 
    System.Boolean. 
 
    .LINK 
    Carbon_Permission 
 
    .LINK 
    ConvertTo-ContainerInheritanceFlags 
 
    .LINK 
    Get-Permission 
 
    .LINK 
    Grant-Permission 
 
    .LINK 
    Protect-Acl 
 
    .LINK 
    Revoke-Permission 
 
    .LINK 
    http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.filesystemrights.aspx 
     
    .LINK 
    http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.registryrights.aspx 
     
    .LINK 
    http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.cryptokeyrights.aspx 
     
    .EXAMPLE 
    Test-Permission -Identity 'STARFLEET\JLPicard' -Permission 'FullControl' -Path 'C:\Enterprise\Bridge' 
 
    Demonstrates how to check that Jean-Luc Picard has `FullControl` permission on the `C:\Enterprise\Bridge`. 
 
    .EXAMPLE 
    Test-Permission -Identity 'STARFLEET\GLaForge' -Permission 'WriteKey' -Path 'HKLM:\Software\Enterprise\Engineering' 
 
    Demonstrates how to check that Geordi LaForge can write registry keys at `HKLM:\Software\Enterprise\Engineering`. 
 
    .EXAMPLE 
    Test-Permission -Identity 'STARFLEET\Worf' -Permission 'Write' -ApplyTo 'Container' -Path 'C:\Enterprise\Brig' 
 
    Demonstrates how to test for inheritance/propogation flags, in addition to permissions. 
 
    .EXAMPLE 
    Test-Permission -Identity 'STARFLEET\Data' -Permission 'GenericWrite' -Path 'cert:\LocalMachine\My\1234567890ABCDEF1234567890ABCDEF12345678' 
 
    Demonstrates how to test for permissions on a certificate's private key/key container. If the certificate doesn't have a private key, returns `$true`. 
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path on which the permissions should be checked. Can be a file system or registry path.
        $Path,
        
        [Parameter(Mandatory=$true)]
        [string]
        # The user or group whose permissions to check.
        $Identity,
        
        [Parameter(Mandatory=$true)]
        [string[]]
        # The permission to test for: e.g. FullControl, Read, etc. For file system items, use values from [System.Security.AccessControl.FileSystemRights](http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.filesystemrights.aspx). For registry items, use values from [System.Security.AccessControl.RegistryRights](http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.registryrights.aspx).
        $Permission,
        
        #[Carbon.Security.ContainerInheritanceFlags]
        # The container and inheritance flags to check. Ignored if `Path` is a file. These are ignored if not supplied. See `Grant-Permission` for detailed explanation of this parameter. This controls the inheritance and propagation flags. Default is full inheritance, e.g. `ContainersAndSubContainersAndLeaves`. This parameter is ignored if `Path` is to a leaf item.
        $ApplyTo,

        [Switch]
        # Include inherited permissions in the check.
        $Inherited,

        [Switch]
        # Check for the exact permissions, inheritance flags, and propagation flags, i.e. make sure the identity has *only* the permissions you specify.
        $Exact
    )

    Set-StrictMode -Version 'Latest'

    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $originalPath = $Path
    $Path = Resolve-Path -Path $Path -ErrorAction 'SilentlyContinue'
    if( -not $Path -or -not (Test-Path -Path $Path) )
    {
        if( -not $Path )
        {
            $Path = $originalPath
        }
        Write-Error ('Unable to test {0}''s {1} permissions: path ''{2}'' not found.' -f $Identity,($Permission -join ','),$Path)
        return
    }

    $providerName = Get-PathProvider -Path $Path | Select-Object -ExpandProperty 'Name'
    if( $providerName -eq 'Certificate' )
    {
        $providerName = 'CryptoKey'
    }

    if( ($providerName -eq 'FileSystem' -or $providerName -eq 'CryptoKey') -and $Exact )
    {
        # Synchronize is always on and can't be turned off.
        $Permission += 'Synchronize'
    }
    $rights = $Permission | ConvertTo-ProviderAccessControlRights -ProviderName $providerName
    if( -not $rights )
    {
        Write-Error ('Unable to test {0}''s {1} permissions on {2}: received an unknown permission.' -f $Identity,$Permission,$Path)
        return
    }

    $account = Resolve-Identity -Name $Identity
    if( -not $account)
    {
        return
    }

    $rightsPropertyName = '{0}Rights' -f $providerName
    $inheritanceFlags = [Security.AccessControl.InheritanceFlags]::None
    $propagationFlags = [Security.AccessControl.PropagationFlags]::None
    $testApplyTo = $false
    if( $PSBoundParameters.ContainsKey('ApplyTo') )
    {
        if( (Test-Path -Path $Path -PathType Leaf ) )
        {
            Write-Warning "Can't test inheritance/propagation rules on a leaf. Please omit `ApplyTo` parameter when `Path` is a leaf."
        }
        else
        {
            $testApplyTo = $true
            $inheritanceFlags = ConvertTo-InheritanceFlag -ContainerInheritanceFlag $ApplyTo
            $propagationFlags = ConvertTo-PropagationFlag -ContainerInheritanceFlag $ApplyTo
        }
    }

    if( $providerName -eq 'CryptoKey' )
    {
        # If the certificate doesn't have a private key, return $true.
        if( (Get-Item -Path $Path | Where-Object { -not $_.HasPrivateKey } ) )
        {
            return $true
        }
    }

    $acl = Get-Permission -Path $Path -Identity $Identity -Inherited:$Inherited | 
                Where-Object { $_.AccessControlType -eq 'Allow' } |
                Where-Object { $_.IsInherited -eq $Inherited } |
                Where-Object { 
                    if( $Exact )
                    {
                        return ($_.$rightsPropertyName -eq $rights)
                    }
                    else
                    {
                        return ($_.$rightsPropertyName -band $rights) -eq $rights
                    }
                } |
                Where-Object {
                    if( -not $testApplyTo )
                    {
                        return $true
                    }

                    if( $Exact )
                    {
                        return ($_.InheritanceFlags -eq $inheritanceFlags) -and ($_.PropagationFlags -eq $propagationFlags)
                    }
                    else
                    {
                        return (($_.InheritanceFlags -band $inheritanceFlags) -eq $inheritanceFlags) -and `
                               (($_.PropagationFlags -and $propagationFlags) -eq $propagationFlags)
                    }
                }
    if( $acl )
    {
        return $true
    }
    else
    {
        return $false
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


#Add User Profile path to customized variables (if not running in Deployment mode)

$OneDriveUserPath = "$env:userprofile\$OneDriveFolderName"
$FirstOneDriveComplete = "$OneDriveUserPath\$MigrationFlagFileName"
$RunningAsSYSTEMCheck = $env:computername + "$"
$RunningAsSYSTEM = $null

If(($RunningAsSYSTEMCheck -eq $env:UserName) -and ($DeployRuntimeScriptOnly -ne $true)){
    $DeployMode = $True
    $RunningAsSYSTEM = $True
    Write-Output "Running as SYSTEM, may be running non-Interacrtively via a Deployment tool (MECM etc)"
}

If($DeployMode -eq $True){$triggerRuntimeScriptHere = $False}
If($RunningAsSYSTEM -eq $True){$triggerRuntimeScriptHere = $False}

#Set the Logfile Location based on this script's mode

If(($DeployMode -eq $True) -and ($DeployRuntimeScriptOnly -ne $true)){

    #IF we're set in DeployRuntimeScriptOnly mode, we'll place the logfile in our Runtime Script location
    $LogFilePath = "$Env:TEMP\$LogFileName"
 
        icacls $LogFilePath /grant:r BUILTIN\Users:F | Out-Null
    
}else{

    #IF we're running this script interactively or not in Deploy only mode, we'll place the logfile in the User Profile Path
    $LogFilePath = "$env:userprofile\$LogFileName"
}

#Reset Logfile & set the Error Action to Continue
    Remove-Item $LogFilePath -Force -ErrorAction Ignore | Out-Null
     
	$ErrorActionPreference = "Continue"
    
	#Log the SCript Runtime start
	WriteLog "OneDrive Migration Checklist and Script Staging"

    Write-Output "Set User Profile paths based on configured required variables"
    WriteLog "Set User Profile paths based on configured required variables..."


#Set PS Transcript Logfile & Restart self in x64 if we're on a 64-bit OS

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

Write-Output "Checking to see if 'WorkFoldersName' variable was set by a human, or if script needs to try populating it."

If($WorkFoldersName -eq $null){

    WriteLog "Attempting to obtain the Work Folders Path from the Registry, format it, and asssign to the WorkFoldersName variable."
    
$WFRegPath = "HKCU:\Software\Policies\Microsoft\Windows\WorkFolders"
$WFNameRegVal = "LocalFolderPath"

try{
    $WorkFoldersName = Get-ItemProperty -Path $WFRegPath | Select-Object -ExpandProperty $WFNameRegVal -ErrorAction Stop
}catch{
    #Write-Error $_ -ErrorAction Continue
    Write-Output "Unable to obtain the Work Folders Path from the Registry, format it, and asssign to the WorkFoldersName variable."
    WriteLog "Unable to obtain the Work Folders Path from the Registry, format it, and asssign to the WorkFoldersName variable."    
    }

if($WorkFoldersName -like '*%userprofile%*'){

    $WorkFoldersName = $WorkFoldersName -replace '%userprofile%', ''
   
}

If(!$WorkFoldersName -eq $null){$WorkFoldersName = $WorkFoldersName.replace('\', '')}

}

$WorkFoldersPath = $null

If($WorkFoldersName){$WorkFoldersPath = "$env:userprofile\$WorkFoldersName"}

If(!$RunningAsSYSTEM){Write-Output "Value of Work Folders Name Variable is $WorkFoldersName"}

If(!$RunningAsSYSTEM){Write-Output "Value of Work Folders Path Variable is $WorkFoldersPath"}
If(!$RunningAsSYSTEM){Write-Output "Configured Path for OneDrive Folder Root: $OneDriveUserPath"}


$PrimaryTenantDomainTLD = $PrimaryTenantDomain.LastIndexOf('.')

$PrimaryTenantSubDomain = $PrimaryTenantDomain.Substring(0,$PrimaryTenantDomainTLD)


WriteLog "Configured Primary Tenant Domain: $PrimaryTenantDomain"
WriteLog "Primary Domain Name without TLD is $PrimaryTenantSubDomain"
Write-Output "Configured Primary Tenant Domain: $PrimaryTenantDomain"
Write-Output "Primary Domain Name without TLD is $PrimaryTenantSubDomain"

If(!$RunningAsSYSTEM){WriteLog "Configured Migration Flag File: $FirstOneDriveComplete"}

WriteLog "Configured Path for This Logfile: $LogFilePath"
Write-Output "Configured Path for This Logfile: $LogFilePath"

If(!$RunningAsSYSTEM){WriteLog "Configured Path for current Work Folder Root: $WorkFoldersPath"}
If(!$RunningAsSYSTEM){WriteLog "Configured Path for OneDrive Folder Root: $OneDriveUserPath"}
If(($RunningAsSYSTEM) -and ($DeployMode)){WriteLog "Running as SYSTEM in Deployment Mode"}
If(($RunningAsSYSTEM) -and ($DeployMode)){Write-Output "Running as SYSTEM in Deployment Mode"}


#Check for Local Admin Rights (expect that user is non-Admin unless running as SYSTEM or in Deploy Mode, but always check anyway)

    $isLocalAdmin = Test-IsLocalAdministrator

    Write-Output "Local Administrator Rights True or False: $isLocalAdmin"

#If user is a non-Admin as-expected, check to see if user has Scheduled Task creation rights

    If($isLocalAdmin -eq $false){
  
        #User running this process is a non-Admin user, therefore they do not have Scheduled Task creation rights
        $SchedTasksRights = $false

    }Else{

        #User running this process has Admin rights, therefore can create Scheduled Tasks
        Write-Output "User $env:USERNAME has Admin rights, therefore can create Scheduled Tasks"
        WriteLog "User $env:USERNAME has Admin rights, therefore can create Scheduled Tasks"
        $SchedTasksRights = $true
    }

#Set system.io variable for operations on Migration Flag file
[System.IO.DirectoryInfo]$FirstOneDriveCompletePath = $FirstOneDriveComplete

if(![System.IO.File]::Exists($FirstOneDriveComplete)){$ODFlagFileExist = $false}else{$ODFlagFileExist  = $true}

Write-output "Migration Flag File Exists true or false: $ODFlagFileExist"

#Set system.io Variable to see if there is a centralized/single Runtime of OneDrive vs the default Windows Bundled version
$OneDriveProgFiles = "C:\Program Files\Microsoft OneDrive"
[System.IO.DirectoryInfo]$OneDriveProgFilesPath = $OneDriveProgFiles


#Set system.io Variable to check if Work Folders Path exists

[System.IO.DirectoryInfo] $WorkFoldersPathCheck = $WorkFoldersPath

If($WorkFoldersPathCheck){Write-Output "Work Folders Path checked and physically exists"}

If($DeployRunTimeScriptOnly -ne $true){
    #beginning of $DeployRuntimeScriptOnly IF check

#CREATE RUNTIME WRAPPER TO LAUNCH THE MIGRATION RUNTIME SCRIPT (SO USER DOESN'T GET A PS WINDOW)
WriteLog "Creating Silent VBS Launcher for Runtime Script (so User doesn't get a PS window)."
$vbsSilentPSLauncher = "
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
}

if(![System.IO.Directory]::($setRuntimeScriptFolder)){
    New-Item -Path $setRuntimeScriptFolder -Type Directory -Force
}

$vbsSilentPSLauncher | Out-File $setPSRuntimeLauncherPath -Force

#Whichever user account first creates this file, ensure other users can replace it

try {
 
    icacls $setPSRuntimeLauncherPath /grant:r BUILTIN\Users:F | Out-Null
}
catch {
    {1:<#terminating exception#>}
}

#ENSURE ONEDRIVE CONFIG REGISTRY KEYS ARE CREATED
try{
    Write-Output "Adding registry keys for Onedrive"
   
    If($isLocalAdmin -eq $true){
          
        $res = New-Item -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Confirm:$False -ErrorAction SilentlyContinue
        $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name SilentAccountConfig -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue
        

        if($enableFilesOnDemand -eq $true){
            $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 1 -PropertyType DWORD -Force -ErrorAction SilentyContinue
        }else{
            $res = New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Onedrive" -Name FilesOnDemandEnabled -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue
        }
        
        #Delete Registry value "DisableFileSyncNGSC" (ignore error if the entry does not exist)
        Remove-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Force -Confirm:$False -ErrorAction SilentlyContinue
    }
    Write-Output "Required Registry keys for Onedrive created or modified"
}catch{
    Write-Error "Failed to add Onedrive registry keys, installation may not be consistent" -ErrorAction Continue
    Write-Error $_ -ErrorAction Continue
}

#REMOVE WORKFOLDERS AUTOPROVISION ENTRIES OF ALL USERS OF THIS SYSTEM

    #Note: By default the HKCU\Software\Policies\Microsoft\Windows\WorkFolder key does not allow non-admin users to modify the AutoProvision DWORD entry
        # So the Runtime Script is not able to stop Work Folder sync, even after successful Data Migration and Folder Redirection
        # So we'll try to modify Work Folder Sync entries for all users of this endpoint, here from this script *IF* it is being run with Admin rights.
        
If($isLocalAdmin -eq $true){
    if(($redirectFoldersToOnedriveForBusiness -eq $true) -and ($enableDataMigration -eq $true)){

        Write-Output "Removing Work Folders Settings via HKCU Registry entries for all users of this system"
        WriteLog "Removing Work Folders Settings via HKCU Registry entries for all users of this system"

    # Regex pattern for Local or Domain SIDs

$PatternSID = 'S-1-5-21-\d+-\d+\-\d+\-\d+$'
 
# Get Username, SID, and location of ntuser.dat for all users
$ProfileList = gp 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' | Where-Object {$_.PSChildName -match $PatternSID} | 
    Select  @{name="SID";expression={$_.PSChildName}}, 
            @{name="UserHive";expression={"$($_.ProfileImagePath)\ntuser.dat"}}, 
            @{name="Username";expression={$_.ProfileImagePath -replace '^(.*[\\\/])', ''}}
 
# Get all user SIDs found in HKEY_USERS (ntuder.dat files that are loaded)
$LoadedHives = gci Registry::HKEY_USERS | ? {$_.PSChildname -match $PatternSID} | Select @{name="SID";expression={$_.PSChildName}}
 
# Get all users that are not currently logged
$UnloadedHives = Compare-Object $ProfileList.SID $LoadedHives.SID | Select @{name="SID";expression={$_.InputObject}}, UserHive, Username
 
# Loop through each profile on the machine
Foreach ($item in $ProfileList) {
    # Load User ntuser.dat if it's not already loaded
    IF ($item.SID -in $UnloadedHives.SID) {
        reg load HKU\$($Item.SID) $($Item.UserHive) | Out-Null
    }
 
    #####################################################################
    # This is where you can read/modify a users portion of the registry 

    # This example checks for a key, adds it if missing, and creates / changes a DWORD in that key
    "{0}" -f $($item.Username) | Write-Output
    

    If ((Test-Path registry::HKEY_USERS\$($Item.SID)\SOFTWARE\Policies\Microsoft\Windows\WorkFolders)) {
        Set-ItemProperty registry::HKEY_USERS\$($Item.SID)\SOFTWARE\Policies\Microsoft\Windows\WorkFolders -Name 'AutoProvision' -Value 0 -Type DWord -Force -ErrorAction Ignore | Out-Null
        Remove-ItemProperty registry::HKEY_USERS\$($Item.SID)\SOFTWARE\Policies\Microsoft\Windows\WorkFolders -Name 'SyncUrl' -Force -ErrorAction Ignore | Out-Null     
    }
    
    #####################################################################
 
    # Unload ntuser.dat        
    IF ($item.SID -in $UnloadedHives.SID) {
        ### Garbage collection and closing of ntuser.dat ###
        [gc]::Collect()
        reg unload HKU\$($Item.SID) | Out-Null
    }
}

}
}  #end of WORKFOLDERS AUTOPROVISION ENTRIES REMOVAL

#######################################################
# Set the Runtime Script to run at User Logon
#######################################################

$wscriptPath = Join-Path $env:SystemRoot -ChildPath "System32\wscript.exe"
$fullRunPath = "$wscriptPath `"$setPSRuntimeLauncherPath`" `"$setRuntimeScriptPath`""
If(($DeployMode -eq $false) -and ($SchedTasksRights -eq $false)){
    WriteLog "Not running in Deployment mode and user does not have Scheduled Task rights = Registering Script to run at logon"
    If(($ODFlagFileExist -eq $false) -and (!$WorkFoldersPath -eq $null)){
        try{
            Write-Output "Adding logon registry key"
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name OnedriveAutoConfig -Value $fullRunPath -PropertyType String -Force -ErrorAction Stop
            Write-Output "logon registry key added"
        }catch{
            Write-Error "Failed to add logon registry keys, user config will likely fail" -ErrorAction Continue
            Write-Error $_ -ErrorAction Continue
        }
    }else{
        WriteLog "ODFileExist variable is True and WorkFoldersPath is "Null" and couldn't be set, therefore not adding logon registry key"
    }
}

#######################################################
# Create a scheduled task to Trigger the Runtime Script
#######################################################

If(($SchedTasksRights -eq $true) -and ($skipScheduledTaskCreation -eq $false)){

# This Scheduled Task section creates the Scheduled Task for "All users" by default, in case the target user getting 
# migrated is NOT the same user who runs this Main Script (e.g. MECM deployment of this script, or otherwise running it as an Admin user).
# First thing's first, if there are a LOT of User profiles on this machine, we aren't going to set the Scheduled Task at all.   Becuase 
# this could be a multi-user machine, and we would rather just let the Runtime Script run as a Logon process (HKCU...\Run) or something else on 
# such a Multi-User Machine.  So if there are more than 5 User Profiles on this machine, we do not set the Scheduled Task.

$UserProfileFolderCount = Get-ChildItem -Path "$env:systemdrive\Users" | Where-Object { !($_.PSIsContainer) }
    If($UserProfileFolderCount.Count -le 6){    #modify this if you wish for multi-user machines to launch Runtime script as Scheduled Task 

    WriteLog "Creating scheduled task to run at Logon + run once several times today."
    Write-Output "Creating scheduled task to run at Logon + run once several times today."
    Write-Output $wscriptPath 
    Write-Output "`"$setPSRuntimeLauncherPath`" `"$setRuntimeScriptPath`""
    $action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$setPSRuntimeLauncherPath`" `"$setRuntimeScriptPath`""
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Compatibility Win8

    $fiveminahead = "{0:hh}:{0:mm}" -f (Get-Date).addminutes(5) | Out-String

    $triggers = @(
        $(New-ScheduledTaskTrigger -AtLogon),
        $(New-ScheduledTaskTrigger -At 12AM -Once),
        $(New-ScheduledTaskTrigger -At 9AM -Once),
        $(New-ScheduledTaskTrigger -At 10AM -Once),
        $(New-ScheduledTaskTrigger -At 11AM -Once),
        $(New-ScheduledTaskTrigger -At 12PM -Once),
        $(New-ScheduledTaskTrigger -At 1PM -Once),
        $(New-ScheduledTaskTrigger -At 2PM -Once),
        $(New-ScheduledTaskTrigger -At 3PM -Once),
        $(New-ScheduledTaskTrigger -At 4PM -Once),
        $(New-ScheduledTaskTrigger -At 5PM -Once)
        $(New-ScheduledTaskTrigger -At 6PM -Once),
        $(New-ScheduledTaskTrigger -At 7PM -Once),
        $(New-ScheduledTaskTrigger -At 8PM -Once),
        $(New-ScheduledTaskTrigger -At 9PM -Once),
        $(New-ScheduledTaskTrigger -At 10PM -Once),
        $(New-ScheduledTaskTrigger -At 11PM -Once),
        $(New-ScheduledTaskTrigger -At $fiveminahead -Once) # run 5 mins after script complete (e.g. MECM triggers this script as SYSTEM, then Runtime script runs 5 mins later for any logged-on user)
    )
    $principal = New-ScheduledTaskPrincipal -GroupId S-1-5-32-545  # <--- S-1-5-32-545 is the builtin Users group
    $task = New-ScheduledTask -Action $action -Settings $settings  -Trigger $triggers -Principal $principal

    if(Get-ScheduledTask -TaskName "OnedriveAutoConfig" -TaskPath \  -ErrorAction Ignore) { Unregister-ScheduledTask -TaskName "OnedriveAutoConfig" -TaskPath \ -Confirm:$false}else{}

    Register-ScheduledTask -InputObject $task -TaskName "OnedriveAutoConfig"

    #SET PERMS TO SCHEDULED TASK SO THAT IT CAN BE RUN BY ANYONE

    #Set the Scheduled Task xml file to be managed by any Authenticated User

    icacls $env:windir\System32\tasks\OnedriveAutoConfig /grant:r BUILTIN\Users:F | Out-Null
    icacls $env:windir\System32\tasks\OnedriveAutoConfig /grant:r `"Authenticated Users`":F | Out-Null

    #Set the Scheduled Task Registry entry to be managed by any Authenticated User

     $Taskname = "OnedriveAutoConfig"

    $KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\OnedriveAutoConfig"

    $Key = Get-Item $KeyPath -ErrorAction SilentlyContinue

    $batFile = "$env:TEMP\Set-A-Task-Free.bat"
    $updateTaskName = 'Set-A-Task-Free'
    ''
    "SDDL for $taskname will be updated via $batfile"
    ''
     
    $wmisdh = new-object system.management.ManagementClass Win32_SecurityDescriptorHelper 
    $subkeys = Get-childitem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree"
    foreach ($key in $subkeys) {
        if ($taskname -eq '') {              # if blank, show SDDL for all tasks 
            ''
            $key.PSChildName
            $task = Get-ItemProperty $($key.name).replace("HKEY_LOCAL_MACHINE","HKLM:")
            $sddl = $wmisdh.BinarySDToSDDL( $task.SD ) 
            $sddl['SDDL']        
        
        } else {
            if ($key.PSChildName -eq $taskname) {
                ""
                $key.PSChildName
                $task = Get-ItemProperty $($key.name).replace("HKEY_LOCAL_MACHINE","HKLM:")
                $sddl = $wmisdh.BinarySDToSDDL( $task.SD ) 
                $sddl['SDDL']
                ''
                'New SDDL'
                $newSD = $sddl['SDDL'] +  '(A;ID;0x1301bf;;;AU)'          # add authenticated users read and execute
                $newSD                                                    # Note: cacls /s will display the SDDL for a file. 
                $newBin = $wmisdh.SDDLToBinarySD( $newsd )
                [string]$newBinStr =  $([System.BitConverter]::ToString($newBin['BinarySD'])).replace('-','') 
                
                # Administrators only have read permissions to the registry value that needs to be updated.
                # We will create a bat file with a reg.exe command to set the new SD.
                # The bat file will be invoked by a scheduled task that runs as the SYSTEM account.
                # The bat file can also be reused if the task is deployed to other machines. 
                ''
                "reg add ""HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\{0}"" /f /v SD /t REG_BINARY /d {1}" -f $key.PSChildName, $newBinStr
                "reg add ""HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\{0}"" /f /v SD /t REG_BINARY /d {1}" -f $key.PSChildName, $newBinStr  | out-file -Encoding ascii $batfile  
                ''
    
            # Here we will set the the above REgistry entries to be triggered as a Scheduled Task for the machine, and run it immediately - then delete the task.

                SCHTASKS /Create /f /tn "$updateTaskName" /sc onstart  /tr "cmd.exe /c $batfile" /ru system 
                SCHTASKS /run /tn "$updateTaskName"
                $count = 0
                while ($count -lt 5) {
                    start-sleep 5
                    $count++
                    $(Get-ScheduledTask -TaskName $updateTaskName).State
                    if ($(Get-ScheduledTask -TaskName $updateTaskName).State -eq 'Ready') {
                        $count = 99            # it's ok to procees
                    }
                }
                if ($count -ne 99) {
                    "Error! The $updateTaskName task is still running. "
                    'It should have ended by now.'
                    'Please investigate.'
                    return
                }
                SCHTASKS /delete /f /tn "$updateTaskName"
                ''
                'Security has been updated.'
            }
        }
    }



    } 
    
} #end of $DeployRuntimeScriptOnly IF check

#######################################################
#
# Begin Placement of code for Runtime Script
#
#######################################################

WriteLog "Staging local Powershell script for OneDrive Config and (if enabled) Data Migration activities"

$RuntimeScriptContent = "
<#
    Name: WF-2-ODfB-Mig.ps1
    Version: 0.4.1 (05 April 2022)
.NOTES
    Author: Julian West
    Licensed Under GNU General Public License, version 3 (GPLv3);
.SYNOPSIS
    Migrate any active Work Folders to OneDrive for Business
.DESCRIPTION
    This script is created by WF-2-ODfB.ps1 (Main Script) and is placed either into Scheduled Tasks or HKCU Run
    to ensure a silent migration of a Windows 10 Endpoint's User data sync settings from Work Folders 
    over to OneDrive for Business.  
    It is targeted to run OneDrive Setup and auto sign-in (if endpoint is Hybrid joined to Azure AD), 
    redirect Known Folders, and move data from Work Folders to OneDrive folder via Robocopy /Move.
    Requirements: Windows 10, Powershell 5x or above.
.LINK
    https://github.com/J-DubApps
#>

### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, required for successful script run.  These are set by the Main (boss/deployment) Script.  
#

# User Profile paths and customized variables set by Deployment Script or auto-filled here - you can Adjust to your own env values if needed - 

`$OneDriveFolderName = `"$OneDriveFolderName`"
`$WorkFoldersName = `"$WorkFoldersName`"
`$PrimaryTenantDomain = `"$PrimaryTenantDomain`"
`$PrimaryTenantSubDomain = `"$PrimaryTenantSubDomain`"
`TenantID = `"$TenantID`"
`$enableDataMigration = `$$enableDataMigration
`$LogFileName = `"ODfB_Config_Run_`$env:username.log`" # <-- Log file name for IT or end-user to review what this script did
`$MigrationFlagFileName = `"$MigrationFlagFileName`" 
`$LogFilePath = `"`$env:userprofile\`$LogFileName`"
`$OneDriveUserPath = `"`$env:userprofile\`$OneDriveFolderName`"
`$WorkFoldersPath = `"`$env:userprofile\`$WorkFoldersName`"
`$FirstOneDriveComplete = `"`$OneDriveUserPath\`$MigrationFlagFileName`"
`$cleanDesktopDuplicates = `$$cleanDesktopDuplicates
`$GPO_Refresh = `$$GPO_Refresh

`Write-Output `"Checking to see if 'WorkFoldersName' variable was set by a human, or if script needs to try populating it.`"

If(`$WorkFoldersName -eq `$null){

    Write-Output `"Attempting to obtain the Work Folders Path from the Registry, format it, and assign to the WorkFoldersName variable.`"
    
`$WFRegPath = `"HKCU:\Software\Policies\Microsoft\Windows\WorkFolders`"
`$WFNameRegVal = `"LocalFolderPath`"

try{
    `$WorkFoldersName = Get-ItemProperty -Path `$WFRegPath | Select-Object -ExpandProperty `$WFNameRegVal
}catch{
    Write-Error `$_ -ErrorAction Continue
    }


if(`$WorkFoldersName -like '*%userprofile%*'){

    `$WorkFoldersName = `$WorkFoldersName -replace '%userprofile%', ''
    `$WorkFoldersName = `$WorkFoldersName.replace('\', '')
}

}

#Write-Output `"Value of Work Folders Name Variable is `$WorkFoldersName`"

`$WorkFoldersPath = `$null

If(`$WorkFoldersName){`$WorkFoldersPath = `"`$env:userprofile\`$WorkFoldersName`"}

Write-Output `"Value of Work Folders Path Variable is `$WorkFoldersPath`"

#Use system.io variable for File & Directory operations to check for Migration Flag file & Work Folders Path
If([System.IO.Directory]::Exists(`$WorkFoldersPath)){`$WorkFoldersExist = `$true}else{`$WorkFoldersExist = `$false}
if(![System.IO.File]::Exists(`$FirstOneDriveComplete)){`$ODFlagFileExist = `$false}else{`$ODFlagFileExist  = `$true}

If((!`$WorkFoldersName) -and (`$enableDataMigration -eq `$true)){

    Write-Output `"Work Folders Path was not found,  WorkFoldersName variable either was not set by a human in WF-2-ODfB.ps1, or WorkFoldersName or could not populated automatically.`"  
    Write-Output `"Without this variable set, the script assumes Work Folders do not exist (and Migration was already done), and will now end. If this is not the case, please review and re-reun WF-2-ODfB.ps1.`"
    Remove-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`" -Name `"OnedriveAutoConfig`" -Force -Confirm:`$False -ErrorAction SilentlyContinue
    Stop-Transcript
    Exit    
}



#Set variable if we encounter both OneDrive Flag File and Work Folders paths at the same time
`$WF_and_Flagfile_Exist = `$null
If((`$ODFlagFileExist -eq `$true)  -and (`$WorkFoldersExist -eq `$true)){`$WF_and_Flagfile_Exist = `$true}else{`$WF_and_Flagfile_Exist = `$false}


`$redirectFoldersToOnedriveForBusiness = `$$redirectFoldersToOnedriveForBusiness
`$attemptKFM = `$$attemptKFM
`$listOfFoldersToRedirectToOnedriveForBusiness = @("
$listOfFoldersToRedirectToOnedriveForBusiness | % {
        $RuntimeScriptContent += "@{`"knownFolderInternalName`"=`"$($_.knownFolderInternalName)`";`"knownFolderInternalIdentifier`"=`"$($_.knownFolderInternalIdentifier)`";`"desiredSubFolderNameInOnedrive`"=`"$($_.desiredSubFolderNameInOnedrive)`"},"
}
$RuntimeScriptContent = $RuntimeScriptContent -replace ".$"
$RuntimeScriptContent += ")
`$logFile = Join-Path `$Env:TEMP -ChildPath `"OnedriveAutoConfig.log`"
`$xmlDownloadURL = `"$xmlDownloadURL`"
`$temporaryInstallerPath = Join-Path `$Env:TEMP -ChildPath `"OnedriveInstaller.EXE`"
`$minimumOfflineVersionRequired = `"$minimumOfflineVersionRequired`"
`$onedriveRootKey = `"HKCU:\Software\Microsoft\OneDrive\Accounts\Business`"
`$setRuntimeScriptFolder = `"$setRuntimeScriptFolder`"
`$setRuntimeScriptPath = `"$setRuntimeScriptPath`" 
Start-Transcript -Path `$logFile

#Reset Logfile & set the Error Action to Continue
Remove-Item `$LogFilePath -Force -ErrorAction Ignore | Out-Null

`$ErrorActionPreference = `"Continue`"

##########################################################################
##		Main Functions Section - DO NOT MODIFY!!
##########################################################################

Function LogInformationalEvent(`$Message){
#########################################################################
#	Writes an informational event to the event log
#########################################################################
`$QualifiedMessage = `$ClientName + `" Script: `" + `$Message
Write-EventLog -LogName Application -Source Winlogon -Message `$QualifiedMessage -EventId 1001 -EntryType Information
}

Function LogWarningEvent(`$Message){
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
`$whatIf = `$false

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
        Write-Output `"Removing empty folder '`${path}'`"
        Remove-Item -Force -Recurse:`$removeHiddenFiles -LiteralPath `$Path -WhatIf:`$whatIf
    }
}


##########################################################################
##	Return True/False on Registry value 
##########################################################################

function Test-RegistryKeyValue {

    param (
    
     [parameter(Mandatory=`$true)]
     [ValidateNotNullOrEmpty()]`$Path,
    
    [parameter(Mandatory=`$true)]
     [ValidateNotNullOrEmpty()]`$Value
    )
    
    try {
    
    Get-ItemProperty -Path `$Path | Select-Object -ExpandProperty `$Value -ErrorAction Stop | Out-Null
     return `$true
     }
    
    catch {
    
    return `$false
    
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

If(`$WorkFoldersExist){
    Write-Output `"Work Folders Path checked and physically exists`"
    WriteLog `"Work Folders Path checked and physically exists`"
}

WriteLog `"One Drive Flag File Exists Status: `$ODFlagFileExist `"
WriteLog `"Work Folders Exist Status: `$WorkFoldersExist `"

WriteLog `"One Drive Flag File & Work Folders Status Simultaneously: `$WF_and_Flagfile_Exist `"



#######################################################
# Re-Apply Runtime Script to run @ User Logon if Needed
#######################################################

WriteLog `"Registering Script to run at logon`"
`$wscriptPath = Join-Path `$env:SystemRoot -ChildPath `"System32\wscript.exe`"
`$fullRunPath = `"`$wscriptPath ```"`$setPSRuntimeLauncherPath```" ```"`$setRuntimeScriptPath```"`"
if(Get-ScheduledTask -TaskName `"OnedriveAutoConfig`" -TaskPath \  -ErrorAction Ignore){ 

    # OneDriveautoConfig task exists, no need to set the logon registry key -- delete it, if it exists --
    Remove-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`" -Name `"OnedriveAutoConfig`" -Force -Confirm:`$False -ErrorAction SilentlyContinue


}else{
    
    try{
        # OneDriveautoConfig task does not exist, so set the logon registry key for this user.

        Write-Output `"Adding logon registry key`"
        New-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`" -Name OnedriveAutoConfig -Value `$fullRunPath -PropertyType String -Force -ErrorAction SilentlyContinue
        Write-Output `"logon registry key added`"
        WriteLog `"logon registry key added`"
    }catch{
        #Write-Error `"Failed to add logon registry keys, user config will likely fail`" -ErrorAction Continue
        WriteLog `"Failed to add logon registry keys, user config will likely fail`"
        #Write-Error `$_ -ErrorAction Continue
    }
}


#######################################################
# Check to see if KFM and Folder Redirection Can Happen
#######################################################

#If certain Registry Values exist, we cannot do traditional KnownFolder Redirection using System.Management.Automation / shell32.dll method
#So we would pivot to a Simpler direct method of Folder Redirection using the Registry (SimpleRedirectMode)


If(`$attemptKFM -eq `$true){
`$SimpleRedirectMode = `$null

`$CheckKFMBlockOptInReg = Test-RegistryKeyValue -Path `"HKLM:\SOFTWARE\Policies\Microsoft\OneDrive`" -Value `"KFMBlockOptIn`"
If(`$CheckKFMBlockOptInReg -eq `$true) {

    `$KFMBLockOptIn = (Get-ItemProperty -Path `"HKLM:\SOFTWARE\Policies\Microsoft\OneDrive`" -Name `"KFMBlockOptIn`" -ErrorAction Continue).KFMBLockOptIn
    #Write-Host `$KFMBLockOptIn 
    If(`$KFMBLockOptIn = 1) {
        
         WriteLog `"KFMBlockOptIn is set to 1, so we will enable Simple Redirect Mode & not do traditional KnownFolder Redirection`"
         Write-Output `"KFMBlockOptIn is set to 1, so we will enable Simple Redirect Mode & not do traditional KnownFolder Redirection`"
        `$SimpleRedirectMode=`$true
     }else{
        WriteLog `"KFMBlockOptInis nonexistent or not enabled, so we will do traditional KnownFolder Redirection`"
        Write-Output `"KFMBlockOptIn is note set to 1, so we will do traditional KnownFolder Redirection`"
        `$SimpleRedirectMode=`$false
     }

    }

     `$CheckDisablePersonalDirChangeReg = Test-RegistryKeyValue -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer`" -Value `"DisablePersonalDirChange`"
If(`$CheckDisablePersonalDirChangeReg -eq `$true) {
         
    `$DisablePersonalDirChange = (Get-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer`" -Name `"DisablePersonalDirChange`" -ErrorAction Continue).DisablePersonalDirChange
    #Write-Host `$DisablePersonalDirChange

     If(`$DisablePersonalDirChange = 1) {
 
         WriteLog `"DisablePersonalDirChange is set to 1, so we will enable Simple Redirect Mode & not do traditional KnownFolder Redirection`"
         Write-Output `"DisablePersonalDirChange is set to 1, so we will enable Simple Redirect Mode & not do traditional KnownFolder Redirection`"
        `$SimpleRedirectMode=`$true
     }else{
        WriteLog `"DisablePersonalDirChange is nonexistent or not enabled, so we will do traditional KnownFolder Redirection`"
        Write-Output `"DisablePersonalDirChange is note set to 1, so we will do traditional KnownFolder Redirection`"
        `$SimpleRedirectMode=`$false
     }

   }

}else { # else for `$attemptKFM check
    
    `$SimpleRedirectMode=`$true     # if we are not attempting KFM, per bool variable setting, just do Simple Redirect Mode

} # end of `$attemptKFM check

WriteLog `"Simple Redirect Mode: `$SimpleRedirectMode `"
Write-Output `"Simple Redirect Mode: `$SimpleRedirectMode `"

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
    WriteLog `"Failed to download / read version info for Onedrive from `$xmlDownloadURL`"
    write-error `$_ -ErrorAction Continue
   
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
            ##
            If(`$detectedTenant -eq `$null){
                New-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -Value `$TenantID -PropertyType String -Force
                `$detectedTenant = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"ConfiguredTenantId`" -ErrorAction SilentlyContinue).ConfiguredTenantId
            }
            Write-Output `"Detected tenant `$detectedTenant`"
            WriteLog `"Detected tenant `$detectedTenant`"
            #we've either found a registry key with the correct TenantID or populated it, Onedrive has been started, let's now check for the folder path
            `$detectedFolderPath = (Get-ItemProperty -Path `"`$(`$subPath)\`" -Name `"UserFolder`" -ErrorAction SilentlyContinue).UserFolder
            ##
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
    Write-Output `"failed to detect user folder! Sleeping for 15 seconds`"
    Sleep -Seconds 15
    `$waited+=15   
     
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

#Clean Up any old Robocopy Log Files older than 1 days (a lot of these get created during the scheduled-runs, even if no copies are performed).  Adjust to keep these longer if you want.

Get-ChildItem -Path `"`$env:userprofile\Start-Robocopy-*`" | Where-Object {(`$_.LastWriteTime -lt (Get-Date).AddDays(-1))} | Remove-Item -Force -ErrorAction Ignore | Out-Null

# Perform First Migration if MIGRATION FLAG FILE <> Exist + Work Folders Path Exists

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

    #Work Folders and Flag File exist at the same time, so Work Folders content may still exist to migrate.
    # Prepare to move any present files in Work Folders root, and remove Work Folders root

    WriteLog `"Work Folders and Flag File exist at the same time, prepare to move any present files in WF folder & remove WF`"
    Write-Output `"Work Folders and Flag File exists at the same time, performing one-way Sync to OD4B from WF using Robocopy with /X CNO options`"
    #Perform WF File Clean-up Migration

    If(`$enableDataMigration -eq `$true){
   

        robocopy `"`"`$(`$WorkFoldersPath)`"`" `"`"`$(`$OneDriveUserPath)`"`" /E /MOVE /XC /XN /XO /LOG+:`$env:userprofile\Start-Robocopy-`$(Get-Date -Format 'yyyyMMddhhmmss').log

         # Robocopy /MOVE should delete Work Folders root folder entirely.
         # If the above fails to remove Work Folders root, or Work Folders root comes back, consider: 
         #
         # GPO or other mechanism that is bringing Work Folders Root back (needs to be un-published to your migrated-users)
         # -or-
         # File(s) or folder(s) was(were) present under Work Folders with Read-Only attribute set.  This can keep Robocopy /MOVE from deleting the Work Folders root. 

         # Check if Work Folders root is empty + delete, if empty
         Try{
            
            If((Get-ChildItem `$WorkFoldersPath -ErrorAction Stop | Measure-Object).Count -eq 0){ Remove-Item -Path `$WorkFoldersPath -Force -ErrorAction Stop | Out-Null}
        }Catch {
          
        }

    }

}

#############
# Custom Code Section -- 
#     here is where you may add custom Data Migration / cleanup code to be executed (e.g. deleting problem-files under Work Folders, etc)
#
# Example:
#   Remove-Item `"`$WorkFoldersPath\Pictures\Wallpaper-Backup\DesktopWallpaper.jpg`" -Force -ErrorAction Ignore | Out-Null

############


If(!`$redirectFoldersToOnedriveForBusiness){
    WriteLog `"Redirection was not enabled, therefore Script-Run is Complete.`"
    Write-Output `"Redirection was enabled, therefore Script-Run is Complete.`"
    Stop-Transcript
    Exit
}

If((`$ODFlagFileExist -eq `$true) -and (`$WorkFoldersExist -eq `$false)){

    WriteLog `"So the Migration Flag File exists & Work Folders do NOT exist = there is nothing to Migrate -- so let's check to see if Redirection is needed by sampling Desktop User Shell Properties`"
    Write-Output `"So the Migration Flag File exists & Work Folders do NOT exist = there is nothing to Migrate -- so let's check to see if Redirection is needed by sampling Desktop User Shell Properties`"

    `$UserShellFoldersRegPath = `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders`"

        `$RedirectDesktopRegVal  = `"`$OneDriveUserPath\Desktop`"
        `$LocalDesktopRegValName = `"{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}`"
        `$DesktopRegValName = `"Desktop`"
        
        # Read the current Registry Values into Variables
        
        `$LocalDesktopRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$LocalDesktopRegValName
        `$DesktopRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$DesktopRegValName
            
            If((`$LocalDesktopRegData = `"`$RedirectDesktopRegVal`") -and ( `$DesktopRegData = `"`$RedirectDesktopRegVal`")){

                WriteLog `"Work Folders do not exist, Migration Flagfile Exists, and Redirection of the Desktop shell folder was done.   Assuming all tasks complete and ending the Runtime Script.`"	
                Write-Output `"Work Folders do not exist, Migration Flagfile Exists, and Redirection of the Desktop shell folder was done.   Assuming all tasks complete and ending the Runtime Script.`"
                Stop-Transcript
                Exit

            }Else{

                WriteLog `"Desktop Folder Redirection is Still needed so script will continue...`"
                Write-Output `"Desktop Folder Redirection is Still needed so script will continue...`"
            }

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

# End of Folder Redirection Functions

### Remove Work Folders Sync URL and Set AutoProvision to Zero (0)

if((`$redirectFoldersToOnedriveForBusiness -eq `$true) -and (`$enableDataMigration -eq `$true)){

        # We're going to try and remove the Work Folders' AutoProvision value from the registry, if needed, but most environments require Admin rights to do this
        # Main / Deployment Script also will have already tried to remove this for all users of this system.

    try{
    WriteLog `"Removing Work Folders Sync URL and disabling AutoProvision`"
    `$WorkFoldersRegPath = `"HKCU:\Software\Policies\Microsoft\Windows\WorkFolders`"
    `$WorkFoldersSyncURL = `"SyncUrl`"

    `$ChecWFRegSyncURL = Test-RegistryKeyValue -Path `"HKCU:\Software\Policies\Microsoft\Windows\WorkFolders`" -Value `$WorkFoldersSyncURL -ErrorAction Ignore
        If(`$ChecWFRegSyncURL -eq `$true){
            Remove-ItemProperty -Path `$WorkFoldersRegPath -Name `$WorkFoldersSyncURL -Force -ErrorAction Ignore | Out-Null 
            New-ItemProperty -Path `$WorkFoldersRegPath -Name `"AutoProvision`" -Value 0 -PropertyType DWord -Force  -ErrorAction Stop | Out-Null
        } 
    }catch{
        #Write-Error `"Could not disable Work Folder Sync URL and/or AutoProvision! Sysadmin will need to disable WorkFolders Settings via GPO or other means`" -ErrorAction Continue
        #Write-Error `$_ -ErrorAction Continue
        Write-Output `"Could not disable Work Folder via Sync URL and/or AutoProvision Registry settings.`"  
        Write-Output `"Sysadmin will need to disable Work Folders via GPO or other means.`"
        WriteLog `"Could not disable Work Folder via Sync URL and/or AutoProvision Registry settings`"  
        WriteLog `"Sysadmin will need to disable Work Folders via GPO or other means.`"
          
    }
}

### Redirect Folders
#Write-Output `$detectedFolderPath
#Write-Output `$redirectFoldersToOnedriveForBusiness

If((!`$null -eq `$detectedFolderPath) -and (`$redirectFoldersToOnedriveForBusiness -eq `$true)){

    If(`$attemptKFM -eq `$false){`$SimpleRedirectMode = `$true}

    If(`$SimpleRedirectMode -eq `$false){
        #Traditional Known Folder Redirect Mode Will be used --
        WriteLog `"Traditional Known Folder Redirect Mode Will be used via SHSetKnownFolderPath function`" 
        Write-Host `"Traditional Known Folder Redirect Mode Will be used via SHSetKnownFolderPath function`"
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
            `$SimpleRedirectMode = `$true
        }
    }
    }
}

} # end of `$attemptKFM check

If(`$SimpleRedirectMode -eq `$true){

    #Simple Redirect Mode writes direct Registry settings to redirect Known Folders to Onedrive for Business
    WriteLog `"Simple Folder Redirect mode will be used via direct Registry writes instead of SHSetKnownFolderPath function`" 
    Write-Output `"Simple Folder Redirect mode will be used via direct Registry writes instead of SHSetKnownFolderPath function`"


        `$ShellFoldersRegPath = `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders`"
        `$UserShellFoldersRegPath = `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders`"

        `$RedirectDocumentsRegVal = `"`$OneDriveUserPath\Documents`"
        `$LocalDocumentsRegValName = `"{F42EE2D3-909F-4907-8871-4C22FC0BF756}`"
        `$DocumentsRegValName = `"Documents`"
        `$PersonalRegValName = `"Personal`"
        `$LocalPicturesRegValName = `"{0DDD015D-B06C-45D5-8C4C-F59713854639}`"
        `$PicturesRegValName = `"My Pictures`"
        `$RedirectPicturesRegVal = `"`$OneDriveUserPath\Pictures`"
        `$RedirectDesktopRegVal  = `"`$OneDriveUserPath\Desktop`"
        `$LocalDesktopRegValName = `"{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}`"
        `$DesktopRegValName = `"Desktop`"
        `$ReDirectFavoritesRegVal = `"`$OneDriveUserPath\Favorites`"
        `$FavoritesRegValName = `"Favorites`"
        
        # Read the current Registry Values into Variables
        
        `$LocalDocumentsRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$LocalDocumentsRegValName
        `$DocumentsRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$DocumentsRegValName
        `$LocalDesktopRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$LocalDesktopRegValName
        `$DesktopRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$DesktopRegValName
        `$LocalPicuturesRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$LocalPicturesRegValName
        `$PicuturesRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$PicturesRegValName
        `$FavoritesRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$FavoritesRegValName
        `$PersonalRegData = Get-ItemProperty -Path `$UserShellFoldersRegPath | Select-Object -ExpandProperty `$PersonalRegValName

        # Begin Checks to see if any Windows Shell registry entries are set to `"Work Folders`" path, and correct to OneDrive path if needed

        try{

            If (`$PersonalRegData = `"`$WorkFoldersPath\Documents`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$PersonalRegValName -Value `$RedirectDocumentsRegVal -PropertyType ExpandString -Force 
                New-ItemProperty -Path `$ShellFoldersRegPath -Name `"Personal`" -Value `$RedirectDocumentsRegVal -PropertyType String -Force 
                WriteLog `"Setting Personal Reg Documents Path`"
                Write-Output `"Setting Personal Reg Documents Path`"	
                    
            } Else {
                
                WriteLog `"Personal Reg Documents Path is not set to Work Folders. No Change Needed`"
                Write-Output `"Personal Reg Documents Path is not set to Work Folders. No Change Needed`"	
            }
            
            If (`$DocumentsRegData = `"`$WorkFoldersPath\Documents`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$DocumentsRegValName -Value `$RedirectDocumentsRegVal -PropertyType ExpandString -Force 
                WriteLog `"Setting Documents Registry Path Redirection Settings`"
                Write-Output `"Setting Documents Registry Path Redirection Settings`"	
                    
            } Else {
            
                WriteLog `"Documents Registry Path Redirection not set to Work Folders. No Change Needed`"
                Write-Output `"Documents Registry Path Redirection not set to Work Folders. No Change Needed`"		
            }
            
            
            If (`$LocalDocumentsRegData = `"`$WorkFoldersPath\Documents`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$LocalDocumentsRegValName -Value `$RedirectDocumentsRegVal -PropertyType ExpandString -Force 
                WriteLog `"Setting Documents Folder Redirection Path`"
                Write-Output `"Setting Documents Folder Redirection Path`"	
                    
            } Else {
                
                WriteLog `"Documents Folder Redirection Path is not set to Work Folders. No Change Needed`"
                Write-Output `"Documents Folder Redirection Path is not set to Work Folders. No Change Needed`"
            }
            
            If (`$LocalDesktopRegData = `"`$WorkFoldersPath\Desktop`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$LocalDesktopRegValName -Value `$RedirectDesktopRegVal -PropertyType ExpandString -Force 
                New-ItemProperty -Path `$ShellFoldersRegPath -Name `"Desktop`" -Value `$RedirectDesktopRegVal -PropertyType String -Force 
                    
                WriteLog `"Setting Desktop Folder Redirection Path`"	
                Write-Output `"Setting Desktop Folder Redirection Path`"
                    
            } Else {
            
                WriteLog `"Desktop Folder Redirection Path is not set to Work Folders. No Change Needed`"
                Write-Output `"Desktop Folder Redirection Path is not set to Work Folders. No Change Needed`"		
            }
            
            If (`$DesktopRegData = `"`$WorkFoldersPath\Desktop`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$DesktopRegValName -Value `$RedirectDesktopRegVal -PropertyType ExpandString -Force 
                    
                    WriteLog `"Setting Personal Reg Desktop Path`"
                    Write-Output `"Setting Personal Reg Desktop Path`"
                    
            } Else {
            
                WriteLog `"Personal Reg Desktop Path is not set to Work Folders. No Change Needed`"
                Write-Output `"Personal Reg Desktop Path is not set to Work Folders. No Change Needed`"
            }
            
            If (`$PicuturesRegData = `"`$WorkFoldersPath\Pictures`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$PicturesRegValName -Value `$RedirectPicturesRegVal -PropertyType ExpandString -Force 
                New-ItemProperty -Path `$ShellFoldersRegPath -Name `"My Pictures`" -Value `$RedirectPicturesRegVal -PropertyType String -Force 	
                WriteLog `"Setting Pictures Reg Desktop Path`"
                Write-Output `"Setting Pictures Reg Desktop Path`"
                    
            } Else {
            
                WriteLog `"Pictures Reg Desktop Path is not set to Work Folders. No Change Needed`"
                Write-Output `"Pictures Reg Desktop Path is not set to Work Folders. No Change Needed`"
            }
            
            If (`$LocalPicuturesRegData = `"`$WorkFoldersPath\Pictures`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$LocalPicturesRegValName -Value `$RedirectPicturesRegVal -PropertyType ExpandString -Force 
                    
                    WriteLog `"Setting Pictures Folder Redirection Path`"
                    Write-Output `"Setting Pictures Folder Redirection Path.`"
                    
            } Else {
                
                WriteLog `"Pictures Folder Redirection Path is not set to Work Folders. No Change Needed`"	
                Write-Output `"Pictures Folder Redirection Path is not set to Work Folders. No Change Needed`"
            }
            
            If (`$FavoritesRegData = `"`$WorkFoldersPath\Favorites`") {
                
                New-ItemProperty -Path `$UserShellFoldersRegPath -Name `$FavoritesRegValName -Value `$ReDirectFavoritesRegVal -PropertyType ExpandString -Force 
                New-ItemProperty -Path `$ShellFoldersRegPath -Name `$FavoritesRegValName -Value `$ReDirectFavoritesRegVal -PropertyType String -Force 
            
                WriteLog `"Setting Favorites Folder Redirection Path`"
                Write-Output `"Setting Favorites Folder Redirection Path.`"	
                    
            } Else {
            
                WriteLog `"Favorites Folder Redirection Path is not set to Work Folders.  No Change Needed`"
                Write-Output `"Favorites Folder Redirection Path is not set to Work Folders. No Change Needed`"
            }
            
            }catch{
            
                Write-Error `"Failed to redirect all folders using Regsitry writes!`" -ErrorAction Continue
                #Write-Error `$_ -ErrorAction Continue  
                WriteLog `"Failed to redirect all folders using Regsitry writes!`"
                 
            }
            
        }

        # Perform GPO Refresh if needed
        If(`$GPO_Refresh = `$true){
            WriteLog `"Refreshing GPO`"
            Write-Output `"Refreshing GPO`"
            gpupdate
        }


Stop-Transcript

LogInformationalEvent(`"Work Folders to OneDrive Migration Script-run completed for `" + `$env:UserName)
	
WriteLog `"WF to OneDrive Config & Data Migration Script-Run Complete`"

Exit (0)
"

$RuntimeScriptContent | Out-File $setRuntimeScriptPath -Force

#Whichever account first created this file, ensure other users can change it

try {
  
    icacls $setRuntimeScriptPath /grant:r BUILTIN\Users:F | Out-Null
}
catch {
    {1:<#terminating exception#>}
}


#######################################################
#
# End of code for Local Script for scheduled task to 
# run the script once
#
#######################################################

#End of Script - cleanup & Exit

Stop-Transcript

   LogInformationalEvent("Work Folders to OneDrive Migration Checks and Runtime Script-creation completed by " + $env:UserName)
   
   
   WriteLog "A Config & Migration script will be established in Scheduled Tasks or the HCKU "Run" section of the registry (depending on operational settings of this script)."

   IF($triggerRuntimeScriptHere -eq $True){
   
   
    $SchedTaskExists = $null
    $SchedTaskName = "OnedriveAutoConfig"
    $SchedTaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $SchedTaskName }
    Write-Output "Scheduled Task Exists: $SchedTaskExists"

    If($SchedTaskExists) {
        # Scheduled Task exists, so start the task as we exit. 
        WriteLog "WF to OneDrive Config & Migration Scheduled Task will now be run"
        Start-ScheduledTask -TaskName "OnedriveAutoConfig"

        } else {
        
            # Scheduled Task does not exist, launch the script directly here at the end
            start-process -FilePath "cmd.exe" -ArgumentList "/c $Env:SystemRoot\$setPSRuntimeLauncherPath" -Wait -Passthru 
            
        }
    }else {
    
        # Do Nothing
    
    }
        
    WriteLog "WF to OneDrive Migration Checks and Runtime Script-Creation is Complete"

    If($RunningAsSYSTEM -eq $True){Copy-Item "$Env:TEMP\$LogFileName" -Destination "$setRuntimeScriptFolder\$LogFileName" -Force -ErrorAction Ignore | Out-Null} 

	Exit (0)


