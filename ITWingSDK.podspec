Pod::Spec.new do |s|
  s.name             = 'ITWingSDK'
  s.version          = '1.0.0'
  s.summary          = 'IT Wing Technologies dynamic ads and remote config SDK.'
  s.homepage         = 'https://itwingtechnologies.com'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'IT Wing Technologies' => 'support@itwingtechnologies.com' }
  s.source           = { :git => 'https://github.com/shahzamansurani/ITWingSDK-iOS.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/ITWingSDK/**/*.swift'
  s.resource_bundles = { 'ITWingSDK_Privacy' => ['Sources/ITWingSDK/Resources/PrivacyInfo.xcprivacy'] }
  s.dependency 'Google-Mobile-Ads-SDK', '~> 13.6'
  s.dependency 'lottie-ios', '~> 4.5'
end
