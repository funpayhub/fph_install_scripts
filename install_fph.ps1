#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 
function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}


function Write-WarnMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}


function Write-ErrMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Update-PATH {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "Machine")
}


function Get-PythonCommand {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $out = & py -3.13 -V 2>$null
            if ($LASTEXITCODE -eq 0 -and $out -match "Python 3\.13") {
                return @("py", @("-3.13"))
            }
        } catch {}
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"),
        (Join-Path $env:ProgramFiles "Python313\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python313\python.exe")
    )

    foreach ($canditate in $candidates) {
        if (Test-Path $canditate) {
            return @(($canditate), @())
        }
    }
 
    return $null
}


function Get-GitCommand {
    return (Get-Command git -ErrorAction SilentlyContinue)

}


function Install-Python {
    $arch = ($env:PROCESSOR_ARCHITECTURE).ToLower()
    $installer = "python-3.13.12-$arch.exe"
    $url = "https://python.org/ftp/python/3.13.12/$installer"
    $tempPath = Join-Path $env:TEMP $installer

    Write-Info "Скачиваем Python 3.13 из $url"
    Invoke-WebRequest -Uri $url -OutFile $tempPath
    
    Write-Info "Устанавливаем Python..."
    $args = "/passive InstallAllUsers=0 PrependPath=1"
    Start-Process -FilePath $tempPath -ArgumentList $args -Wait
    Remove-Item $tempPath -Force
    Update-PATH
}


function Install-Git {
    $pattern = $null
    if (($env:PROCESSOR_ARCHITECTURE).ToLower() -eq "amd64") {
        $pattern = "64-bit.exe"
    }
    elseif (($env:PROCESSOR_ARCHITECTURE).ToLower() -eq "arm64") {
        $pattern = "arm64.exe"
    }
    else {
        Write-ErrMsg "Не удалось скачать Git. Неизвестная архитектура $env:PROCESSOR_ARCHITECTURE."
    }

    $headers = @{ 
        "User-Agent" = "FunPayHub Installer"
        "Access" = "application/vnd.github+json" 
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -TimeoutSec 10 -Headers $headers
    $asset = $release.assets | Where-Object {$_.name -match $pattern -and $_.name -notmatch "Portable" } | Select-Object -First 1
    
    if (-not $asset) {
        throw "Не удалось найти установщик Git, подходящий под вашу систему :("
    }

    Write-Info "Найден подходящий релиз!"
    echo $asset

    $tempPath = Join-Path $env:TEMP $asset.name

    Write-Info "Загружаем Git..."
    $headers = @{"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"}
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -Headers $headers -TimeoutSec 10

    Write-Info "Устанавливаем Git..."
    Start-Process -FilePath $tempPath -ArgumentList "/SILENT /NORESTART /NOCANCEL /SP-" -Wait
    Remove-Item $tempPath -Force
    Update-PATH
}


function Select-InstallDir {
    $selected = $null
 
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Выберите папку, куда хотите установить FunPay Hub."
        $dialog.ShowNewFolderButton = $true
        $dialog.SelectedPath = [Environment]::GetFolderPath("Desktop")
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.SelectedPath
        }
    } catch {}
 
    if (-not $selected) {
        throw "Директория установки не выбрана."
    }
 
    return $selected
}


function Clone-Hub {
    param(
        [array]$git,
        [string]$path
    )

    Write-Info "Загружаю FunPay Hub..."
    & $git clone "https://github.com/funpayhub/funpayhub" $path
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось склонировать FunPay Hub."
    }
}


function Bootstrap {
    param(
        [string]$python,
        [array]$python_args,
        [string]$path
    )
    Push-Location $path
    $python_args = $python_args + @("-m", "venv", ".venv")

    Write-Info "Создаю виртуальное окружение..."
    & $python $python_args
    $python = ".venv\Scripts\python.exe"

    & $python -m pip --version *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Устанавливаю pip..."
        & $python -m ensurepip --upgrade
    }

    if (-not (Test-Path "requirements.txt")) {
        Write-WarnMsg "requirements.txt не найден. Пропускаю установку зависимостей."
    }
    else {
        Write-Info "Устанавливают зависимости..."
        & $python -m pip install -r requirements.txt
    }

    Write-Info "Запускаю bootstrap..."
    & $python bootstrap.py
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось выполнить bootstrap."
    }

    Write-Info "Настроим ка конфиг..."
    & $python releases\current\launcher.py --setup-config
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось выполнить первуичную настройку."
    }

    Write-Info "Создаю скрипт для запуска..."
    $bat = "cmd.exe /k `".venv\Scripts\python.exe releases\current\launcher.py`""
    $encoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) "run_funpayhub.bat"), $bat, $encoding)
}


# Скрипт
chcp 65001

$python = Get-PythonCommand
if (-not $python) {
    Write-Info "Python не найден. Начинаем установку."
    Install-Python
    $python = Get-PythonCommand
    if (-not $python) {
        throw "После установки Python так и не был обнаружен."
    }
}
Write-Info "Python обнаружен."
$python_args = $python[1]
$python = $python[0]


$git = Get-GitCommand
if (-not $git) {
    Write-Info "Git не найден. Начинаем установку."
    Install-Git
    $git = Get-GitCommand
    if (-not $git) {
        throw "После установки Git так и не был обнаружен."
    }
}
Write-Info "Git обнаружен."


Write-Info "Выберите директорию, куда хотите установить FunPay Hub."
$install_dir = Select-InstallDir
if (-not $install_dir) {
    throw "Директория установки не была выбрана."
}

Write-Info "Начинаем процесс установки FunPay Hub в $install_dir."
Clone-Hub -git $git -path $install_dir
Bootstrap -python $python -python_args $python_args -path $install_dir

Write-Info "FunPay Hub успешно установлен. Для запуска используйте файл run_funpayhub.bat."

$answer = Read-Host "Хотите запустить FunPay Hub сейчас? [Y/n]"
if ($answer -match "^[YyДд]" -or (-not $answer)) {
    Start-Process cmd.exe -ArgumentList "/k", "run_funpayhub.bat"
} else {
    Write-Info "Ну и больно надо было :("
}
exit 0
