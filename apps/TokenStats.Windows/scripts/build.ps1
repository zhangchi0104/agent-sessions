[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string] $Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $projectRoot "TokenStats.Windows.sln"
$nugetConfig = Join-Path $projectRoot "NuGet.Config"
$tests = Join-Path $projectRoot "tests\TokenStats.Core.Tests\TokenStats.Core.Tests.csproj"
$uiSmoke = Join-Path $projectRoot "tests\TokenStats.UiSmoke\TokenStats.UiSmoke.csproj"

dotnet restore $solution --configfile $nugetConfig
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet build $solution --configuration $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet run --project $tests --configuration $Configuration --no-build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet run --project $uiSmoke --configuration $Configuration --no-build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
