@echo off
setlocal enabledelayedexpansion
rem Double-click to rebuild VerifiedData.lua from your saved Merchant Map data.
rem Log out or /reload in game first so the saved data is up to date.

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

rem Saved data from every account in this game folder
set "FILES="
for /d %%A in ("..\..\..\WTF\Account\*") do (
    if exist "%%A\SavedVariables\MerchantMap.lua" set FILES=!FILES! "%%A\SavedVariables\MerchantMap.lua"
    rem Data saved before the rename from Vendor Atlas
    if exist "%%A\SavedVariables\VendorAtlas.lua" set FILES=!FILES! "%%A\SavedVariables\VendorAtlas.lua"
)
if not defined FILES (
    echo No saved Merchant Map data found. Log in, then log out or /reload, and try again.
    pause
    exit /b 1
)

%LUA% Tools\BuildVerifiedData.lua VerifiedData.lua %FILES%
pause
