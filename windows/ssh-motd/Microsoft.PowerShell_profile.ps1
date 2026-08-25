# ============================================================
# MOOLO.NET - PowerShell 7 SSH MOTD
# Windows Server 2022
# ============================================================

# 仅交互式登录(SSH PTY 会话 / 本地控制台)时显示 MOTD。
# SFTP / SCP / rsync / git / 远程执行命令等非交互会话直接跳过,
# 避免横幅输出污染传输协议流导致 "Received message too long" 等异常。
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return }

Clear-Host

# ------------------------------------------------------------
# 基础信息
# ------------------------------------------------------------

$ComputerInfo = Get-CimInstance Win32_ComputerSystem
$OSInfo       = Get-CimInstance Win32_OperatingSystem
$CPUInfo      = Get-CimInstance Win32_Processor | Select-Object -First 1

$ComputerName = $env:COMPUTERNAME
$UserName     = "$env:USERDOMAIN\$env:USERNAME"
$Domain       = $ComputerInfo.Domain

$OS           = $OSInfo.Caption
$OSVersion    = $OSInfo.Version
$Architecture = $OSInfo.OSArchitecture
$PSVersion    = $PSVersionTable.PSVersion.ToString()

# ------------------------------------------------------------
# 系统运行时间
# ------------------------------------------------------------

$Uptime = (Get-Date) - $OSInfo.LastBootUpTime

$UptimeText = "{0}天 {1}小时 {2}分钟" -f `
    [int]$Uptime.TotalDays,
    $Uptime.Hours,
    $Uptime.Minutes

# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

$CPUUsage = [math]::Round(
    $CPUInfo.LoadPercentage,
    1
)

$CPUName = $CPUInfo.Name.Trim()

# ------------------------------------------------------------
# 内存
# ------------------------------------------------------------

$TotalMemory = [math]::Round(
    $OSInfo.TotalVisibleMemorySize / 1MB,
    2
)

$FreeMemory = [math]::Round(
    $OSInfo.FreePhysicalMemory / 1MB,
    2
)

$UsedMemory = [math]::Round(
    $TotalMemory - $FreeMemory,
    2
)

$MemoryUsage = [math]::Round(
    ($UsedMemory / $TotalMemory) * 100,
    1
)

# ------------------------------------------------------------
# IPv4 地址
# ------------------------------------------------------------

$IPv4 = Get-NetIPAddress `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object -ExpandProperty IPAddress

$IPv4Text = $IPv4 -join ", "

# ------------------------------------------------------------
# SSH 来源 IP
# ------------------------------------------------------------

if ($env:SSH_CLIENT) {
    $SSHSourceIP = ($env:SSH_CLIENT -split "\s+")[0]
}
else {
    $SSHSourceIP = "本机"
}

# ------------------------------------------------------------
# 当前时间
# ------------------------------------------------------------

$CurrentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ------------------------------------------------------------
# 磁盘信息
# ------------------------------------------------------------

$DiskInfo = Get-CimInstance Win32_LogicalDisk `
    -Filter "DriveType=3" |
    ForEach-Object {

        $Size = [math]::Round(
            $_.Size / 1GB,
            1
        )

        $Free = [math]::Round(
            $_.FreeSpace / 1GB,
            1
        )

        $Used = [math]::Round(
            $Size - $Free,
            1
        )

        if ($Size -gt 0) {
            $Percent = [math]::Round(
                ($Used / $Size) * 100,
                0
            )
        }
        else {
            $Percent = 0
        }

        "{0}  {1} / {2} GB  ({3}%)" -f `
            $_.DeviceID,
            $Used,
            $Size,
            $Percent
    }

# ============================================================
# Windows Logo
# ============================================================

$Logo = @(
""
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
""
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
"        ██████████████    ██████████████"
""
)

# ============================================================
# 系统信息
# ============================================================

$Info = @(
    "操作系统    : $OS"
    "系统版本    : $OSVersion"
    "系统架构    : $Architecture"
    "计算机名    : $ComputerName"
    "域          : $Domain"
    "当前用户    : $UserName"
    "PowerShell  : $PSVersion"
    "运行时间    : $UptimeText"
    "CPU 使用率  : $CPUUsage%"
    "CPU 型号    : $CPUName"
    "内存使用    : $UsedMemory GB / $TotalMemory GB"
    "内存占用    : $MemoryUsage%"
    "IPv4 地址   : $IPv4Text"
    "SSH 来源    : $SSHSourceIP"
    "当前时间    : $CurrentTime"
)

# ============================================================
# 输出 Logo + 系统信息
# ============================================================

$MaxLines = [Math]::Max(
    $Logo.Count,
    $Info.Count
)

Write-Host ""

for ($i = 0; $i -lt $MaxLines; $i++) {

    if ($i -lt $Logo.Count) {
        $Left = $Logo[$i]
    }
    else {
        $Left = ""
    }

    if ($i -lt $Info.Count) {
        $Right = $Info[$i]
    }
    else {
        $Right = ""
    }

    Write-Host ("{0,-42}  {1}" -f $Left, $Right)
}

# ============================================================
# 磁盘空间
# ============================================================

Write-Host ""
Write-Host "磁盘空间"
Write-Host "────────────────────────────────────────────────────────────"

foreach ($Disk in $DiskInfo) {
    Write-Host "  $Disk"
}

# ============================================================
# Footer
# ============================================================

Write-Host ""
Write-Host "────────────────────────────────────────────────────────────"
Write-Host "  欢迎登录 $ComputerName"
Write-Host "  MOOLO.NET 域控制器"
Write-Host "────────────────────────────────────────────────────────────"
Write-Host ""
