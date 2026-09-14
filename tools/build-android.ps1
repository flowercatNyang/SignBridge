param(
    [Parameter(Mandatory = $true)]
    [string]$JdkHome
)
$ErrorActionPreference = 'Stop'
$jdkPath = (Resolve-Path -LiteralPath $JdkHome).Path
if (-not (Test-Path -LiteralPath (Join-Path $jdkPath 'bin/java.exe'))) {
    throw 'JdkHome must point to a JDK 11 directory.'
}
$previousJavaHome = $env:JAVA_HOME
$repoRoot = Split-Path -Parent $PSScriptRoot
try {
    $env:JAVA_HOME = $jdkPath
    Push-Location -LiteralPath $repoRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
        & ./android/gradlew.bat -p android "-Dorg.gradle.java.home=$jdkPath" assembleDebug
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
        Write-Output (Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk')
    } finally {
        Pop-Location
    }
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
