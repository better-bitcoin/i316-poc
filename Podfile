# Podfile — 从官方 tag 15.2.0 拉取 (该 tag 含 ios-arm64_x86_64-simulator slice)
platform :ios, '16.0'
project 'PoC.xcodeproj'

target 'PoC' do
  use_frameworks!
  pod 'ZendeskSDKConversationKit', :git => 'https://github.com/zendesk/sdk_conversation_kit_ios.git', :tag => '15.2.0'
  # 依赖 (FayeClient/HTTPClient/Storage/CoreUtilities) 由 podspec 自动解析
end
