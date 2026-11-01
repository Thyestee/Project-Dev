# Builds build/DeepFindsLauncher.exe with the C# compiler that ships with Windows (.NET Framework 4.8).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$out = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $out | Out-Null

& $csc /nologo /target:winexe /optimize+ "/out:$out\DeepFindsLauncher.exe" "/win32icon:$PSScriptRoot\icon.ico" `
    /r:System.Net.Http.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
    /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    "$PSScriptRoot\DeepFindsLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw 'The launcher failed to compile.' }
Write-Host "Built $out\DeepFindsLauncher.exe"
