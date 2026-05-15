@echo off
echo Building rootchat.exe...
pyinstaller main.py --name rootchat --onefile --console --collect-data textual --collect-data rich --noconfirm

echo.
echo Building installer...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" rootchat.iss

echo.
echo Done. Output: dist\rootchat-setup-v1.0.exe
pause
