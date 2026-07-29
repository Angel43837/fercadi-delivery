# build_apks.ps1
# Genera tres APKs firmados: app principal, app admin y app flota
# Todos con IDs distintos para instalar juntos sin conflicto

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
Write-Host "=== APK Flota (GOGO Flota) ===" -ForegroundColor Cyan
$env:FLUTTER_APP_ID = "com.fercadi.flota"
& $flutter build apk --target lib/main_flota.dart --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "build\GOGOFlota.apk" -Force
Write-Host "Guardado: build\GOGOFlota.apk" -ForegroundColor Green

Write-Host ""
Write-Host "Listo. Los tres APKs estan en la carpeta build\" -ForegroundColor Yellow
