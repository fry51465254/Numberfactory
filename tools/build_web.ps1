param([string]$Godot = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Godot) {
    $Godot = Join-Path $root '.tools/portable/Godot_v4.7.2-stable_win64_console.exe'
    if (-not (Test-Path -LiteralPath $Godot)) {
        $Godot = (Get-Command godot -ErrorAction Stop).Source
    }
}
$output = Join-Path $root 'build/web'
[IO.Directory]::CreateDirectory($output) | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'build/.gdignore'), '')
& $Godot --headless --path $root --export-release Web (Join-Path $output 'index.html')
if ($LASTEXITCODE -ne 0) { throw "Godot Web export failed: exit $LASTEXITCODE" }
$licenses = Join-Path $output 'licenses'
[IO.Directory]::CreateDirectory($licenses) | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'assets/fonts/OFL.txt') -Destination (Join-Path $licenses 'NotoSansSC-OFL.txt')
Copy-Item -LiteralPath (Join-Path $root 'assets/icons/LICENSE') -Destination (Join-Path $licenses 'Lucide-LICENSE.txt')
& $Godot --headless --path $root --script res://tools/export_engine_licenses.gd --log-file (Join-Path $root 'qa-licenses.log')
if ($LASTEXITCODE -ne 0) { throw "Engine license export failed: exit $LASTEXITCODE" }
Write-Output "Web build ready: $output"
