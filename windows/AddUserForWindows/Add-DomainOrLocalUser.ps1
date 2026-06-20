<#
.SYNOPSIS
Creates a user in the current Active Directory domain when domain-joined, or locally when not domain-joined.

.DESCRIPTION
The script detects whether the computer is joined to an Active Directory domain.
If it is domain-joined, it creates the user in the current domain.
If it is not domain-joined, it creates a local Windows user.

Run PowerShell as an administrator. For domain user creation, run as a domain administrator.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-RandomPassword {
    param(
        [int]$Length = 10
    )

    if ($Length -lt 3) {
        throw "Password length must be at least 3."
    }

    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghijkmnopqrstuvwxyz"
    $digits = "23456789"
    $all = ($upper + $lower + $digits).ToCharArray()

    $required = @(
        $upper[(Get-Random -Minimum 0 -Maximum $upper.Length)]
        $lower[(Get-Random -Minimum 0 -Maximum $lower.Length)]
        $digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]
    )

    $remaining = for ($i = 0; $i -lt ($Length - $required.Count); $i++) {
        $all[(Get-Random -Minimum 0 -Maximum $all.Length)]
    }

    $passwordChars = @($required + $remaining) | Sort-Object { Get-Random }
    return -join $passwordChars
}

function Read-NonEmptyValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    do {
        $value = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "Value cannot be empty. Please try again." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    do {
        $answer = (Read-Host "$Prompt (Y/N)").Trim()
        switch -Regex ($answer) {
            "^(Y|y|Yes|yes)$" { return $true }
            "^(N|n|No|no)$" { return $false }
            default { Write-Host "Please enter Y or N." -ForegroundColor Yellow }
        }
    } while ($true)
}

function Wait-BeforeExit {
    Write-Host ""
    Read-Host "Press Enter to exit"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EnvironmentInfo {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $isDomainJoined = [bool]$computerSystem.PartOfDomain

    if (-not $isDomainJoined) {
        return [pscustomobject]@{
            IsDomainJoined = $false
            DomainName     = $null
            TargetType     = "Local"
        }
    }

    return [pscustomobject]@{
        IsDomainJoined = $true
        DomainName     = $computerSystem.Domain
        TargetType     = "Active Directory domain"
    }
}

function Import-ActiveDirectoryModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "The ActiveDirectory PowerShell module is not installed. Install RSAT Active Directory tools and run the script again."
    }

    Import-Module ActiveDirectory
}

function New-RandomUserName {
    param(
        [bool]$ForDomain
    )

    do {
        $userName = "mu{0:D4}" -f (Get-Random -Minimum 0 -Maximum 10000)
        if ($ForDomain) {
            $exists = Get-ADUser -Filter "SamAccountName -eq '$userName'" -ErrorAction SilentlyContinue
        }
        else {
            $exists = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
        }
    } while ($null -ne $exists)

    return $userName
}

function Test-TargetUserExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Environment
    )

    if ($Environment.IsDomainJoined) {
        return $null -ne (Get-ADUser -Filter "SamAccountName -eq '$UserName'" -ErrorAction SilentlyContinue)
    }

    return $null -ne (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)
}

function New-TargetUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Environment
    )

    if (Test-TargetUserExists -UserName $UserName -Environment $Environment) {
        throw "The user '$UserName' already exists."
    }

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    if ($Environment.IsDomainJoined) {
        New-ADUser `
            -Name $UserName `
            -SamAccountName $UserName `
            -UserPrincipalName "$UserName@$($Environment.DomainName)" `
            -AccountPassword $securePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $false

        return [pscustomobject]@{
            Target          = $Environment.TargetType
            Domain          = $Environment.DomainName
            UserName        = $UserName
            UserPrincipalName = "$UserName@$($Environment.DomainName)"
            Password        = $Password
        }
    }

    New-LocalUser `
        -Name $UserName `
        -Password $securePassword `
        -FullName $UserName `
        -Description "Generated by Add-DomainOrLocalUser.ps1"

    return [pscustomobject]@{
        Target            = $Environment.TargetType
        ComputerName      = $env:COMPUTERNAME
        UserName          = $UserName
        UserPrincipalName = $null
        Password          = $Password
    }
}

try {
    if (-not (Test-IsAdministrator)) {
        Write-Host "This script must be run as administrator. Please open PowerShell as administrator and run it again." -ForegroundColor Red
        Wait-BeforeExit
        exit 1
    }

    Write-Host "Checking the current environment..." -ForegroundColor Cyan
    $environment = Get-EnvironmentInfo

    Write-Host "Detected target: $($environment.TargetType)" -ForegroundColor Green
    if ($environment.IsDomainJoined) {
        Write-Host "Detected domain: $($environment.DomainName)" -ForegroundColor Green
        Import-ActiveDirectoryModule
    }
    else {
        Write-Host "This computer is not joined to a domain. A local user will be created." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Choose an option:"
    Write-Host "1. Create a specified username and password"
    Write-Host "2. Create a random user"

    do {
        $choice = Read-Host "Enter 1 or 2"
        if ($choice -notin @("1", "2")) {
            Write-Host "Invalid option. Please enter 1 or 2." -ForegroundColor Yellow
        }
    } while ($choice -notin @("1", "2"))

    if ($choice -eq "1") {
        do {
            $userName = Read-NonEmptyValue -Prompt "Enter the username without the @domain part"
            if ($userName -match "@") {
                Write-Host "Do not include the @domain part. Please enter only the username." -ForegroundColor Yellow
            }
        } while ($userName -match "@")

        $useCustomPassword = Read-YesNo -Prompt "Do you want to specify a password"
        if ($useCustomPassword) {
            $password = Read-NonEmptyValue -Prompt "Enter the password. Make sure it meets the password policy"
        }
        else {
            $password = New-RandomPassword
        }
    }
    else {
        $userName = New-RandomUserName -ForDomain:$environment.IsDomainJoined
        $password = New-RandomPassword
    }

    $createdUser = New-TargetUser -UserName $userName -Password $password -Environment $environment

    Write-Host ""
    Write-Host "User created successfully." -ForegroundColor Green
    Write-Host "Generated user information:" -ForegroundColor Cyan
    $createdUser | Format-List
    Wait-BeforeExit
}
catch {
    Write-Host ""
    Write-Host "Failed to create the user." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "- The password does not meet the domain or local password policy."
    Write-Host "- The username already exists."
    Write-Host "- The ActiveDirectory module is missing on this computer."
    Write-Host "- PowerShell was not run as administrator."
    Wait-BeforeExit
    exit 1
}
