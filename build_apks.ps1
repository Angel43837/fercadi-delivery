# build_apks.ps1
# Genera dos APKs firmados: app principal y app admin
# Ambos con IDs distintos para instalar juntos sin conflicto

$flutter = "C:\src\flutter\bin\flutter.bat"

Write-Host "=== APK Principal (GOGO Food) ===" -ForegroundColor Cyan
$env:FLUTTER_APP_ID = "com.fercadi.app"
& $flutter build apk --target lib/main.dart --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "build\GOGOFood.apk" -Force
Write-Host "Guardado: build\GOGOFood.apk" -ForegroundColor Green

Write-Host ""
Write-Host "=== APK Admin (GOGO Admin) ===" -ForegroundColor Cyan
$env:FLUTTER_APP_ID = "com.fercadi.admin"
& $flutter build apk --target lib/main_admin.dart --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "build\GOGOAdmin.apk" -Force
Write-Host "Guardado: build\GOGOAdmin.apk" -ForegroundColor Green

Write-Host ""
Write-Host "Listo. Ambos APKs en la carpeta build\" -ForegroundColor Yellow
