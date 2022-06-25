#Credit for original script to Helge Klein https://helgeklein.com.
#Adapted to allow higher numbers of users with the same information set.

# Summary of hamal03 cahnges
# Moved postal codes and phone prefix to address file
# Create "Company" OU and employee and departments ou below that
#    create department groups and add user to their department group
# Filled Adrresses with Dutch addresses from fakenamegenerator.com.
#
# Summary of changes.
# Reduced Male and Female names into one list for ease of expansion
# Changed Displayname code to create each combination of names possible
# Changed sAMAccountname generation to add unique account ID with orgShortName as suffix.

Set-StrictMode -Version 2
$DebugPreference = "SilentlyContinue" # SilentlyContinue | Continue
Import-Module ActiveDirectory

# Set the working directory to the script's directory
Push-Location (Split-Path ($MyInvocation.MyCommand.Path))

#
# Global variables
#
# User properties
$ADdomain="ad.rwlab.lcl"             # AD domain to fill with fake users
$mailDomain = "rwlab.lcl"            # Domain is used for e-mail address (leaf empty for AD domain)
$BaseOU = "OU=RWLab"                 # "Company" OU under the domain root
$empou = "OU=Employees"              # OU under "Company" OU where the users are created
$dptou = "OU=Departments"            # OU under "Company" OU where Department groups are created
$initialPassword = "S3cr37P@ssw0rd"  # Initial password set for the user
$company = "RWLab POC"               # Used for the user object's company attribute
$departments = (                     # Departments and associated job titles to assign to the users
    @{"Name" = "Finance & Accounting"; Positions = ("Manager", "Accountant", "Data Entry")},
    @{"Name" = "Human Resources"; Positions = ("Manager", "Administrator", "Officer", "Coordinator")},
    @{"Name" = "Sales"; Positions = ("Manager", "Representative", "Consultant")},
    @{"Name" = "Engineering"; Positions = ("Manager", "Engineer", "Scientist")},
    # @{"Name" = "Marketing"; Positions = ("Manager", "Coordinator", "Assistant", "Specialist")},
    # @{"Name" = "Consulting"; Positions = ("Manager", "Consultant")},
    # @{"Name" = "Planning"; Positions = ("Manager", "Engineer")},
    # @{"Name" = "Contracts"; Positions = ("Manager", "Coordinator", "Clerk")},
    # @{"Name" = "Purchasing"; Positions = ("Manager", "Coordinator", "Clerk", "Purchaser")},
    @{"Name" = "IT"; Positions = ("Manager", "Engineer", "Technician", "Administrator")}
)
$addRFC2307 = $false                # Add Unix attributes
$nameAccounts = $false              # use sAMAccountName based on first letter + last name i.o. "p" + employeenumber

# Country codes for the countries used in the address file
[System.Collections.ArrayList]$phoneCountryCodes = @{"NL" = "+31"; "GB" = "+44"; "DE" = "+49"}

# Other parameters
$userCount = 200                    # How many users to create

# TSV Files used
$firstNameFile = "Firstnames.txt"   # Format: FirstName,Gender
$lastNameFile = "Lastnames.txt"     # Format: LastName
$addressFile = "Addresses.txt"      # Format: Street,PostalCode,City,PhoneAreaCode

# Generate base part of DN from AD Domain
$ADDN=""
foreach ($elem in $ADdomain.split(".")) {
    $ADDN = $ADDN + "DC=" + $elem + ","
}
$ADDN = $ADDN.TrimEnd(",")

# Create the OU's
New-ADOrganizationalUnit -Name $BaseOU.TrimStart("OU=") -Path ($ADDN)
New-ADOrganizationalUnit -Name $empou.TrimStart("OU=") -Path ($BaseOU + "," + $ADDN)
New-ADOrganizationalUnit -Name $dptou.TrimStart("OU=") -Path ($BaseOU + "," + $ADDN)
$empou = $empou + "," + $BaseOU + "," + $ADDN

