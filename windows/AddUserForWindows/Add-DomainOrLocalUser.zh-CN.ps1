<#
.SYNOPSIS
在当前 Active Directory 域环境中创建用户；如果不是域环境，则创建本地用户。

.DESCRIPTION
脚本会检测当前计算机是否加入 Active Directory 域。
如果已加入域，则在当前域中创建用户。
如果未加入域，则创建本地 Windows 用户。

请以管理员身份运行 PowerShell。创建域用户时，请使用域管理员身份运行。
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
        throw "密码长度至少需要 3 位。"
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
            Write-Host "输入不能为空，请重新输入。" -ForegroundColor Yellow
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
            default { Write-Host "请输入 Y 或 N。" -ForegroundColor Yellow }
        }
    } while ($true)
}

function Wait-BeforeExit {
    Write-Host ""
    Read-Host "按 Enter 键退出"
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
            TargetType     = "本地环境"
        }
    }

    return [pscustomobject]@{
        IsDomainJoined = $true
        DomainName     = $computerSystem.Domain
        TargetType     = "Active Directory 域环境"
    }
}

function Import-ActiveDirectoryModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "未安装 ActiveDirectory PowerShell 模块。请安装 RSAT Active Directory 工具后重新运行脚本。"
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
        throw "用户 '$UserName' 已存在。"
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
            Target            = $Environment.TargetType
            Domain            = $Environment.DomainName
            UserName          = $UserName
            UserPrincipalName = "$UserName@$($Environment.DomainName)"
            Password          = $Password
        }
    }

    New-LocalUser `
        -Name $UserName `
        -Password $securePassword `
        -FullName $UserName `
        -Description "由 Add-DomainOrLocalUser.zh-CN.ps1 生成"

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
        Write-Host "此脚本必须以管理员身份运行。请以管理员身份打开 PowerShell 后重新运行。" -ForegroundColor Red
        Wait-BeforeExit
        exit 1
    }

    Write-Host "正在检测当前环境..." -ForegroundColor Cyan
    $environment = Get-EnvironmentInfo

    Write-Host "检测到目标环境：$($environment.TargetType)" -ForegroundColor Green
    if ($environment.IsDomainJoined) {
        Write-Host "检测到域：$($environment.DomainName)" -ForegroundColor Green
        Import-ActiveDirectoryModule
    }
    else {
        Write-Host "当前计算机未加入域，将创建本地用户。" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "请选择操作："
    Write-Host "1. 创建指定用户名和密码的用户"
    Write-Host "2. 创建随机用户"

    do {
        $choice = Read-Host "请输入 1 或 2"
        if ($choice -notin @("1", "2")) {
            Write-Host "选项无效，请输入 1 或 2。" -ForegroundColor Yellow
        }
    } while ($choice -notin @("1", "2"))

    if ($choice -eq "1") {
        do {
            $userName = Read-NonEmptyValue -Prompt "请输入用户名，不要包含 @域名 部分"
            if ($userName -match "@") {
                Write-Host "请不要包含 @域名 部分，只输入用户名。" -ForegroundColor Yellow
            }
        } while ($userName -match "@")

        $useCustomPassword = Read-YesNo -Prompt "是否要指定密码"
        if ($useCustomPassword) {
            $password = Read-NonEmptyValue -Prompt "请输入密码，请确保符合密码策略"
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
    Write-Host "用户创建成功。" -ForegroundColor Green
    Write-Host "生成的用户信息如下：" -ForegroundColor Cyan
    $createdUser | Format-List
    Wait-BeforeExit
}
catch {
    Write-Host ""
    Write-Host "用户创建失败。" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "常见原因：" -ForegroundColor Yellow
    Write-Host "- 密码不符合域或本地密码策略。"
    Write-Host "- 用户名已存在。"
    Write-Host "- 当前计算机未安装 ActiveDirectory 模块。"
    Write-Host "- PowerShell 未以管理员身份运行。"
    Wait-BeforeExit
    exit 1
}
