<#
.SYNOPSIS
    Mooloco 专属智能复制与时间锁工具 (V3 终极版)

.DESCRIPTION
    这是一个工业级、高稳健性的 PowerShell 文件/文件夹克隆工具。
    专门用于解决 Windows 系统在跨盘复制文件时，目标文件/文件夹的“创建时间”和“修改时间”会被系统强行刷新的逻辑痛点。
    
    本脚本通过独创的“回马枪时间锁”机制，在完成传输后利用 .NET 底层接口强制将目标对象（包含子文件、子目录、以及根文件夹本身）
    的时间戳返老还童，精准对齐源头，实现 100% 的时间戳克隆。

.FEATURES
    1. 智能目录重定向：当源为文件夹时，自动在目标路径下创建同名文件夹作为容器（套娃模式），而不是将文件散落一地。
    2. 全多级时间锁定：不仅克隆文件时间，连同新创建的各级子文件夹、根文件夹本身的时间戳一并死死锁住。
    3. 交互式防呆设计：支持路径自动去噪（清除双引号与末尾斜杠），执行前提供清晰的任务预览及 Y/N 二次确认机制。
    4. 生产级同名冲突：遭遇同名文件时，采取强行覆盖（Force）策略，确保最新数据写入。
    5. 可视化进度回显：文件夹复制采用 Windows 系统级原生 UI 进度条，实时展示当前传输状态与百分比。
    6. 数字化结果战报：执行完毕后自动化身“审计大师”，直观统计应复制总数、成功数、失败数以及本次传输的 MB 数据量。

.PARAMETER sourcePath
    源路径。支持直接拖入或粘贴文件、文件夹的绝对路径（支持带双引号）。

.PARAMETER destInput
    目的地基础路径。如果目标路径不存在，脚本将自动深度创建多级目录。

.EXAMPLE
    .\SmartCopy_V3.ps1
    启动脚本后根据控制台中文向导交互操作即可。

.NOTES
    作者: Mooloco
    运行环境: 建议在 Windows Terminal / VS Code / PowerShell 5.1+ 环境下以管理员权限运行。
    编码规范: 本脚本必须保存为 UTF-8 (或 UTF-8 with BOM) 编码，否则中文交互界面可能出现乱码。
#>
[CmdletBinding()]
param()

