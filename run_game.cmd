@echo off
setlocal
cd /d "%~dp0"
if exist ".tools\portable\Godot_v4.7.2-stable_win64.exe" (
  start "" ".tools\portable\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
) else (
  echo Open project.godot with Godot 4.7 and press F5.
  pause
)
