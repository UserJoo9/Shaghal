#!/usr/bin/env bash
# شغّله على الـ Mac (محتاج Flutter + Xcode). من جوّه فولدر shaghal:
#   chmod +x setup.sh && ./setup.sh
set -euo pipefail

flutter create --platforms=ios --project-name shaghal --org com.yalkhodary app
cp -R lib/. app/lib/
mkdir -p app/assets/icon
cp assets/icon/icon.png app/assets/icon/icon.png
cp flutter_launcher_icons.yaml app/
cd app

flutter pub add flutter_riverpod media_kit media_kit_video media_kit_libs_ios_video path_provider path file_picker:^10.0.0 audio_service audio_session audio_metadata_reader video_thumbnail

# نسخة معدّلة من liquid_design (حركة عدسة الـ navbar) جوّه المشروع
cp -R ../packages .
flutter pub add liquid_design --path packages/liquid_design

flutter pub add --dev flutter_launcher_icons
dart run flutter_launcher_icons

PLIST=ios/Runner/Info.plist
PB=/usr/libexec/PlistBuddy
# الملفات تظهر في تطبيق «الملفات» ← على iPhone ← Shaghal
$PB -c "Add :UIFileSharingEnabled bool true" "$PLIST" || true
$PB -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$PLIST" || true
# تشغيل الصوت في الخلفية
$PB -c "Add :UIBackgroundModes array" "$PLIST" || true
$PB -c "Add :UIBackgroundModes:0 string audio" "$PLIST" || true
# اسم التطبيق تحت الأيقونة
$PB -c "Set :CFBundleDisplayName 'Shaghal - شغل'" "$PLIST" || $PB -c "Add :CFBundleDisplayName string 'Shaghal - شغل'" "$PLIST"

# media_kit محتاج iOS 13 على الأقل
sed -i '' "s/^# *platform :ios.*/platform :ios, '13.0'/" ios/Podfile || true

flutter pub get
flutter analyze || true
echo "جاهز. افتح الجهاز/المحاكي وشغّل: cd app && flutter run"
