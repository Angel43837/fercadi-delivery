# build_apks.ps1
# Genera el APK firmado de la app principal (GOGO Food).
# GOGO Admin y GOGO Flota ya no se compilan desde aquí: tienen sus propios
# repos (GOGO-ADMIN y gogo-flota), cada uno con su `flutter build apk`.

$flutter = "C:\src\flutter\bin\flutter.bat"

Write-Host "=== APK Principal (GOGO Food) ===" -ForegroundColor Cyan
$env:FLUTTER_APP_ID = "com.fercadi.app"
& $flutter build apk --target lib/main.dart --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "build\GOGOFood.apk" -Force
Write-Host "Guardado: build\GOGOFood.apk" -ForegroundColor Green
