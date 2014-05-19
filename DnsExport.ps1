# USAGE:
# .\DnsExport.ps1 | Out-File .\dnsexport.sql

Import-Module DnsShell

### NOTE - PLEASE READ FIRST ###
# The script requires the DnsShell module for Powershell installed to work:
# http://dnsshell.codeplex.com/releases/view/68243
#
# IMPORTANT:
# 1. The domains and records tables of PowerDNS have to be empty
# 
# 2. To work properly, i had to open the sql file in notepad after export and save it as UTF-8,
#    and then do a dos2unix convertion on Linux before importing it into MySQL.
#    The file was unusable without these tasks for me.
#
# 3. The script should work fine with the most common record types:
#    SOA, A, AAAA, NS, MX, CNAME, SRV (That's what i used myself)
###

#############################
### CONFIGURATION - begin ###
#############################

# Doing a migration to Tupa v0.1?
# (Tables of tupa have to exist already before executing the queries this script generates, or it will fail)
$TupaMigration = $false
# ID of Tupa admin (Will be the owner of all added domains)
$TupaAdminId = 1

# if you want exclude your active directory domain from exporting, enter the domain here. Else add a nonexisting domain.
$AdDomain = 'example.com'

# Set new SOA Hostmaster address (set it to '' to not change anything)
$NewSoaHostmaster = 'hostmaster@example.com'

# Set old and new primary nameserver (set the same for both if nothing changes)
$OldPrimaryNameserver = 'olddns01.example.com'
$NewPrimaryNameserver = 'newdns01.example.com'

# Set old and new secondary nameserver (set the same for both if nothing changes)
$OldSecondaryNameserver = 'olddns02.example.com'
$NewSecondaryNameserver = 'newdns21.example.com'

# I had some old NS records in AD. Records with the following servers will be removed.
# Set to something random non existing (NOT EMPTY!) if you don't use them
$DeleteNs01 = 'deleredns01.example.com'
$DeleteNs02 = 'deleredns02.example.com'
$DeleteNs03 = 'deleredns03.example.com'

# Recor
# Set new time values to overwrite for all records. Set to '' to not change the current values
$NewSoaRefresh = '10800'
$NewSoaRetry = '3600'
$NewSoaExpire = '604800'
$NewSoaTtl = '86400'

###########################
### CONFIGURATION - end ###
###########################


# Used for auto-increment values
$DomainId = 1

# Get all zones
$Zones = Get-DnsZone | sort ZoneName
	
