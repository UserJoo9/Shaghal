#!/usr/bin/env ruby
# Adds ShaghalBridge.swift + ShareExtension target to the generated Runner.xcodeproj
require 'fileutils'
require 'xcodeproj'

templates_dir = File.expand_path(__dir__)
ios_dir = File.expand_path('ios', Dir.pwd)
proj_path = File.join(ios_dir, 'Runner.xcodeproj')

abort("Runner.xcodeproj not found at #{proj_path}") unless File.exist?(proj_path)

# 1. Copy Runner helper files
runner_dir = File.join(ios_dir, 'Runner')
FileUtils.cp(File.join(templates_dir, 'Runner', 'ShaghalBridge.swift'), File.join(runner_dir, 'ShaghalBridge.swift'))
FileUtils.cp(File.join(templates_dir, 'Runner', 'Runner.entitlements'), File.join(runner_dir, 'Runner.entitlements'))

# 2. Copy ShareExtension files
ext_dir = File.join(ios_dir, 'ShareExtension')
FileUtils.mkdir_p(ext_dir)
%w[ShareViewController.swift Info.plist ShareExtension.entitlements].each do |f|
  FileUtils.cp(File.join(templates_dir, 'ShareExtension', f), File.join(ext_dir, f))
end

# 3. Patch AppDelegate.swift cleanly (works with both old FlutterAppDelegate and UIScene FlutterImplicitEngineDelegate)
app_delegate = File.join(runner_dir, 'AppDelegate.swift')
if File.exist?(app_delegate)
  src = File.read(app_delegate)
  unless src.include?('ShaghalBridge.register')
    if src.include?('GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)')
      src.sub!(
        'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
        "GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)\n    ShaghalBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: \"ShaghalBridge\"))"
      )
    elsif src.include?('GeneratedPluginRegistrant.register(with: self)')
      src.sub!(
        'GeneratedPluginRegistrant.register(with: self)',
        "GeneratedPluginRegistrant.register(with: self)\n    ShaghalBridge.register(with: self.registrar(forPlugin: \"ShaghalBridge\"))"
      )
    end
    File.write(app_delegate, src)
  end
end

# 4. Update Xcode project
project = Xcodeproj::Project.open(proj_path)
runner_target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless runner_target

runner_group = project.main_group.find_subpath('Runner', true)
unless runner_group.files.any? { |f| f.path == 'ShaghalBridge.swift' }
  bridge_ref = runner_group.new_reference('ShaghalBridge.swift')
  runner_target.source_build_phase.add_file_reference(bridge_ref)
end
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

runner_target.build_configurations.each do |cfg|
  cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  cfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
end

unless project.targets.any? { |t| t.name == 'ShareExtension' }
  ext_target = project.new_target(:app_extension, 'ShareExtension', :ios, '15.0')
  ext_group = project.main_group.new_group('ShareExtension', 'ShareExtension')
  vc_ref = ext_group.new_reference('ShareViewController.swift')
  ext_group.new_reference('Info.plist')
  ext_group.new_reference('ShareExtension.entitlements')
  ext_target.source_build_phase.add_file_reference(vc_ref)

  ext_target.build_configurations.each do |cfg|
    bs = cfg.build_settings
    bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.yalkhodary.shaghal.ShareExtension'
    bs['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
    bs['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
    bs['GENERATE_INFOPLIST_FILE'] = 'NO'
    bs['SKIP_INSTALL'] = 'YES'
    bs['SWIFT_VERSION'] = '5.0'
    bs['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    bs['TARGETED_DEVICE_FAMILY'] = '1,2'
    bs['CLANG_ENABLE_MODULES'] = 'YES'
    bs['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
    bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  end

  runner_target.add_dependency(ext_target)
  embed_phase = runner_target.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
  unless embed_phase
    embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
    embed_phase.dst_subfolder_spec = '13'
    embed_phase.dst_path = ''
  end
  build_file = embed_phase.add_file_reference(ext_target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

project.save
puts 'Configured Runner + ShareExtension successfully.'
