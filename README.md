# WF-2-OneDrive

Description 
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
