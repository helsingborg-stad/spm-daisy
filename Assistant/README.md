# Assistant
A package that manages voice commands, text to speech, translations and localized strings. It also makes sure that TTS and STT is not interfering with each other, especially important when using a shared device without a headset.

## Text translations
To make the most out of the assistant you might want to have a look at [TextTranslator](https://github.com/helsingborg-stad/spm-text-translator) framework.

## Voice commands from file
The the moment the `Assistant` is using regular expressions to parse and trigger events based on STT output. First you need to create an enum that implements the `NLKeyDefinition`
```swift
import Foundation
import Assistant
enum VoiceCommands : String, NLKeyDefinition {
    var description: String {
        return self.rawValue
    }
    case leave
    case home
    case weather
    case food
    case calendar
    case instagram
}
```
After that you can create a plist file (default name is `VoiceCommands.plist`, however this is configurable) to populate the assistant voicecommand database (You can create the database in code aswell, for more details look at the code documentation for `Assistant.Settings`).

You need to add the file to your target and localize it to the languages that your app supports.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>weather</key>
    <array>
        <string>weather</string>
        <string>cold outside</string>
        <string>hot outside</string>
        <string>temperature</string>
        <string>freezing</string>
    </array>
</dict>
</plist>
```

Now you're ready to create your assistant

```swift
import Combine
import AudioSwitchboard
import Assistant
import STT
import TTS
/// Create a typealias you can use throughout your app, it's easier than declaring the generic over and over again.
typealias MyAssistant = Assistant<VoiceCommands>

class AppState : ObservableObject {
    let assistant: MyAssistant
    let switchboard = AudioSwitchboard()
    init() {
        assistant = MyAssistant(
            settings: .init(
                sttService: AppleSTT(audioSwitchboard: switchboard),
                ttsServices: AppleTTS(audioSwitchBoard: switchboard),
                translator: nil // https://github.com/helsingborg-stad/spm-text-translator
            )
        )
        /// If you have added a translator you can use the handy `assistant.translate()` methods
    }
}
```

## SwiftUI
The assistant works great with SwiftUI, it even has its own view container that exposes it's functions as environment values and objects.

```swift
@main struct MyAssistantApp: App {
    @StateObject var appState = AppState()
    var body: some Scene {
        WindowGroup {
            appState.assistant.containerView {
                ContentView()
            }
        }
    }
}
struct ContentView: View {
    @EnvironmentObject var assistant:MyAssistant
    @State var recognizedCommand:String = ""
    var body: some View {
        VStack {}
            Text(recognizedCommand)
        }
        .onReceive(assistant.listen(for: [.weather])) { results in
            /// in case you're listening to multiple commands

            /// if results.contains(.weather) {} 
            /// else if results.contains(.food) {}
            recognizedCommand = "I don't have a weather service installed. Pop your head outside to know more"
        }
        .onAppear {
            assistant.speak("Say something related to weather")
        }
    }
}
```

### Previews
When running previews you probably want to turn off certain features to speed up compilation.
The best way of doing that is to create a reusable view and instance of your assistant. This way you can be in control of what is being compiled and read into memory. Remember, statics are your enemy coding for SwiftUI.

The preview state might be overkill depending in how you implement the rest of the app. You can also make sure that your state listes for preview simulators using `ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"`
```swift
struct PreviewState {
    static let instance = PreviewState()
    let switchboard = AudioSwitchboard()
    let assistant:MyAssistant
    init() {
        assistant = MyAssistant(
            settings: .init(
                sttService: AppleSTT(audioSwitchboard: switchboard),
                ttsServices: AppleTTS(audioSwitchBoard: switchboard),
                translator: nil
            )
        )
        assistant.disabled = true
    }
}
struct MyAssistantPreviewContainer<Content: View>: View {
    let content: (PreviewState) -> Content
    init(@ViewBuilder content: @escaping (PreviewState) -> Content) {
        self.content = content
    }
    var body: some View {
        Group { 
            PreviewState.instance.assistant.containerView {
                content(PreviewState.instance)
            }
        }
        .preferredColorScheme(.dark)
    }
}
static var previews: some View {
    MyAssistantPreviewContainer { state in
        ContentView()
    }
}
```

## TODO
- [ ] add taskqueue support for other media such ans audio and video?
- [ ] replace/add voice command keys using a trained (or untrained?) ml model
- [x] code documentation
- [x] package documentation
- [x] write tests

