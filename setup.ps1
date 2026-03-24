$ErrorActionPreference = "Stop"
Write-Host "Setting up headless environment for Android SDK and Flutter..."

Write-Host "1. Structuring SDK Pathing..."
$srcDir = "C:\src"
$androidSdkDir = "$srcDir\android_sdk"
$javaDir = "$srcDir\java"

Write-Host "2. Downloading & Extracting Java 17..."
if (-not (Test-Path "$srcDir\java.zip")) {
    Invoke-WebRequest -Uri "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.10%2B7/OpenJDK17U-jdk_x64_windows_hotspot_17.0.10_7.zip" -OutFile "$srcDir\java.zip"
}
if (-not (Test-Path $javaDir)) {
    Expand-Archive -Path "$srcDir\java.zip" -DestinationPath $javaDir -Force
}

$jdkFolder = (Get-ChildItem -Path $javaDir -Directory -Filter "jdk*")[0].FullName
$javaBin = "$jdkFolder\bin"
[Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkFolder, "User")
$env:JAVA_HOME = $jdkFolder
$env:PATH += ";$javaBin"

Write-Host "3. Configuring Android Command Line Tools..."
if (Test-Path "$androidSdkDir\cmdline-tools\cmdline-tools") {
    Rename-Item "$androidSdkDir\cmdline-tools\cmdline-tools" "$androidSdkDir\cmdline-tools\latest"
}

$sdkManager = "$androidSdkDir\cmdline-tools\latest\bin\sdkmanager.bat"

Write-Host "4. Accepting Android SDK Licenses and Downloading Dependencies..."
echo "y" | & $sdkManager --licenses
& $sdkManager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

Write-Host "5. Mapping Global User Paths..."
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notmatch "flutter\bin") {
    $userPath += ";$srcDir\flutter\bin"
}
if ($userPath -notmatch "android_sdk") {
    $userPath += ";$androidSdkDir\platform-tools;$androidSdkDir\cmdline-tools\latest\bin;$javaBin"
}

[Environment]::SetEnvironmentVariable("ANDROID_HOME", $androidSdkDir, "User")
[Environment]::SetEnvironmentVariable("PATH", $userPath, "User")

Write-Host "Done!"
