@echo off
setlocal enabledelayedexpansion

:: --- WORKER ROUTINE HOOK ---
if "%~1"=="_worker" goto _worker

:: ==========================================
:: CONFIGURATION
:: ==========================================
set "SOURCE_DIR=E:\Medical Study\BTR\Main"
set "DEST_DIR=E:\Medical Study\BTR\audio"
set "MAX_THREADS=16"
:: ==========================================

:: Clean up any leftover lock files from previous runs
del /q "%temp%\lock_*.txt" 2>nul

echo =======================================================
echo     MAX-SPEED MULTI-THREADED AUDIO EXTRACTION
echo =======================================================
echo  Source:      "%SOURCE_DIR%"
echo  Destination: "%DEST_DIR%"
echo  Threads:     %MAX_THREADS% Active Lanes
echo -------------------------------------------------------

if not exist "%SOURCE_DIR%" (
    echo ERROR: Source folder does not exist! Check your path.
    pause
    exit /b
)

for /r "%SOURCE_DIR%" %%F in (*.mp4) do (
    set "ABS_DIR=%%~dpF"
    set "REL_DIR=!ABS_DIR:%SOURCE_DIR%=!"
    set "TARGET_DIR=%DEST_DIR%!REL_DIR!"
    
    if "!TARGET_DIR:~-1!"=="\" set "TARGET_DIR=!TARGET_DIR:~0,-1!"
    if not exist "!TARGET_DIR!" mkdir "!TARGET_DIR!"

    echo Queuing: ...!REL_DIR!%%~nxF

    :: Thread controller loop
    :thread_wait
    set "active_threads=0"
    for /l %%I in (1,1,%MAX_THREADS%) do (
        if exist "%temp%\lock_%%I.txt" set /a active_threads+=1
    )
    if !active_threads! geq %MAX_THREADS% (
        timeout /t 1 /nobreak >nul
        goto thread_wait
    )

    :: Find an available slot/thread number
    set "assigned_slot="
    for /l %%I in (1,1,%MAX_THREADS%) do (
        if not defined assigned_slot (
            if not exist "%temp%\lock_%%I.txt" (
                set "assigned_slot=%%I"
                echo slot_token > "%temp%\lock_%%I.txt"
            )
        )
    )

    :: Launch background worker passing the assigned slot number
    start "FFmpeg_Worker" /b cmd /c ""%~f0" _worker "%%F" "!TARGET_DIR!\%%~nF" !assigned_slot!"
)

echo -------------------------------------------------------
echo All files queued. Waiting for remaining background extractions to close...
:final_wait
for /l %%I in (1,1,%MAX_THREADS%) do (
    if exist "%temp%\lock_%%I.txt" (
        timeout /t 1 /nobreak >nul
        goto final_wait
    )
)

echo -------------------------------------------------------
echo Success! Your structured audio library is ready.
pause
exit /b

:: ==========================================
:: BACKGROUND WORKER ROUTINE
:: ==========================================
:_worker
set "INPUT_FILE=%~2"
set "OUTPUT_BASE=%~3"
set "SLOT=%~4"

:: Query ffprobe to check the internal audio stream format dynamically
for /f "tokens=*" %%A in ('ffprobe -v error -select_streams a:0 -show_entries stream^=codec_name -of default^=noprint_wrappers^=1:nokey^=1 "%INPUT_FILE%"') do (
    set "CODEC=%%A"
)

:: Set standard file extensions based on the codec found
set "EXT=.aac"
if "!CODEC!"=="aac"  set "EXT=.m4a"
if "!CODEC!"=="mp3"  set "EXT=.mp3"
if "!CODEC!"=="opus" set "EXT=.opus"
if "!CODEC!"=="flac" set "EXT=.flac"

:: Extract the audio stream instantaneously without re-encoding
ffmpeg -y -i "%INPUT_FILE%" -vn -c:a copy "%OUTPUT_BASE%!EXT!" >nul 2>&1

:: Release the lock token slot
del /q "%temp%\lock_%SLOT%.txt" 2>nul
exit /b