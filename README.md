# WF-2-OneDrive

## Description 
	
	This PS script will migrate a Windows 10 Endpoint's User Work Folder sync settings
	and their Work Folder data over to OneDrive for Business and leave OneDrive sync 
	enabled (while disabling WF sync).  Useful for scenarios where back-end data
 	migration cannot be performed in advance (the client does the heavy-lifting).
	
	You can optionally have it not do the data migration or Folder Redirection steps, and only 
	configure OneDrive Client and stop, via several Boolean variable settings.  Useful for scenarios
 	where you are already doing bulk data migration of user WF data to OneDrive for Business 
 	via the SharePoint File Migration Tool:
  	https://learn.microsoft.com/en-us/sharepointmigration/fileshare-to-odsp-migration-guide
       
       It is targeted for Domain-joined PC Endpoints, and PCs that are in Azure AD Hybrid Join status.  
       Script will silently run OneDrive Setup and sign the user into the OneDrive client and
       (if enabled) sets redirection for Known Folders, and finally (if enabled) moves data 
       a user's Work Folders to their OneDrive folder using Robocopy /Move method.
       
## Disclaimers

* No warranty or guarantee is provided, explicit or implied, for any purpose, use, or adaptation, whether direct or derived, for any code examples or sample data provided on this site.
* USE AT YOUR OWN RISK
* User assumes ANY AND ALL RISK and LIABILITY for any and all usage of examples provided herein.  Author assumes no liability for any consequences of using these examples for any purpose whatsoever.

LICENSE: GNU General Public License, version 3 (GPLv3) 

