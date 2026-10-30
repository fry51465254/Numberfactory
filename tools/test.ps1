param([string]$Godot = '', [switch]$FullGrowth, [switch]$Onboarding, [switch]$GalaxyGrowth)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Godot) {
    $Godot = Join-Path $root '.tools/portable/Godot_v4.7.2-stable_win64_console.exe'
    if (-not (Test-Path -LiteralPath $Godot)) {
        $Godot = (Get-Command godot -ErrorAction Stop).Source
    }
}
$tests = @('simulation', 'belt_build', 'routing', 'belt_texture', 'interface', 'world', 'logistics', 'world_cycle', 'save_store', 'usability', 'generation', 'adaptive', 'device_texture', 'build_tools', 'galaxy')
if ($Onboarding) { $tests += @('onboarding') }
if ($GalaxyGrowth) { $tests += @('galaxy_growth', 'galaxy_checkpoint') }
if ($FullGrowth) { $tests += @('planner', 'growth', 'checkpoint') }
foreach ($test in $tests) {
    & $Godot --headless --path $root --script "res://tests/$($test)_test.gd" --log-file (Join-Path $root "qa-$test.log") -- --qa --test
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $test, exit $LASTEXITCODE" }
}
