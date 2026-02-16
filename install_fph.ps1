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

    Write-Info "Ñêà÷èâàåì Python 3.13 èç $url"
    Invoke-WebRequest -Uri $url -OutFile $tempPath

    Write-Info "Óñòàíàâëèâàåì Python..."
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
        Write-ErrMsg "Íå óäàëîñü ñêà÷àòü Git. Íåèçâåñòíàÿ àðõèòåêòóðà $env:PROCESSOR_ARCHITECTURE."
    }

    $headers = @{
        "User-Agent" = "FunPayHub Installer"
        "Access" = "application/vnd.github+json"
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -TimeoutSec 10 -Headers $headers
    $asset = $release.assets | Where-Object {$_.name -match $pattern -and $_.name -notmatch "Portable" } | Select-Object -First 1

    if (-not $asset) {
        throw "Íå óäàëîñü íàéòè óñòàíîâùèê Git, ïîäõîäÿùèé ïîä âàøó ñèñòåìó :("
    }

    Write-Info "Íàéäåí ïîäõîäÿùèé ðåëèç!"
    echo $asset

    $tempPath = Join-Path $env:TEMP $asset.name

    Write-Info "Çàãðóæàåì Git..."
    $headers = @{"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"}
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -Headers $headers -TimeoutSec 10

    Write-Info "Óñòàíàâëèâàåì Git..."
    Start-Process -FilePath $tempPath -ArgumentList "/SILENT /NORESTART /NOCANCEL /SP-" -Wait
    Remove-Item $tempPath -Force
    Update-PATH
}


function Select-InstallDir {
    $selected = $null

    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Âûáåðèòå ïàïêó, êóäà õîòèòå óñòàíîâèòü FunPay Hub."
        $dialog.ShowNewFolderButton = $true
        $dialog.SelectedPath = [Environment]::GetFolderPath("Desktop")
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.SelectedPath
        }
    } catch {}

    if (-not $selected) {
        throw "Äèðåêòîðèÿ óñòàíîâêè íå âûáðàíà."
    }

    return $selected
}


function Clone-Hub {
    param(
        [array]$git,
        [string]$path
    )

    Write-Info "Çàãðóæàþ FunPay Hub..."
    & $git clone "https://github.com/funpayhub/funpayhub" $path
    if ($LASTEXITCODE -ne 0) {
        throw "Íå óäàëîñü ñêëîíèðîâàòü FunPay Hub."
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

    Write-Info "Ñîçäàþ âèðòóàëüíîå îêðóæåíèå..."
    & $python $python_args
    $python = ".venv\Scripts\python.exe"

    & $python -m pip --version *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Óñòàíàâëèâàþ pip..."
        & $python -m ensurepip --upgrade
    }

    if (-not (Test-Path "requirements.txt")) {
        Write-WarnMsg "requirements.txt íå íàéäåí. Ïðîïóñêàþ óñòàíîâêó çàâèñèìîñòåé."
    }
    else {
        Write-Info "Óñòàíàâëèâàþò çàâèñèìîñòè..."
        & $python -m pip install -r requirements.txt
    }

    Write-Info "Çàïóñêàþ bootstrap..."
    & $python bootstrap.py
    if ($LASTEXITCODE -ne 0) {
        throw "Íå óäàëîñü âûïîëíèòü bootstrap."
    }

    Write-Info "Íàñòðîèì êà êîíôèã..."
    & $python releases\current\launcher.py --setup-config
    if ($LASTEXITCODE -ne 0) {
        throw "Íå óäàëîñü âûïîëíèòü ïåðâóè÷íóþ íàñòðîéêó."
    }

    Write-Info "Ñîçäàþ ñêðèïò äëÿ çàïóñêà..."
    $bat = "cmd.exe /k `".venv\Scripts\python.exe releases\current\launcher.py`""
    $encoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) "run_funpayhub.bat"), $bat, $encoding)
}


# Ñêðèïò
chcp 65001

$python = Get-PythonCommand
if (-not $python) {
    Write-Info "Python íå íàéäåí. Íà÷èíàåì óñòàíîâêó."
    Install-Python
    $python = Get-PythonCommand
    if (-not $python) {
        throw "Ïîñëå óñòàíîâêè Python òàê è íå áûë îáíàðóæåí."
    }
}
Write-Info "Python îáíàðóæåí."
$python_args = $python[1]
$python = $python[0]


$git = Get-GitCommand
if (-not $git) {
    Write-Info "Git íå íàéäåí. Íà÷èíàåì óñòàíîâêó."
    Install-Git
    $git = Get-GitCommand
    if (-not $git) {
        throw "Ïîñëå óñòàíîâêè Git òàê è íå áûë îáíàðóæåí."
    }
}
Write-Info "Git îáíàðóæåí."


Write-Info "Âûáåðèòå äèðåêòîðèþ, êóäà õîòèòå óñòàíîâèòü FunPay Hub."
$install_dir = Select-InstallDir
if (-not $install_dir) {
    throw "Äèðåêòîðèÿ óñòàíîâêè íå áûëà âûáðàíà."
}

Write-Info "Íà÷èíàåì ïðîöåññ óñòàíîâêè FunPay Hub â $install_dir."
Clone-Hub -git $git -path $install_dir
Bootstrap -python $python -python_args $python_args -path $install_dir

Write-Info "FunPay Hub óñïåøíî óñòàíîâëåí. Äëÿ çàïóñêà èñïîëüçóéòå ôàéë run_funpayhub.bat."

$answer = Read-Host "Õîòèòå çàïóñòèòü FunPay Hub ñåé÷àñ? [Y/n]"
if ($answer -match "^[YyÄä]" -or (-not $answer)) {
    Start-Process cmd.exe -ArgumentList "/k", "run_funpayhub.bat"
} else {
    Write-Info "Íó è áîëüíî íàäî áûëî :("
}
exit 0