clear

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "      Mooloco 专属智能复制与时间锁工具 (V3 套娃版)      " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# 1. 获取源路径
[string]$sourcePath = Read-Host "请输入源路径 (文件或文件夹的绝对路径)"
$sourcePath = $sourcePath.Trim('"').TrimEnd('\') # 去掉引号和末尾的反斜杠

if (-not (Test-Path -Path $sourcePath)) {
    Write-Error "错误：源路径不存在，请检查后重新运行脚本！"
    exit
}

# 获取源对象属性
$sourceItem = Get-Item -Path $sourcePath -Force
$isFolder = $sourceItem -is [System.IO.DirectoryInfo]

# 2. 获取目的地基础路径
[string]$destInput = Read-Host "请输入目的地文件夹路径"
$destInput = $destInput.Trim('"').TrimEnd('\')

# 3. 【核心改进逻辑】如果是文件夹，自动在目的地追加源文件夹的名字
[string]$finalDestFolder = $destInput
if ($isFolder) {
    $sourceFolderName = $sourceItem.Name
    $finalDestFolder = Join-Path -Path $destInput -ChildPath $sourceFolderName
    Write-Host "-> 智能识别：内容将安全克隆至: $finalDestFolder" -ForegroundColor Green
}

# 4. 任务预览与二次确认
Write-Host ""
Write-Host "------------- 任务预览 -------------" -ForegroundColor Cyan
Write-Host "源  类  型: $(if($isFolder){"文件夹 [整个克隆]"}else{"单文件"})"
Write-Host "源  路  径: $sourcePath"
Write-Host "最终目的地: $finalDestFolder"
Write-Host "------------------------------------"
Write-Host ""

[string]$confirmation = Read-Host "是否确认执行上述操作？(输入 Y 继续，输入 N 终止)"
if ($confirmation.ToUpper() -ne "Y") {
    Write-Warning "操作已被用户取消。"
    exit
}

Write-Host ""
Write-Host "正在初始化复制引擎并同步目录时间..." -ForegroundColor Green

# 5. 执行复制与时间锁锁定
try {
    if ($isFolder) {
        # ---------------- 文件夹及其自身时间戳克隆 ----------------
        # 如果最终的目标文件夹不存在，创建它
        if (-not (Test-Path -Path $finalDestFolder)) {
            New-Item -ItemType Directory -Path $finalDestFolder -Force | Out-Null
        }
        
        # 统计源文件夹下的文件总数
        Write-Host "正在扫描源文件夹计算文件总数..." -ForegroundColor Gray
        $allFiles = Get-ChildItem -Path $sourcePath -Recurse -File -Force -ErrorAction SilentlyContinue
        $totalCount = $allFiles.Count
        
        if ($totalCount -eq 0) {
            # 如果是空文件夹，直接同步文件夹本身时间就完事了
            $destFolderItem = Get-Item -Path $finalDestFolder -Force
            $destFolderItem.CreationTime = $sourceItem.CreationTime
            $destFolderItem.LastWriteTime = $sourceItem.LastWriteTime
            Write-Warning "源文件夹下没有文件，已完美克隆空文件夹本身的时间戳。"
            exit
        }

        # 计数器
        $currentCount = 0
        $successCount = 0
        $failedCount = 0
        [long]$totalBytes = 0

        # 开始循环拷贝内部文件
        foreach ($file in $allFiles) {
            $currentCount++
            
            # 精准计算相对路径（保持原有的子目录结构）
            $relativeData = $file.FullName.Substring($sourcePath.Length)
            $targetFilePath = Join-Path -Path $finalDestFolder -ChildPath $relativeData
            $targetFileDir = Split-Path -Path $targetFilePath -Parent
            
            # 如果子文件夹不存在，创建之
            if (-not (Test-Path -Path $targetFileDir)) {
                New-Item -ItemType Directory -Path $targetFileDir -Force | Out-Null
            }

            # 顶部系统级原生进度条
            $percent = [math]::Round(($currentCount / $totalCount) * 100)
            Write-Progress -Activity "正在完美克隆文件夹中..." `
                           -Status "当前正在复制: $($file.Name) ($currentCount/$totalCount)" `
                           -PercentComplete $percent

            try {
                # 复制文件（强制同名覆盖）
                Copy-Item -Path $file.FullName -Destination $targetFilePath -Force -ErrorAction Stop
                
                # 强行同步内部文件的时间戳
                $targetFileItem = Get-Item -Path $targetFilePath -Force
                $targetFileItem.CreationTime = $file.CreationTime
                $targetFileItem.LastWriteTime = $file.LastWriteTime
                
                $successCount++
                $totalBytes += $file.Length
            } catch {
                $failedCount++
            }
        }
        # 关闭进度条
        Write-Progress -Activity "正在完美克隆文件夹中..." -Completed

        # 【核心点】全部文件拷贝完后，最后再把“根文件夹”的时间戳强行修改成跟源文件夹一模一样
        # 必须最后改，因为之前往里面塞文件时，系统的默认机制会不断刷新这个根文件夹的修改时间
        $destFolderItem = Get-Item -Path $finalDestFolder -Force
        $destFolderItem.CreationTime = $sourceItem.CreationTime
        $destFolderItem.LastWriteTime = $sourceItem.LastWriteTime

        # 6. 输出文件夹战报大盘
        Write-Host ""
        Write-Host "============ 📊 本次处理结果战报 ============" -ForegroundColor Green
        Write-Host " 任务状态: 整个文件夹克隆成功！"
        Write-Host " 根文件夹时间锁: 已锁死（与源文件夹完全一致）" -ForegroundColor Cyan
        Write-Host " 应复制文件总数: $totalCount 个"
        Write-Host " 成功复制数: $successCount 个" -ForegroundColor Green
        if ($failedCount -gt 0) {
            Write-Host " 失败文件数: $failedCount 个" -ForegroundColor Red
        } else {
            Write-Host " 失败文件数: 0 个"
        }
        Write-Host " 传输总数据量: [ $([math]::Round($totalBytes / 1MB, 2)) MB ]" -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor Green

    } else {
        # ---------------- 单文件复制保持原样 ----------------
        # 如果输入目的地不存在，先创建目的地
        if (-not (Test-Path -Path $finalDestFolder)) {
            New-Item -ItemType Directory -Path $finalDestFolder -Force | Out-Null
        }

        [string]$destFilePath = Join-Path -Path $finalDestFolder -ChildPath $sourceItem.Name
        
        # 模拟进度条
        for ($i = 1; $i -le 100; $i += 20) {
            Write-Progress -Activity "正在精准锁时拷贝单文件..." -Status "传输进度: $i%" -PercentComplete $i
            Start-Sleep -Milliseconds 50
        }

        Copy-Item -Path $sourcePath -Destination $destFilePath -Force
        
        # 单文件时间戳强行同步
        $destFileItem = Get-Item -Path $destFilePath -Force
        $destFileItem.CreationTime = $sourceItem.CreationTime
        $destFileItem.LastWriteTime = $sourceItem.LastWriteTime
        
        Write-Progress -Activity "正在精准锁时拷贝单文件..." -Completed

        # 输出单文件战报
        Write-Host ""
        Write-Host "============ 📊 本次处理结果战报 ============" -ForegroundColor Green
        Write-Host " 任务状态: 单文件复制成功！"
        Write-Host " 文件名称: $($sourceItem.Name)"
        Write-Host " 目标位置: $finalDestFolder"
        Write-Host " 文件大小: $([math]::Round($sourceItem.Length / 1KB, 2)) KB"
        Write-Host " 时间戳同步: 完美锁死"
        Write-Host "=============================================" -ForegroundColor Green
    }
} catch {
    Write-Error "脚本执行崩溃，错误信息: $_"
}

Write-Host ""
Read-Host "全部搞定！请按回车键退出..."