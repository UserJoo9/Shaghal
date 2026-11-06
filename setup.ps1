# للتجربة على Windows. شغّله من PowerShell جوّه فولدر shaghal:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
# المتطلبات: Flutter + Visual Studio (workload: Desktop development with C++) + Developer Mode مفعّل.
$ErrorActionPreference = 'Stop'

flutter create --platforms=windows,ios --project-name shaghal --org com.yalkhodary app
Copy-Item -Recurse -Force .\lib\* .\app\lib\
New-Item -ItemType Directory -Force .\app\assets\icon | Out-Null
Copy-Item -Force .\assets\icon\icon.png .\app\assets\icon\icon.png
Copy-Item -Force .\flutter_launcher_icons.yaml .\app\
Set-Location app

flutter pub add flutter_riverpod media_kit media_kit_video media_kit_libs_video path_provider path file_picker:^10.0.0 audio_service audio_session liquid_design:^0.4.1

flutter pub add --dev flutter_launcher_icons
dart run flutter_launcher_icons

# إعدادات iOS (مشاركة الملفات + الصوت في الخلفية) عشان الـ Info.plist يبقى جاهز
$plist = Join-Path (Get-Location) 'ios\Runner\Info.plist'
$xml = [IO.File]::ReadAllText($plist)
if ($xml -notmatch 'UIFileSharingEnabled') {
  $add = "`t<key>UIFileSharingEnabled</key>`n`t<true/>`n" +
         "`t<key>LSSupportsOpeningDocumentsInPlace</key>`n`t<true/>`n" +
         "`t<key>UIBackgroundModes</key>`n`t<array>`n`t`t<string>audio</string>`n`t</array>`n"
  $xml = $xml.Insert($xml.LastIndexOf('</dict>'), $add)
  [IO.File]::WriteAllText($plist, $xml, (New-Object Text.UTF8Encoding($false)))
}

# اسم التطبيق تحت الأيقونة
$xml = [IO.File]::ReadAllText($plist)
$xml = [regex]::Replace($xml, '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', '${1}Shaghal - شغل${2}')
[IO.File]::WriteAllText($plist, $xml, (New-Object Text.UTF8Encoding($false)))

flutter pub get
flutter analyze
Write-Host "جاهز. شغّل: cd app ; flutter run -d windows"
Write-Host "حط ملفات التجربة في: Documents\Shaghal"
