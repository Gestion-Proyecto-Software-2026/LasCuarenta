@echo off
rem ==========================================================================
rem  Las Cuarenta: una partida completa en este ordenador, con doble clic.
rem
rem  Abre una ventana por jugador (2 o 4, colocadas en rejilla) y esta consola
rem  hace de servidor. Al acabar la partida, vuelve al menu para jugar otra.
rem
rem  Uso, con dos argumentos opcionales y en cualquier orden:
rem    jugar.bat [MODO] [ruta\de\Godot.exe]
rem    MODO: guinote_1v1 guinote_2v2 tute_1v1 tute_2v2 mus_1v1 mus_2v2
rem  Tambien se puede arrastrar el .exe de Godot encima de este fichero.
rem
rem  Godot 4.7 se busca en: la variable GODOT, la ruta de la vez anterior
rem  (guardada en LOCALAPPDATA\LasCuarenta\godot.txt), el PATH y, junto con
rem  sus subcarpetas, esta carpeta, la de arriba, Descargas y Escritorio.
rem  Si no aparece, lo pide.
rem
rem  OJO: este fichero tiene que ser solo ASCII (sin tildes ni enes) y con
rem  finales de linea CRLF. Con la consola en UTF-8 (chcp 65001, para ver bien
rem  lo que escribe el servidor), cmd calcula mal donde esta cada linea si hay
rem  letras de varios bytes y salta a sitios que no son. La "enie" de Guinote
rem  se fabrica al arrancar (variable ENIE).
rem ==========================================================================

setlocal EnableExtensions
for /f "tokens=2 delims=:." %%c in ('chcp') do set "PAGINA_ANTES=%%c"
chcp 65001 >nul
title Las Cuarenta - servidor

set "JUEGO=%~dp0game"
set "TITULO_JUGADOR=Las Cuarenta - jugador"
set "MODOS=guinote_1v1 guinote_2v2 tute_1v1 tute_2v2 mus_1v1 mus_2v2"
set "GUARDADO=%LOCALAPPDATA%\LasCuarenta\godot.txt"
set "MODO="
set "GODOT_EXE="
set "YA_JUGADO="

rem La enie en UTF-8 son los bytes C3 B1.
set "ENIE=n"
> "%TEMP%\lascuarenta_enie.hex" echo C3B1
certutil -f -decodehex "%TEMP%\lascuarenta_enie.hex" "%TEMP%\lascuarenta_enie.txt" >nul 2>&1
if exist "%TEMP%\lascuarenta_enie.txt" set /p ENIE=<"%TEMP%\lascuarenta_enie.txt"
del "%TEMP%\lascuarenta_enie.hex" "%TEMP%\lascuarenta_enie.txt" >nul 2>&1

if not exist "%JUEGO%\project.godot" (
	echo.
	echo  No encuentro game\project.godot: jugar.bat tiene que estar en la carpeta principal del repositorio.
	goto salir_con_pausa
)

:argumentos
if "%~1"=="" goto buscar_godot
if /i "%~x1"==".exe" (call :probar "%~f1") else set "MODO=%~1"
shift
goto argumentos

:buscar_godot
if defined GODOT call :probar "%GODOT%"
if exist "%GUARDADO%" call :probar_guardada
for /f "delims=" %%G in ('where godot 2^>nul') do call :probar "%%G"
rem Primero un 4.7 y, si no hay, cualquier 4.x. (Sin asteriscos aqui: un
rem "for" normal los tomaria como ficheros de la carpeta actual.)
for %%V in (4.7 4) do (
	call :buscar_en "%~dp0." %%V
	call :buscar_en "%~dp0.." %%V
	call :buscar_en "%USERPROFILE%\Downloads" %%V
	call :buscar_en "%USERPROFILE%\Desktop" %%V
	call :buscar_en "%USERPROFILE%\OneDrive\Escritorio" %%V
	call :buscar_en "%USERPROFILE%\OneDrive\Desktop" %%V
)
if not defined GODOT_EXE call :pedir_godot
if not defined GODOT_EXE goto salir

rem La proxima vez se encuentra a la primera.
if not exist "%LOCALAPPDATA%\LasCuarenta\" mkdir "%LOCALAPPDATA%\LasCuarenta" 2>nul
<nul set /p "=%GODOT_EXE%" >"%GUARDADO%" 2>nul

rem Godot trae dos ejecutables: el normal (para las ventanas de los jugadores)
rem y el _console (para el servidor, que escribe en esta consola).
for %%F in ("%GODOT_EXE%") do (
	set "CARPETA=%%~dpF"
	set "NOMBRE=%%~nF"
)
set "NOMBRE=%NOMBRE:_console=%"
set "GODOT_VENTANA=%CARPETA%%NOMBRE%.exe"
set "GODOT_CONSOLA=%CARPETA%%NOMBRE%_console.exe"
if not exist "%GODOT_VENTANA%" set "GODOT_VENTANA=%GODOT_EXE%"
if not exist "%GODOT_CONSOLA%" set "GODOT_CONSOLA="

set "VERSION="
if defined GODOT_CONSOLA for /f "usebackq delims=" %%V in (`"%GODOT_CONSOLA%" --version`) do if not defined VERSION set "VERSION=%%V"
echo.
echo  Godot: %GODOT_VENTANA%
if defined VERSION echo  Godot %VERSION%
if defined VERSION if not "%VERSION:~0,4%"=="4.7." echo  Aviso: el proyecto es para Godot 4.7; con este puede fallar.

