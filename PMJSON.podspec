Pod::Spec.new do |s|
  s.name         = "PMJSON"
  s.version      = "3.1.2"
  s.summary      = "Pure Swift JSON encoding/decoding library"
  s.description  = "PMJSON provides a pure-Swift strongly-typed JSON encoder/decoder as well as a set of convenience methods for converting to/from Foundation objects and for decoding JSON structures."

  s.homepage     = "https://github.com/postmates/PMJSON"

  s.license      = "MIT & Apache License, Version 2.0"

  s.author             = { "Lily Ballard" => "lily@sb.org" }
  s.social_media_url   = "https://twitter.com/LilyInTech"

  s.source       = { :git => "https://github.com/postmates/PMJSON.git", :tag => "v#{s.version}" }

  s.source_files  = "Sources/**/*.{swift,h,m}",

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  s.watchos.deployment_target = '2.0'
  s.tvos.deployment_target = '9.0'

  s.swift_version = '4.0'
end
