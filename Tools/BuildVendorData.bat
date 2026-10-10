@echo off
setlocal
rem Double-click to rebuild VendorData.lua from your installed QuestieDB (Forever).
rem Update Questie first to get their latest data.

rem Work from the addon folder (this file sits in MerchantMap\Tools)
cd /d "%~dp0.."

rem Find Lua
set "LUA="
for %%L in (lua lua54 lua5.4 lua53 lua5.3 lua52 lua5.2 lua51 lua5.1) do (
    if not defined LUA (
        where %%L >nul 2>nul
        if not errorlevel 1 set "LUA=%%L"
    )
)
if not defined LUA (
    echo Lua was not found. Install it first, for example with: winget install DEVCOM.Lua
    pause
    exit /b 1
)

set "TOC=..\QuestieDB\QuestieDB_Forever.toc"
if not exist "%TOC%" (
    echo %TOC% was not found. Install or update Questie, then try again.
    pause
    exit /b 1
)

%LUA% Tools\BuildVendorData.lua VendorData.lua "%TOC%"
pause