echo.
echo  Preparando el proyecto (la primera vez tarda un poco)...
if defined GODOT_CONSOLA (
	"%GODOT_CONSOLA%" --headless --path "%JUEGO%" --import >"%TEMP%\lascuarenta_import.log" 2>&1
) else (
	start "" /wait "%GODOT_VENTANA%" --headless --path "%JUEGO%" --import
)

:menu
if defined MODO goto comprobar_modo
if defined YA_JUGADO cls
echo.
echo    LAS CUARENTA
echo.
echo    1  Gui%ENIE%ote 1 contra 1
echo    2  Gui%ENIE%ote por parejas
echo    3  Tute 1 contra 1
echo    4  Tute por parejas
echo    5  Mus 1 contra 1
echo    6  Mus por parejas
echo.
echo    S  Salir
echo.
choice /c 123456S /n /m "   Elige un modo (1-6) o S para salir: "
if errorlevel 7 goto salir
for /f "tokens=%errorlevel%" %%M in ("%MODOS%") do set "MODO=%%M"

:comprobar_modo
set "JUGADORES="
for %%M in (guinote_1v1 tute_1v1 mus_1v1) do if /i "%MODO%"=="%%M" set "MODO=%%M" & set "JUGADORES=2"
for %%M in (guinote_2v2 tute_2v2 mus_2v2) do if /i "%MODO%"=="%%M" set "MODO=%%M" & set "JUGADORES=4"
if defined JUGADORES goto jugar
echo.
echo  No conozco el modo "%MODO%". Los modos son: %MODOS%
set "MODO="
goto menu

:jugar
call :cerrar_ventanas
echo.
echo  ------------------------------------------------------------------
echo   Se abren %JUGADORES% ventanas, una por jugador.
if "%JUGADORES%"=="4" echo   Parejas: J1 y J3 contra J2 y J4.
echo   Esta consola es el servidor: no la cierres durante la partida.
echo   Para acabar antes, cierra la ventana de cualquier jugador.
echo  ------------------------------------------------------------------
echo.
for /l %%i in (1,1,%JUGADORES%) do start "" "%GODOT_VENTANA%" --path "%JUEGO%" res://escenas/partida.tscn -- modo=%MODO% cliente ventana=%%i
if defined GODOT_CONSOLA (
	"%GODOT_CONSOLA%" --headless --path "%JUEGO%" res://escenas/partida.tscn -- modo=%MODO% servidor salir_al_terminar
) else (
	start "" /wait "%GODOT_VENTANA%" --path "%JUEGO%" res://escenas/partida.tscn -- modo=%MODO% servidor salir_al_terminar
)
set "SALIDA=%errorlevel%"

echo.
if "%SALIDA%"=="1" echo  No se pudo abrir el servidor. Puede que ya haya otra partida de este modo abierta.
echo  Partida terminada. Cierra las ventanas de los jugadores cuando quieras
echo  o pulsa C en esta consola para cerrarlas todas. Luego se elige otra partida.
:esperar_ventanas
tasklist /fi "WINDOWTITLE eq %TITULO_JUGADOR%*" /fo csv /nh 2>nul | findstr /l /i /c:".exe" >nul || goto despues_de_jugar
choice /c CN /n /t 2 /d N >nul
if errorlevel 2 goto esperar_ventanas
call :cerrar_ventanas
:despues_de_jugar
set "MODO="
set "YA_JUGADO=1"
goto menu

:salir_con_pausa
echo.
pause
:salir
call :cerrar_ventanas
chcp %PAGINA_ANTES% >nul
endlocal
exit /b 0


rem --- Subrutinas ---

rem Se queda con %1 si es un .exe que existe (y no hay ya otro elegido).
:probar
if defined GODOT_EXE exit /b
if /i not "%~x1"==".exe" exit /b
if not exist "%~f1" exit /b
if exist "%~f1\*" exit /b
set "GODOT_EXE=%~f1"
exit /b

:probar_guardada
set "GUARDADA="
set /p GUARDADA=<"%GUARDADO%"
if defined GUARDADA call :probar "%GUARDADA%"
exit /b

rem Busca Godot_v<version %2>*.exe en la carpeta %1 y en sus subcarpetas (un nivel).
:buscar_en
if defined GODOT_EXE exit /b
if not exist "%~1\" exit /b
for %%F in ("%~1\Godot_v%~2*.exe") do call :probar "%%~fF"
for /d %%D in ("%~1\*") do for %%F in ("%%~fD\Godot_v%~2*.exe") do call :probar "%%~fF"
exit /b

:pedir_godot
echo.
echo  No encuentro Godot 4.7 en este ordenador.
echo  Hace falta Godot 4.7.2 para Windows: https://godotengine.org/download/archive/
echo  Descomprime el zip, arrastra su fichero .exe a esta ventana y pulsa Enter.
echo  Para salir, Enter sin nada.
:pedir_otra_vez
echo.
set "RESPUESTA="
set /p "RESPUESTA= Godot: "
if not defined RESPUESTA exit /b
set "RESPUESTA=%RESPUESTA:"=%"
call :probar "%RESPUESTA%"
if defined GODOT_EXE exit /b
echo  Eso no es un fichero .exe que exista. Prueba otra vez.
goto pedir_otra_vez

rem Cierra (como si se pulsara la X) las ventanas de jugador de la partida anterior.
:cerrar_ventanas
taskkill /fi "WINDOWTITLE eq %TITULO_JUGADOR%*" >nul 2>&1
exit /b
