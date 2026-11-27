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

flutter pub add flutter_riverpod media_kit media_kit_video media_kit_libs_ios_video path_provider path file_picker:^10.0.0 audio_service audio_session liquid_design:^0.4.1 audio_metadata_reader video_thumbnail youtube_explode_dart:^3.1.0 webview_flutter:^4.14.0 dio:^5.11.1 app_links:^7.2.2 ffmpeg_kit_flutter_new:^5.0.0

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
# السماح بالتحميل والتصفح لأي رابط + دعم Deep Link (shaghal://)
$PB -c "Add :NSAppTransportSecurity dict" "$PLIST" || true
$PB -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes array" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes:0 dict" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Editor" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.yalkhodary.shaghal" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST" || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string shaghal" "$PLIST" || true
# اسم التطبيق تحت الأيقونة
$PB -c "Set :CFBundleDisplayName 'Shaghal - شغل'" "$PLIST" || $PB -c "Add :CFBundleDisplayName string 'Shaghal - شغل'" "$PLIST"

# إضافة Share Extension وجسر AVFoundation للدمج/استخراج الصوت
if [ -d "../ios_templates" ]; then
  if ruby -e "require 'xcodeproj'" 2>/dev/null; then
    ruby ../ios_templates/configure_ios.rb
  else
    POD_BIN=$(command -v pod 2>/dev/null || true)
    POD_SHEBANG=$([ -n "$POD_BIN" ] && head -1 "$POD_BIN" 2>/dev/null | sed 's/^#!//' | xargs || true)
    if [ -n "$POD_SHEBANG" ] && [ -x "$POD_SHEBANG" ] && "$POD_SHEBANG" -e "require 'xcodeproj'" 2>/dev/null; then
      "$POD_SHEBANG" ../ios_templates/configure_ios.rb
    else
      gem install --user-install xcodeproj --no-document
      GEM_USER_DIR=$(ruby -e 'puts Gem.user_dir')
      GEM_PATH="${GEM_USER_DIR}:${GEM_PATH:-}" ruby ../ios_templates/configure_ios.rb
    fi
  fi
fi

# ffmpeg_kit_flutter_new محتاج iOS 15 على الأقل
sed -i '' "s/^# *platform :ios.*/platform :ios, '15.0'/" ios/Podfile || true

flutter pub get
flutter analyze || true
echo "جاهز. افتح الجهاز/المحاكي وشغّل: cd app && flutter run"