# Create the groups
foreach ($dpt in $departments)
{
    New-ADGroup -Name $dpt.Name -GroupCategory Security -GroupScope Global -Path ($dptou `
        + "," + $BaseOU + "," + $ADDN)
}

#
# Read input files
#
# utf7 will remove some "illegal" characters from the names as those characters
# are not displayed properly (in WS2012R2)
$firstNames = Import-CSV $firstNameFile -Encoding utf7 
$lastNames = Import-CSV $lastNameFile -Encoding utf7
$addresses = Import-CSV $addressFile -Encoding utf7

#
# Preparation
#
$securePassword = ConvertTo-SecureString -AsPlainText $initialPassword -Force

#
# Create the users
#
# Create (and overwrite) new array lists [0]
$CSV_Fname = New-Object System.Collections.ArrayList
$CSV_Lname = New-Object System.Collections.ArrayList
$CSV_Addr = New-Object System.Collections.ArrayList

#Populate entire $firstNames, $lastNames and $addresses into the array
$CSV_Fname.Add($firstNames)
$CSV_Lname.Add($lastNames)
$CSV_Addr.Add($addresses)

# Sex & name
$i = 0
while ($true)
{
    if ($i -lt $userCount)
    {
        $fnidx = Get-Random -Minimum 0 -Maximum $firstNames.Count
        $lnidx = Get-Random -Minimum 0 -Maximum $lastNames.Count
        $adidx = Get-Random -Minimum 0 -Maximum $addresses.Count
        $Fname = $firstNames[$fnidx].FirstName
        $Lname = $lastNames[$lnidx].LastName
        $Addrs = $addresses[$adidx]
      
        #Capitalise first letter of each name
        $displayName = $Fname + " " + $Lname
      
        # Address
        $street = $Addrs.Street + " " + (Get-Random -Minimum 1 -Maximum 300)
        $city = $Addrs.City
        $postalCode = $Addrs.PostalCode
        $country = $Addrs.Country
        # match the phone country code to the selected country above
        $matchcc = $phoneCountryCodes.GetEnumerator() | Where-Object {$_.Name -eq $country}
      
        # Department & title
        $departmentIndex = Get-Random -Minimum 0 -Maximum $departments.Count
        $department = $departments[$departmentIndex].Name
        $title = $departments[$departmentIndex].Positions[$(Get-Random -Minimum 0 `
            -Maximum $departments[$departmentIndex].Positions.Count)]
      
        # Phone number
        if ($matchcc.Name -notcontains $country)
        {
            Write-Debug ("ERROR: No country code found for $country")
            continue
        }
        $homePhone = ($matchcc.Value + ($Addrs.PhoneNet) + " " + (Get-Random `
            -Minimum 1000000000 -Maximum 9999999999)).Substring(0,13)
      
        # Build the sAMAccountName: $orgShortName + employee number
        $employeeNumber = Get-Random -Minimum 50000 -Maximum 99999
        if ($nameAccounts)
        {
            $sAMAccountName = ( $Fname.Substring(0,1) + $Lname ).ToLower().replace(' ','')
        }
        else
        {
            $sAMAccountName = 'p' + $employeeNumber
        }
        if (-not ( $mailDomain ))
        {
            $mailDomain = ( $ADdomain )
        }
        $emailAddress = ( $Fname + '.' + $Lname + '@' + $mailDomain ).replace(' ','')
        $userExists = $false
        Try   { $userExists = Get-ADUser -LDAPFilter "(sAMAccountName=$sAMAccountName)" }
        Catch { }
        if ($userExists)
        {
            continue
        }
      
        #
        # Create the user account
        #
        New-ADUser -SamAccountName $sAMAccountName -Name $displayName -Path $empou `
            -AccountPassword $securePassword -Enabled $true -GivenName $Fname `
            -Surname $Lname -DisplayName $displayName -EmailAddress $emailAddress `
            -StreetAddress $street -City $city -PostalCode $postalCode `
            -Country $country -UserPrincipalName "$sAMAccountName@$ADdomain" `
            -Company $company -Department $department -EmployeeNumber $employeeNumber `
            -Title $title -HomePhone $homePhone
        if ($addRFC2307) {
            # Add RFC2307 attributes
            $homeDirectory="/home/" + $sAMAccountName
            Set-ADUser -Identity $sAMAccountName -add @{uid="$sAMAccountName" ; `
                uidNumber="$employeeNumber" ; gidNumber="$employeeNumber" ; `
                gecos="$displayName" ; loginShell="/bin/bash" ; homeDirectory="$homeDirectory"}
        }
        # Add user to group
        Add-ADGroupMember -Identity "$department" -Members "$sAMAccountName"
      
        "Created user #" + ($i+1) + ", $displayName, $sAMAccountName, $title, $department, $homePhone, $country, $street, $city"
        $i = $i+1
      
        if ($i -ge $userCount)
        {
            "Script Complete. Exiting"
            exit
        }
   }
}
