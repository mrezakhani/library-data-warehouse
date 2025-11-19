@echo off
REM ====================================================================
REM Automatischer Start: Data Warehouse Bibliotheksprojekt
REM ====================================================================

echo.
echo ====================================================================
echo    DATA WAREHOUSE BIBLIOTHEKSPROJEKT - AUTOMATISCHER START
echo ====================================================================
echo.

REM Zum Projektverzeichnis wechseln

echo [1/4] Arbeitsverzeichnis: %CD%
echo.

REM Prüfen ob OLTP-Datenbank existiert
if not exist bibliothek_oltp.db (
    echo FEHLER: bibliothek_oltp.db nicht gefunden!
    echo Bitte stellen Sie sicher, dass die korrigierte Quelldatenbank vorhanden ist.
    pause
    exit /b 1
)
echo [2/4] OLTP-Datenbank gefunden: bibliothek_oltp.db 
echo.

REM Alte DWH-Datenbank loeschen (falls vorhanden)
if exist bibliothek_dwh.db (
    echo Loesche alte DWH-Datenbank...
    del bibliothek_dwh.db
)

REM DWH-Schema erstellen
echo [3/5] Erstelle DWH-Schema...
python -c "import sqlite3; conn = sqlite3.connect('bibliothek_dwh.db'); conn.executescript(open('DWH_Schema.sql', 'r', encoding='utf-8').read()); conn.close(); print('Schema erstellt!')"
echo.

REM ETL-Prozess ausfuehren
echo [4/5] Starte ETL-Prozess...
echo ====================================================================
python ETL_Complete.py
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo FEHLER: ETL-Prozess fehlgeschlagen!
    pause
    exit /b 1
)

echo.
echo ====================================================================
echo [5/5] Starte Analytische Auswertungen...
echo ====================================================================
python Quick_Analysis.py

echo.
echo ====================================================================
echo    PROJEKT ERFOLGREICH AUSGEFUEHRT!
echo ====================================================================
echo.
echo Die folgenden Dateien wurden erstellt:
echo   - bibliothek_dwh.db (Data Warehouse mit 3.262 Datensaetzen)
echo.
echo Sie koennen nun:
echo   1. Die DWH-Datenbank in DB Browser oeffnen
echo   2. Eigene SQL-Queries ausfuehren
echo   3. Die Analysen in Quick_Analysis.py anpassen
echo.
pause
