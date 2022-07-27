@echo off

if not exist "C:\Program Files\iTunes\iTunes.exe" (
    if not exist "C:\Program Files (x86)\iTunes\iTunes.exe" (
        echo [Error] iTunes does not seem to be installed.
        echo * Please install iTunes 12.6.5 or older before proceeding.
        echo * Read the "How to Use" wiki page in GitHub for more details.
        pause >nul
        exit
    )
)

if not exist "C:\msys64\msys2.exe" (
    echo [Error] MSYS2 does not seem to be installed.
    echo * Please install MSYS2 first before proceeding.
    echo * Read the "How to Use" wiki page in GitHub for more details.
    pause >nul
    exit
)

C:\msys64\msys2.exe "./restore.sh"

rem Add the argument at the end of the line above if needed
rem Examples:
rem C:\msys64\msys2.exe "./restore.sh" NoDevice
rem C:\msys64\msys2.exe "./restore.sh" PwnedDevice
