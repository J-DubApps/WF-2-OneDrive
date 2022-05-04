# WF-2-OneDrive

Description 
	
	This PS script will migrate a Windows 10 Endpoint's User data sync settings
	from Work Folders over to OneDrive for Business.
       
       It is targeted to silently run OneDrive Setup and sign-in the user 
       (if computer in a Hybrid Azure AD domain join), sets redirection for Known Folders, 
       and finally moves data from Work Folders to OneDrive folder using Robocopy /Move 
       in a Wrapper Function. 
       
