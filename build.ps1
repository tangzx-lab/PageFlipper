[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$Install
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $root "app\src\main"
$build = Join-Path $root "build\manual"
$dist = Join-Path $root "dist"
$keys = Join-Path $root "keys"
$versionName = "1.0"
$versionCode = 1

function Fail([string]$message) {
    Write-Host ""
    Write-Host "BUILD FAILED: $message" -ForegroundColor Red
    exit 1
}

function Find-Sdk {
    $candidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "D:\develop\Android\Sdk"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "platform-tools\adb.exe"))) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

$sdk = Find-Sdk
if (-not $sdk) { Fail "找不到 Android SDK。请设置 ANDROID_HOME。" }

$buildTools = Get-ChildItem (Join-Path $sdk "build-tools") -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        (Test-Path (Join-Path $_.FullName "aapt2.exe")) -and
        (Test-Path (Join-Path $_.FullName "d8.bat")) -and
        (Test-Path (Join-Path $_.FullName "apksigner.bat")) -and
        (Test-Path (Join-Path $_.FullName "zipalign.exe"))
    } |
    Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } -Descending |
    Select-Object -First 1
if (-not $buildTools) { Fail "找不到完整的 Android build-tools。" }
$bt = $buildTools.FullName

$platform = Get-ChildItem (Join-Path $sdk "platforms") -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "android.jar") } |
    Sort-Object { try { [version]($_.Name -replace '^android-', '') } catch { [version]"0.0" } } -Descending |
    Select-Object -First 1
if (-not $platform) { Fail "找不到 Android platform (android.jar)。" }
$androidJar = Join-Path $platform.FullName "android.jar"

$javaHome = $env:JAVA_HOME
if (-not $javaHome) {
    $javacCmd = Get-Command javac -ErrorAction SilentlyContinue
    if ($javacCmd) { $javaHome = Split-Path -Parent (Split-Path -Parent $javacCmd.Source) }
}
if (-not $javaHome -or -not (Test-Path (Join-Path $javaHome "bin\javac.exe"))) {
    Fail "找不到 JDK。请设置 JAVA_HOME。"
}
$javac = Join-Path $javaHome "bin\javac.exe"
$java = Join-Path $javaHome "bin\java.exe"
$keytool = Join-Path $javaHome "bin\keytool.exe"

$python = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $python) { Fail "找不到 python，无法把 classes.dex 写入 APK。" }
$packageScript = Join-Path $root "tools\package_apk.py"
$keystore = Join-Path $keys "local-debug.keystore"

Write-Host "SDK:        $sdk"
Write-Host "BuildTools: $($buildTools.Name)"
Write-Host "Platform:   $($platform.Name)"
Write-Host "JDK:        $javaHome"
Write-Host ""

if ($Clean) {
    Write-Host "==> 清理构建目录" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $build, $dist, $keys | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $build "gen"), (Join-Path $build "classes"), (Join-Path $build "dex") | Out-Null

Write-Host "==> 1/5 编译资源" -ForegroundColor Cyan
$resZip = Join-Path $build "res.zip"
& (Join-Path $bt "aapt2.exe") compile --dir (Join-Path $app "res") -o $resZip
if ($LASTEXITCODE -ne 0) { Fail "aapt2 compile 失败。" }

Write-Host "==> 2/5 生成 R.java 和资源 APK" -ForegroundColor Cyan
$resourcesApk = Join-Path $build "resources.apk"
& (Join-Path $bt "aapt2.exe") link `
    -o $resourcesApk `
    -I $androidJar `
    --manifest (Join-Path $app "AndroidManifest.xml") `
    -R $resZip `
    --java (Join-Path $build "gen") `
    --min-sdk-version 26 `
    --target-sdk-version 36 `
    --version-code $versionCode `
    --version-name $versionName `
    --auto-add-overlay
if ($LASTEXITCODE -ne 0) { Fail "aapt2 link 失败。" }

Write-Host "==> 3/5 编译 Java" -ForegroundColor Cyan
$sources = @()
$sources += Get-ChildItem (Join-Path $app "java") -Recurse -Filter *.java |
    Select-Object -ExpandProperty FullName
