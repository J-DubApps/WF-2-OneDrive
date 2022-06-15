#Requires -Version 5.1
#Requires -PSEdition Desktop
<#
    Name: WF-2-ODfB-Clean.ps1
    Version: 0.1.1 (30 May 2022)
.NOTES
    Author: Julian West
    Creative GNU General Public License, version 3 (GPLv3);
.SYNOPSIS
    Optional Cleanup Script for WF-2-ODfB.ps1 and WF-2-ODfB-Mig.ps1
.DESCRIPTION
    This contains an excerpt of the code from the Runtime Script (WF-2-ODfB-Mig.ps1) for
    removing the Registry Run and/or Scheduled Tasks created by WF-2-ODfB.ps1 (which kick-off repeated
    runs of WF-2-ODfB.Mig.ps1, and runs at Logon).  
    It also deletes the Runtime Script itself ( WF-2-ODfB-Mig.ps1) and the silent .vbs Launch wrapper 
    from their default location under C:\ProgramData\WF-2-ODfB.  
   
    The Runtime Script already does it's own cleanup once an Endpoint user's Work Folders root no
    longer exists.  But sometimes you may wish to terminate/cleanup the Runtime Script operation early.

    This script is for those situations, where you wish to have a separarate task perform cleanup via MECM / other 
    deployment system.   It is also intended for IT groups who may have deployed WF-2-ODfB.ps1 to shared multi-user
    Endpoints (Floating Staff PCs, Terminal Servers, etc), and wish to remove it earlier than planned.
    
    This script, like the WF-2-ODfB-Mig.ps1 Runtime Script, will perform cleanup based on:
    
    Presence of OneDrive Migration Flag file + 
    Non-Existent Work Folders root under %USERPROFILE%
    
    In the above condition, this script will remove the Registry Run key and/or Scheduled Tasks established by WF-2-ODfB.ps1.
    Requirements: Windows 10, Powershell 5.1 or above
    NOTE:
    If your Deployment to endpoints originally used Scheduled Tasks to migrate users to OneDrive 
    (preferred for Endpoints that are remote or on VPN) then it is recommended that you run this 
    script Elevated or as SYSTEM (via MECM deployment) to guarantee a good cleanup of the Scheduled Task. 
    If Script is run non-elevated on an endpoint, script still makes a "best effort" attempt at deleting 
    any found Scheduled Task and/or Registry Run entries associated with the original run of WF-2-ODfB.ps1.  
.LINK
    https://github.com/J-DubApps
    #>
###############################################################################################
#	Change Control (add dates and changes below in your own organization)
###############################################################################################
#
#	Date		Modified by		Description of modification
#----------------------------------------------------------------------------------------------
#
#   05/30/2022              Initial version by Julian West
#
###############################################################################################

#-----------------------------------------------------------[Execution]------------------------------------------------------------


### REQUIRED CONFIGURATION ###
## *REQUIRED* Variables, needed for successful script run.  Set to the same env values that you set in WF-2-ODfB.ps1 - 
#

$OneDriveFolderName = "OneDrive - McKool Smith" #  <--- This is your Tenant OneDrive folder name (can be confirmed via manual install of ODfB client)
# **required - this is the OneDrive folder name that will exist under %USERPROFILE%
# This folder is usually named from your O365 Tenant's Org name by default, or is customized in GPO/Registry.
# This default folder name can be confirmed via a single manual install of OneDrive on a standalone Windows endpoint

    $MigrationFlagFileName = "FirstOneDriveComplete.flg"
# This is the Migration Flag File variable and should be set to the same file name that was used in WF-2-ODfB.ps1
# This is checked to exist at the following path before any cleanup takes placE:  %userprofile%\$OneDriveFolderName\$MigrationFlagFileName
#

$logFileX64 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx64.log"    #Tracelog file for x64
$logFileX86 = Join-Path $Env:TEMP -ChildPath "OnedriveAutoConfigx86.log"    #Tracelog file for x86

$LogFileName = "ODfB_Cleanup-$env:username.log" # <-- General Log file name (less detail than TraceLog, audience is IT or end user)
#  It is saved during Runtime to current %userprofile%\$LogFileName
#
#

#########################################################################
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

If(($RunningAsSYSTEMCheck -eq $env:UserName) -and ($DeployRuntimeScriptOnly -ne $true)){
    $RunningAsSYSTEM = $True
    Write-Output "Running as SYSTEM, may be running non-Interacrtively via a Deployment tool (MECM etc)"
} else {
    $RunningAsSYSTEM = $False
    Write-Output "Running as User, must be running as SYSTEM or with Admin rights"
}

