[CmdletBinding()]
param(
    [ValidateSet("win-x64", "win-arm64")]
    [string] $Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $projectRoot "src\TokenStats.App\TokenStats.App.csproj"
$nugetConfig = Join-Path $projectRoot "NuGet.Config"
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot "artifacts"))
$output = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot $Runtime))
$requiredPrefix = $artifactsRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith(
        $requiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to publish outside the TokenStats artifacts directory: $output"
}

dotnet restore $project `
    --runtime $Runtime `
    --configfile $nugetConfig
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}

dotnet publish $project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained true `
    --output $output `
    --no-restore `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false `
    -p:DebugType=None
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Published TokenStats to $output"