$sources += Join-Path $build "gen\com\flipper\local\R.java"
$javacOut = & $javac -encoding UTF-8 -nowarn -Xlint:-options --release 8 -classpath $androidJar `
    -d (Join-Path $build "classes") $sources 2>&1
if ($LASTEXITCODE -ne 0) {
    $javacOut | ForEach-Object { Write-Host $_ }
    Fail "Java 编译失败。"
}

Write-Host "==> 4/5 生成 classes.dex" -ForegroundColor Cyan
$classFiles = Get-ChildItem (Join-Path $build "classes") -Recurse -Filter *.class |
    Select-Object -ExpandProperty FullName
$dexDir = Join-Path $build "dex"
Get-ChildItem $dexDir -ErrorAction SilentlyContinue | Remove-Item -Force
& (Join-Path $bt "d8.bat") --lib $androidJar --min-api 26 --output $dexDir $classFiles
if ($LASTEXITCODE -ne 0) { Fail "d8 失败。" }
$dex = Join-Path $dexDir "classes.dex"
if (-not (Test-Path $dex)) { Fail "没有生成 classes.dex。" }

Write-Host "==> 5/5 打包、对齐、签名" -ForegroundColor Cyan
$unsigned = Join-Path $build "unsigned.apk"
$aligned = Join-Path $build "aligned.apk"
& $python $packageScript $resourcesApk $dex $unsigned
if ($LASTEXITCODE -ne 0) { Fail "写入 classes.dex 失败。" }

& (Join-Path $bt "zipalign.exe") -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { Fail "zipalign 失败。" }

if (-not (Test-Path $keystore)) {
    Write-Host "    生成本地签名证书（仅用于你自己的手机）"
    & $keytool -genkeypair -keystore $keystore -storepass android -alias androiddebugkey `
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "生成签名证书失败。" }
}

$apk = Join-Path $dist "PageFlipper-v$versionName.apk"
if (Test-Path $apk) { Remove-Item -Force $apk }
$signOut = & (Join-Path $bt "apksigner.bat") sign --ks $keystore --ks-pass pass:android `
    --key-pass pass:android --v4-signing-enabled false --out $apk $aligned 2>&1
if ($LASTEXITCODE -ne 0) {
    $signOut | ForEach-Object { Write-Host $_ }
    Fail "apksigner 签名失败。"
}

Write-Host "==> 校验 APK" -ForegroundColor Cyan
$verifyOut = & (Join-Path $bt "apksigner.bat") verify --verbose $apk 2>&1
if ($LASTEXITCODE -ne 0) {
    $verifyOut | ForEach-Object { Write-Host $_ }
    Fail "APK 签名校验失败。"
}
$verifyOut | Select-String -Pattern "Verified using|Number of signers"

$size = [math]::Round((Get-Item $apk).Length / 1KB, 1)
Write-Host ""
Write-Host "构建完成: $apk ($size KB)" -ForegroundColor Green
& (Join-Path $bt "aapt2.exe") dump badging $apk |
    Select-String -Pattern "^package:|^minSdkVersion|^targetSdkVersion|^application-label" |
    ForEach-Object { Write-Host $_.Line }

if ($Install) {
    Write-Host ""
    Write-Host "==> 安装到已连接的手机" -ForegroundColor Cyan
    $devices = & (Join-Path $sdk "platform-tools\adb.exe") devices
    $ready = @($devices | Where-Object { $_ -match "\s+device$" })
    if ($LASTEXITCODE -ne 0 -or $ready.Count -eq 0) {
        Fail "没有检测到已授权的设备。请连接手机并打开 USB 调试。"
    }
    & (Join-Path $sdk "platform-tools\adb.exe") install -r $apk
    if ($LASTEXITCODE -ne 0) { Fail "adb install 失败。" }
    Write-Host "安装完成。请在手机上打开“翻页笔”。" -ForegroundColor Green
}

Write-Host ""
Write-Host "提示：请保留 keys\local-debug.keystore。删除后新 APK 将无法覆盖安装旧版本。" -ForegroundColor Yellow
exit 0
