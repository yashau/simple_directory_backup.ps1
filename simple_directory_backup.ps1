[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Remove-TempFiles {
    Get-ChildItem -Path $ScriptDirectory -Filter *.7z -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

$LogFile = "$ScriptDirectory\backup.log"
function Write-LogAndOutput {
    param (
        [string]$Message,
        [bool]$OutputToConsole = $true
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $LogMessage = "$Timestamp - $Message"

    if (-not (Test-Path -Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    Add-Content -Path $LogFile -Value $LogMessage
    
    if ($OutputToConsole) {
        Write-Output "$Timestamp - $Message"
    }
}

function Import-Vars {
    $EnvFilePath = Join-Path -Path $ScriptDirectory -ChildPath ".env"
    if (Test-Path -Path $EnvFilePath) {
        $dotenvContent = Get-Content -Path $EnvFilePath
        foreach ($Line in $dotenvContent) {
            if ($Line -match "^\s*#") { continue }
            $Parts = $Line -split "="
            if ($Parts.Length -eq 2) {
                $VariableName = $Parts[0].Trim()
                $VariableValue = $Parts[1].Trim().Trim('"')
                [System.Environment]::SetEnvironmentVariable($VariableName, $VariableValue, "Process")
            }
        }
    } else {
        $ErrorMessage = "Environment file .env not found at $EnvFilePath"
        Write-LogAndOutput "Error: $ErrorMessage"
        exit 1
    }
}

function Install-VCRuntime {
    try {
        $InstallerUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $RuntimePath = Join-Path $env:SystemRoot "system32\VCRUNTIME140_1.dll"
        if (-not (Test-Path $RuntimePath)) {
            Write-LogAndOutput "Visual C++ Runtime not found. Downloading and installing..."
            $VCInstaller = [System.IO.Path]::GetTempFileName() + ".exe"
            try {
                Invoke-WebRequest -Uri $InstallerUrl -OutFile $VCInstaller
                Start-Process -FilePath $VCInstaller -ArgumentList "/install", "/quiet", "/norestart" -Wait
                Write-LogAndOutput "Visual C++ Runtime installed successfully."
            }
            finally {
                Remove-Item $VCInstaller -Force
            }
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-LogAndOutput "Failed to download and install Visual C++ Runtime: $ErrorMessage"
        Send-TelegramMessage -Message "[$($env:JOB_NAME)] Failed to install Visual C++ Runtime: $ErrorMessage"
        exit 1
    }
}

function Get-ShadowRun {
    if ($env:SHADOWRUN_PATH) {
        $script:ShadowRunPath = $env:SHADOWRUN_PATH
    } else {
        $script:ShadowRunPath = Join-Path -Path $ScriptDirectory -ChildPath "ShadowRun.exe"
        try {
            if (-not (Test-Path -Path $script:ShadowRunPath)) {
                Write-LogAndOutput "ShadowRun.exe not found. Downloading from https://github.com/albertony/vss/..."
                $ShadowRunUrl = "https://github.com/albertony/vss/releases/download/v0.5.4/ShadowRun.exe"
                Invoke-WebRequest -Uri $ShadowRunUrl -OutFile $script:ShadowRunPath
                Write-LogAndOutput "ShadowRun.exe downloaded successfully."
            }
        } catch {
            $ErrorMessage = $_.Exception.Message
            Write-LogAndOutput "Failed to download ShadowRun.exe: $ErrorMessage"
            Send-TelegramMessage -Message "[$($env:JOB_NAME)] Failed to download ShadowRun.exe: $ErrorMessage"
            exit 1
        }
    }
}

function Install-7ZipZS {
    try {
        $script:7ZipZSPath = (Get-ItemProperty -Path 'HKLM:SOFTWARE\7-Zip-Zstandard' -Name 'Path').Path + "7z.exe"
        if (-not (Test-Path -Path $script:7ZipZSPath)) {
            Write-LogAndOutput "7-Zip ZS not found. Downloading and installing..."
            $7ZUrl = "https://github.com/mcmilk/7-Zip-zstd/releases/download/v22.01-v1.5.5-R3/7z22.01-zstd-x64.exe"
            $7ZInstaller = "$env:TEMP\7zInstaller.exe"
            Invoke-WebRequest -Uri $7ZUrl -OutFile $7ZInstaller
            Start-Process -FilePath $7ZInstaller -ArgumentList "/S" -Wait
            Remove-Item -Path $7ZInstaller -Force
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-LogAndOutput "Failed to download and install 7-Zip ZS: $ErrorMessage"
        Send-TelegramMessage -Message "[$($env:JOB_NAME)] Failed to download and install 7-Zip ZS: $ErrorMessage"
        exit 1
    }
}

function Get-Rclone {
    if ($env:RCLONE_PATH) {
        $script:RclonePath = $env:RCLONE_PATH
    } else {
        $script:RclonePath = Join-Path -Path $ScriptDirectory -ChildPath "rclone.exe"
        try {
            if (-not (Test-Path -Path $script:RclonePath)) {
                Write-LogAndOutput "Downloading rclone from https://downloads.rclone.org/rclone-current-windows-amd64.zip..."
                $RcloneZip = Join-Path -Path $ScriptDirectory -ChildPath "rclone.zip"
                Invoke-WebRequest -Uri "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $RcloneZip -ErrorAction Stop
                Expand-Archive -Path $RcloneZip -DestinationPath $ScriptDirectory -Force
                $RcloneExtractedPath = Get-ChildItem -Path "$ScriptDirectory\rclone-*-windows-amd64" | Select-Object -ExpandProperty FullName
                Move-Item -Path $RcloneExtractedPath\rclone.exe -Destination $script:RclonePath -Force
                Remove-Item -Path $RcloneZip -Force
                Remove-Item -Path "$ScriptDirectory\rclone-*-windows-amd64" -Recurse -Force
                Write-LogAndOutput "rclone downloaded and installed successfully."
            }
        } catch {
            $ErrorMessage = $_.Exception.Message
            Write-LogAndOutput "Failed to download and install rclone: $ErrorMessage"
            Send-TelegramMessage -Message "[$($env:JOB_NAME)] Failed to download and install rclone: $ErrorMessage"
            exit 1
        }
    }
}

function Send-TelegramMessage {
    param (
        [string]$Message
    )
    $Url = "https://api.telegram.org/bot$($env:BOT_TOKEN)/sendMessage"
    $Params = @{
        chat_id = $env:CHAT_ID
        text    = $Message
    }
    Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json" -Body ($Params | ConvertTo-Json)
    Write-LogAndOutput "Telegram message sent: $Message"
}

function Get-HumanReadableFileSize {
    param (
        [string]$FilePath
    )
    $FileInfo = Get-Item $FilePath
    $SizeInBytes = $FileInfo.Length
    $Sizes = "B", "KB", "MB", "GB", "TB"
    $Index = 0
    while ($SizeInBytes -ge 1024 -and $Index -lt $Sizes.Length) {
        $SizeInBytes = $SizeInBytes / 1024.0
        $Index++
    }
    "{0:N2} {1}" -f $SizeInBytes, $Sizes[$Index]
}

function Compress-Directory {
    param (
        [string]$Directory
    )
    $DriveLetter = Split-Path -Path $Directory -Qualifier
    $RelativePath = $Directory.Substring($Directory.IndexOf("\") + 1)
    $DirName = Split-Path -Path $Directory -Leaf
    $CompressedFileName = "$DirName-$(Get-Date -Format 'yyyy_MM_dd-HHmm')-zstd.7z"
    $CompressedPath = Join-Path -Path $ScriptDirectory -ChildPath $CompressedFileName
    Write-LogAndOutput "Creating VSS Snapshot and compressing $DirName..."
    & $script:ShadowRunPath -env -mount -exec="$script:7ZipZSPath" $DriveLetter -- a -t7z -m0=zstd -mx=1 $CompressedPath "%SHADOW_DRIVE_1%\$RelativePath"
    if ($LASTEXITCODE -ne 0) {
        Write-LogAndOutput "Compressing directory $DirName failed. See log file for details."
        Send-TelegramMessage "[$($env:JOB_NAME)] Compressing directory $DirName failed. See log file for details."
        exit 1
    }
    $Size = Get-HumanReadableFileSize -FilePath $CompressedPath
    Write-LogAndOutput "Compressed $DirName successfully. File size is $Size."
    $script:FilesToUpload[$DirName] = $CompressedPath
}

function Move-ToS3 {
    param (
        [string]$FilePath,
        [string]$Name
    )
    $RcloneConfPath = Join-Path -Path $ScriptDirectory -ChildPath "rclone.conf"
    $RcloneConfContent = @(
        "[remote]",
        "type = s3",
        "provider = $($env:PROVIDER)",
        "env_auth = true",
        "access_key_id = $($env:ACCESS_KEY)",
        "secret_access_key = $($env:SECRET_KEY)",
        "endpoint = $($env:ENDPOINT)"
    )
    $RcloneConfContent | Set-Content -Path $RcloneConfPath -Force -ErrorAction Stop
    $File = Split-Path -Path $FilePath -Leaf
    $RcloneDest = "remote:$($env:BUCKET_NAME)/$File"

    Write-LogAndOutput "Starting upload of $File to $($env:PROVIDER)."
    & $script:RclonePath moveto --config $RcloneConfPath $FilePath $RcloneDest --progress --s3-no-check-bucket 2>> $LogFile
    if ($LASTEXITCODE -eq 0) {
        Write-LogAndOutput "Uploading $File to $($env:PROVIDER) succeeded."
    } else {
        Write-LogAndOutput "Upload to $($env:PROVIDER) failed for directory $Name. See log file for details."
        Send-TelegramMessage "[$($env:JOB_NAME)] Upload to $($env:PROVIDER) failed for directory $Name. See log file for details."
        exit 1
    }
}

try {
    Write-LogAndOutput "Script execution started..."
    Import-Vars
    Write-LogAndOutput "Checking for dependencies..."
    Install-VCRuntime
    Install-7ZipZS
    Get-ShadowRun
    Get-Rclone
    Write-LogAndOutput "Cleaning working directory..."
    Remove-TempFiles
    Write-LogAndOutput "Starting backup job..."

    $Directories = Get-ChildItem Env: | Where-Object { $_.Name -match '^DIR_\d+$' } | ForEach-Object { $_.Value }
    $script:FilesToUpload = @{}
    foreach ($Directory in $Directories) {
        Compress-Directory -Directory $Directory
    }

    foreach ($Name in $script:FilesToUpload.Keys) {
        $FilePath = $script:FilesToUpload[$Name]
        Move-ToS3 -File $FilePath -Name $Name
    }

    Remove-TempFiles
    Write-LogAndOutput -Message "Script execution completed."
    Send-TelegramMessage -Message "[$($env:JOB_NAME)] backup job completed successfully."
} catch {
    $ErrorMessage = $_.Exception.Message
    Write-LogAndOutput "Error during script execution: $ErrorMessage"
    Send-TelegramMessage -Message "[$($env:JOB_NAME)] Error during script execution: $ErrorMessage"
    exit 1
}