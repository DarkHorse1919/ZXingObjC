Pod::Spec.new do |s|
  s.name                        = "ZXingObjC"
  s.version                     = "2.2.7"
  s.summary                     = "An Objective-C Port of the ZXing barcode framework."
  s.homepage                    = "https://github.com/TheLevelUp/ZXingObjC"
  s.author                      = "ZXing and ZXingObjC team"
  s.license                     = { :type => 'Apache License 2.0', :file => 'COPYING' }
  s.source                      = { :git => "https://github.com/TheLevelUp/ZXingObjC.git", :tag => "#{s.version}" }
  s.source_files                = 'ZXingObjC/**/*.{h,m}'
  s.requires_arc                = true

  s.ios.deployment_target 	= '6.0'
  s.osx.deployment_target 	= '10.8'

  s.ios.frameworks              = 'AVFoundation', 'CoreGraphics', 'CoreMedia', 'CoreVideo', 'ImageIO', 'QuartzCore'
  s.osx.frameworks              = 'AVFoundation', 'CoreMedia', 'QuartzCore'
end