#Set the Logfile Location based on this script's mode

If($RunningAsSYSTEM = $True){

    #IF we're set in DeployRuntimeScriptOnly mode, we'll place the logfile in our Runtime Script location
    $LogFilePath = "$Env:TEMP\$LogFileName"
 
        icacls $LogFilePath /grant:r BUILTIN\Users:F | Out-Null
    
}else{

    #IF we're running this script interactively or not in Deploy only mode, we'll place the logfile in the User Profile Path
    $LogFilePath = "$env:userprofile\$LogFileName"
}

If(!$RunningAsSYSTEM){WriteLog "Configured Migration Flag File: $FirstOneDriveComplete"}

WriteLog "Configured Path for This Logfile: $LogFilePath"
Write-Output "Configured Path for This Logfile: $LogFilePath"

#Set system.io variable for operations on Migration Flag file
[System.IO.DirectoryInfo]$FirstOneDriveCompletePath = $FirstOneDriveComplete

if(![System.IO.File]::Exists($FirstOneDriveComplete)){$ODFlagFileExist = $false}else{$ODFlagFileExist  = $true}

Write-output "Migration Flag File Exists true or false: $ODFlagFileExist"

#Set system.io Variable to check if Work Folders Path exists

[System.IO.DirectoryInfo] $WorkFoldersPathCheck = $WorkFoldersPath

 If($WorkFoldersPathCheck){Write-Output "Work Folders Path checked and physically exists"}

#Use system.io variable for File & Directory operations to check for Migration Flag file & Work Folders Path
If([System.IO.Directory]::Exists($WorkFoldersPath)){$WorkFoldersExist = $true}else{$WorkFoldersExist = $false}

#Set variable if we encounter both OneDrive Flag File and Work Folders paths at the same time
$WF_and_Flagfile_Exist = $null
If(($ODFlagFileExist -eq $true)  -and ($WorkFoldersExist -eq $true)){$WF_and_Flagfile_Exist = $true}else{$WF_and_Flagfile_Exist = $false}

If(($WF_and_Flagfile_Exist -eq $false) -and ($ODFlagFileExist -eq $true)){$scriptCleanup = $true}else{$scriptCleanup = $false}

If($scriptCleanup -eq $true){

# Check for Local Admin Rights (expect that user is non-Admin unless running as SYSTEM, but always check anyway)

If($RunningAsSYSTEM -eq $False){  #If we're not running as SYSTEM, we should check for Admin rights

    $isLocalAdmin = Test-IsLocalAdministrator

    Write-Output "Local Administrator Rights True or False: $isLocalAdmin"

#If user is a non-Admin as-expected, check to see if user has Scheduled Task creation rights

    If($isLocalAdmin -eq $false){
  
        #User running this process is a non-Admin user, therefore they do not have Scheduled Task creation rights
        $SchedTasksRights = $false
        
        Write-Output "User $env:USERNAME is not running this script with Admin rights, therefore may not be able to delete any Scheduled Task"
        WriteLog "User $env:USERNAME is not running this script with Admin rights, therefore may not be able to delete any Scheduled Task"

    }Else{

        #User running this process has Admin rights, therefore can create Scheduled Tasks
        Write-Output "User $env:USERNAME has Admin rights, therefore can delete Scheduled Tasks"
        WriteLog "User $env:USERNAME has Admin rights, therefore can delete Scheduled Tasks"

    }
}   #end $RunningAsSYSTEM check

$SchedTaskExists = $null
$SchedTaskName = "OnedriveAutoConfig"
$SchedTaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $SchedTaskName }


If($SchedTaskExists){
    Write-Output "Scheduled Task Exists"
    Unregister-ScheduledTask -TaskName $SchedTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

Get-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Remove-ItemProperty -Name OnedriveAutoConfig -Force -ErrorAction SilentlyContinue

$setRuntimeScriptFolder = Join-Path $Env:ProgramData -ChildPath "WF-2-ODfB"
$setPSRuntimeLauncherPath = Join-Path $setRuntimeScriptFolder -ChildPath "WF-2-ODfB-Mig.vbs"

Remove-Item $setPSRuntimeLauncherPath -Force  -Recurse -ErrorAction SilentlyContinue 
Remove-Item $MyInvocation.MyCommand.Source -Force -ErrorAction SilentlyContinue


}  # end of $scriptCleanup check

Exit (0)