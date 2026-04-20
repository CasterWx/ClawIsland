require 'xcodeproj'
project_path = 'ClawIsLand.xcodeproj'
project = Xcodeproj::Project.open(project_path)

entitlements_path = 'ClawIsLand/ClawIsLand.entitlements'
unless File.exist?(entitlements_path)
  File.write(entitlements_path, <<~ENTITLEMENTS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>com.apple.security.app-sandbox</key>
        <true/>
    </dict>
    </plist>
  ENTITLEMENTS
  )
end

project.targets.each do |target|
  if target.name == 'ClawIsLand'
    target.build_configurations.each do |config|
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ClawIsLand/ClawIsLand.entitlements'
    end
  end
end

project.save
