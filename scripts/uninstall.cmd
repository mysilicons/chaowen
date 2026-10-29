@echo off
chcp 65001 >nul
set "TARGET=%LOCALAPPDATA%\Programs\ChaoWen"

echo 正在卸载朝闻...
taskkill /IM rmrb_reader.exe /F >nul 2>&1
timeout /t 1 /nobreak >nul

del "%USERPROFILE%\Desktop\朝闻.lnk" >nul 2>&1
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\朝闻.lnk" >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ChaoWen" /f >nul 2>&1

if exist "%TARGET%" rmdir /S /Q "%TARGET%"

echo.
echo 已卸载。以下目录保留（个人存档与缓存），需要时可手动删除：
echo   下载的报纸：%USERPROFILE%\Documents\人民日报
echo   缓存与状态：%LOCALAPPDATA%\rmrb-reader
echo.
pause
