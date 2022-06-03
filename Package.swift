// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Daisy",
    defaultLocalization: "sv",
    //platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    platforms: [.iOS(.v13), .tvOS(.v13)],
    products: [
        .library(name: "AppSettings",               targets: ["AppSettings"]),
        .library(name: "Assistant",                 targets: ["Assistant"]),
        .library(name: "AudioSwitchboard",          targets: ["AudioSwitchboard"]),
        .library(name: "AutomatedFetcher",          targets: ["AutomatedFetcher"]),
        .library(name: "Dragoman",                  targets: ["Dragoman"]),
        .library(name: "FFTPublisher",              targets: ["FFTPublisher"]),
        .library(name: "Instagram",                 targets: ["Instagram"]),
        .library(name: "Meals",                     targets: ["Meals"]),
        .library(name: "PublicCalendar",            targets: ["PublicCalendar"]),
        .library(name: "Shout",                     targets: ["Shout"]),
        .library(name: "TTS",                       targets: ["TTS"]),
        .library(name: "STT",                       targets: ["STT"]),
        .library(name: "TextTranslator",            targets: ["TextTranslator"]),
        .library(name: "Weather",                   targets: ["Weather"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.2"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2")
    ],
    targets: [
        .target(name: "AppSettings",                dependencies: [],                                           path:"AppSettings/Sources"),
        .target(name: "Assistant",                  dependencies: ["Dragoman", "TTS", "STT", "TextTranslator"], path:"Assistant/Sources"),
        .target(name: "AudioSwitchboard",           dependencies: [],                                           path:"AudioSwitchboard/Sources"),
        .target(name: "AutomatedFetcher",           dependencies: [],                                           path:"AutomatedFetcher/Sources"),
        .target(name: "Dragoman",                   dependencies: ["TextTranslator", "Shout"],                  path:"Dragoman/Sources"),
        .target(name: "FFTPublisher",               dependencies: [],                                           path:"FFTPublisher/Sources"),
        .target(name: "Instagram",                  dependencies: ["AutomatedFetcher", "KeychainAccess"],       path:"Instagram/Sources"),
        .target(name: "Meals",                      dependencies: ["AutomatedFetcher", "SwiftSoup"],            path:"Meals/Sources"),
        .target(name: "PublicCalendar",             dependencies: ["AutomatedFetcher", "SwiftSoup"],            path:"PublicCalendar/Sources"),
        .target(name: "Shout",                      dependencies: [],                                           path:"Shout/Sources"),
        .target(name: "TTS",                        dependencies: ["AudioSwitchboard", "FFTPublisher"],         path:"TTS/Sources"),
        .target(name: "STT",                        dependencies: ["AudioSwitchboard", "FFTPublisher"],         path:"STT/Sources"),
        .target(name: "TextTranslator",             dependencies: [],                                           path:"TextTranslator/Sources"),
        .target(name: "Weather",                    dependencies: ["AutomatedFetcher"],                         path:"Weather/Sources"),
        .testTarget(name: "AppSettingsTests",       dependencies: ["AppSettings"],                              path:"AppSettings/Tests"),
        .testTarget(name: "AssistantTests",         dependencies: ["Assistant"],                                path:"Assistant/Tests"),
        .testTarget(name: "AudioSwitchboardTests",  dependencies: ["AudioSwitchboard"],                         path:"AudioSwitchboard/Tests"),
        .testTarget(name: "AutomatedFetcherTests",  dependencies: ["AutomatedFetcher"],                         path:"AutomatedFetcher/Tests"),
        .testTarget(name: "DragomanTests",          dependencies: ["Dragoman"],                                 path:"Dragoman/Tests"),
        .testTarget(name: "FFTPublisherTests",      dependencies: ["FFTPublisher"],                             path:"FFTPublisher/Tests"),
        .testTarget(name: "InstagramTests",         dependencies: ["Instagram"],                                path:"Instagram/Tests"),
        .testTarget(name: "MealsTests",             dependencies: ["Meals"],                                    path:"Meals/Tests"),
        .testTarget(name: "PublicCalendarTests",    dependencies: ["PublicCalendar"],                           path:"PublicCalendar/Tests"),
        .testTarget(name: "ShoutTests",             dependencies: ["Shout"],                                    path:"Shout/Tests"),
        .testTarget(name: "TTSTests",               dependencies: ["TTS"],                                      path:"TTS/Tests"),
        .testTarget(name: "STTTests",               dependencies: ["STT"],                                      path:"STT/Tests"),
        .testTarget(name: "TextTranslatorTests",    dependencies: ["TextTranslator"],                           path:"TextTranslator/Tests"),
        .testTarget(name: "WeatherTests",           dependencies: ["Weather"],                                  path:"Weather/Tests")
    ]
)

