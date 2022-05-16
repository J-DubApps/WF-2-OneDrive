# WF-2-OneDrive

Description 
	
	This PS script will migrate a Windows 10 Endpoint's User Work Folder sync settings
	and data over to OneDrive for Business.  You can optionally have it not do
	the data migration part, and only configure OneDrive and redirect Known Folders.
       
       It is targeted to silently run OneDrive Setup and sign-in the user 
       (if computer in a Hybrid Azure AD domain join), sets redirection for Known Folders, 
       and finally moves data from Work Folders to OneDrive folder using Robocopy /Move 
       in a Wrapper Function. 
       
LICENSE: GNU General Public License, version 3 (GPLv3) 

