Powershell DNS Export
=====================
Exports DNS domains and records from Windows DNS to SQL queries to be imported into a MySQL database of PowerDNS.


Usage
=====
.\DnsExport.ps1 | Out-File .\dnsexport.sql


Requirements
============
The script requires the DnsShell module for Powershell installed to work:

http://dnsshell.codeplex.com/releases/view/68243


Notes
=====
- The domains and records tables of PowerDNS have to be empty

- IMPORTANT: To work properly, i had to open the sql file in notepad after export and save it as UTF-8, and then do a dos2unix convertion on Linux before importing it into MySQL. The file was unusable without these tasks for me.

- The script should work fine with the most common record types:
  SOA, A, AAAA, NS, MX, CNAME, SRV (That's what i used myself)

- Tested on Windows 2008 Server


License
=======
GPLv3, see LICENCE file.