# Loop through zones, make changes and adjustments needed, and generate SQL query for domain
ForEach ($Zone in $Zones) {
    # Get all records of domain
    $Records = Get-DnsRecord -ZoneName $Zone.ZoneName

    # Skip AD domain (will stay on existing DNS)
    if ($($Zone.ZoneName) -eq $AdDomain -or $($Zone.ZoneName) -eq '_msdcs.' + $AdDomain) {
        continue
    }

    # Create SQL query for the domain
    Write-Output "INSERT INTO domains (id, name, type) VALUES ($DomainID, '$($Zone.ZoneName)', 'NATIVE');"
    
    # Add domain user relation for Tupa
    if ($TupaMigration -eq $true) {
        Write-Output "INSERT INTO domain_owners (dom_id, usr_id) VALUES ($DomainID, $TupaAdminId);"
    }


    # Loop through records and make adjustments needed
    for($i=0; $i -le $Records.length-1; $i++) {
        # Set a temporary variable which only contains the hostname.
        # Used to do the initial sorting much cleaner if Tupa is used to manage records.
        $NameTrimmed = $Records[$i].Name.Replace($Zone.ZoneName, $null)
        $Records[$i] | Add-Member -MemberType NoteProperty -Name NameTrimmed -Value $NameTrimmed

        # Clean the record type value (no idea why this is used, but sorting is wrong if not done)
        $RecordType = [string]$Records[$i].RecordType
        $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordType -Value $RecordType.Trim()

        # Remove the dot at the end of content because it's not used in PowerDNS
        $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $($Records[$i].RecordData).TrimEnd(".")
        # $Records[$i] | Add-Member -MemberType NoteProperty -Name TupaSorting -Value $i

        # Set TTL of all records to 86400 by default
        $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name TTL -Value 86400

        # Modify specific record types
        if ($($Records[$i].RecordType) -eq 'SOA') {
            # Replace primary nameserver, hostmaster address and SOA time values as needed
            $RecordData = $($Records[$i].RecordData).Trim() -replace '\s+', ' '
            $RecordDataSplitted = $RecordData.Split(" ")
            $RecordDataSplitted[0] = $NewPrimaryNameserver
            $RecordDataSplitted[1] = @{$true=$RecordDataSplitted[1];$false=$NewSoaHostmaster}[$NewSoaHostmaster -eq '']
            $RecordDataSplitted[2] = Get-Date -format yyyyMMdd00
            $RecordDataSplitted[3] = @{$true=$RecordDataSplitted[3];$false=$NewSoaRefresh}[$NewSoaRefresh -eq '']
            $RecordDataSplitted[4] = @{$true=$RecordDataSplitted[4];$false=$NewSoaRetry}[$NewSoaRetry -eq '']
            $RecordDataSplitted[5] = @{$true=$RecordDataSplitted[5];$false=$NewSoaExpire}[$NewSoaExpire -eq '']
            $RecordDataSplitted[6] = @{$true=$RecordDataSplitted[6];$false=$NewSoaTtl}[$NewSoaTtl -eq '']

            $RecordData = $RecordDataSplitted -join " "
            
            $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $RecordData

            # Set TTL of SOA records to 86400 by default
            #$Records[$i] | Add-Member -Force -MemberType NoteProperty -Name TTL -Value 86400
        } elseif ($($Records[$i].RecordType) -eq 'MX') {
            # Split priority and server and save them to separate values as needed by PowerDNS
            $RecordData = $($Records[$i].RecordData).Trim()
            $RecordDataSplitted = $RecordData.Split(" ")
            $Records[$i] | Add-Member -MemberType NoteProperty -Name RecordPrio -Value $RecordDataSplitted[0]
            $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $RecordDataSplitted[1]
        } elseif ($($Records[$i].RecordType) -eq 'NS') {
            # Replace nameservers and clean up some old depricated ones which doesn't exist anymore
            if ($($Records[$i].RecordData) -eq $DeleteNs01 -or $($Records[$i].RecordData) -eq $DeleteNs02 -or $($Records[$i].RecordData) -eq $DeleteNs03) {
                # Because it's a collection of fixed size, it unfortunateley can't be removed easily
                # Set record type to delete, and skip it later... What a dirty hack ;-)
                $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordType -Value 'DELETE'
            } elseif ($($Records[$i].RecordData) -eq $OldPrimaryNameserver) {
                $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $NewPrimaryNameserver
            } elseif ($($Records[$i].RecordData) -eq $OldSecondaryNameserver) {
                $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $NewSecondaryNameserver
            }

            # Set TTL of all NS records to 86400
            #$Records[$i] | Add-Member -Force -MemberType NoteProperty -Name TTL -Value 86400
        } elseif ($($Records[$i].RecordType) -eq 'SRV') {
            # Split off priority and save it to prio fied
            $RecordData = $($Records[$i].RecordData).Trim()
            $RecordDataSplitted = $RecordData.Split(" ")
            # Cut off priority
            $RecordContent = ($RecordDataSplitted[1..$RecordDataSplitted.Length])
            $RecordContent = $RecordContent  -join " "
            $Records[$i] | Add-Member -MemberType NoteProperty -Name RecordPrio -Value $RecordDataSplitted[0]
            $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordData -Value $RecordContent
        }

        # Set prio to 0 if not set
        if (!$($Records[$i].RecordPrio)) {
            $Records[$i] | Add-Member -Force -MemberType NoteProperty -Name RecordPrio -Value 0
        }
    }

    # Sort records
    $Records = $Records | Sort-Object -Property NameTrimmed,@{expression="RecordType";Descending=$true},RecordData

    $i = 0
    # Generate SQL queries for records
    ForEach ($Record in $Records) {
        # Check if record should be skipped
        if ($($Record.RecordType) -eq 'DELETE') {
            continue
        }

        # $RecordName = $Record.Name.Replace($Zone.ZoneName, $null)
        # Write-Host $Record.Name $Record.TTL $Record.RecordClass $Record.RecordType $Record.RecordData
        if ($TupaMigration -eq $true) {
            Write-Output "INSERT INTO records (domain_id, name, type, content, ttl, prio, tupasorting) VALUES ($DomainID, '$($Record.Name)', '$($Record.RecordType)', '$($Record.RecordData)', $($Record.TTL), $($Record.RecordPrio), $i);"
        } else {
            Write-Output "INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES ($DomainID, '$($Record.Name)', '$($Record.RecordType)', '$($Record.RecordData)', $($Record.TTL), $($Record.RecordPrio));"
        }
        $i++
    }

    $DomainId++
    Write-Output `n
}