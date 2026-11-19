@echo off
rem Wrapper for build.ps1 - uses PowerShell 7 (pwsh) so that the UTF-8
rem source file is parsed correctly even without a BOM.
pwsh -NoProfile -File "%~dp0build.ps1" %*
