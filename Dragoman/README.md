# Dragoman

Dragoman is a localization and translation manager. It uses the built in support for .strings and the Bundle object in order to supply an app with translations

## Usage
To use dragoman to all it's potential you should make sure you have a translation service that implements the `TextTranslatorService` protocol. More information about text transaltion can be found at https://github.com/helsingborg-stad/spm-text-translator. There is a concrete implementation of the protocol in the https://github.com/helsingborg-stad/spm-ms-cognitive-services package called `MSTextTranslator`.

```swift
import Dragoman
import Combine

var cancellables = Set<AnyCancellable>()
func insert(cancellable:AnyCancellable?) {
    guard let cancellable = cancellable else { return }
    cancellables.insert(cancellable)
}
func remove(cancellable:AnyCancellable?) {
    guard let cancellable = cancellable else { return }
    cancellables.remove(cancellable)
}

class MyState : ObservableObject {
    let translator:MyTranslatorService
    let dragoman:Dragoman
    @Published var locale:Locale{
        didSet {
            dragoman.language = locale.languageCode ?? "sv"
        }
    }
    init() {
        let locale = Locale(identifier: "sv-SE")
        self.locale = locale
        self.translator = MyTranslatorService()
        dragoman = Dragoman(
            translationService: translator,
            language: locale.languageCode ?? "sv",
            supportedLanguages: ["sv","en"]
        )
        /// If you want to remove all previously translated strings you can run:
        /// dragoman.clean()
    }
    func translate(_ texts:[String]) {
        var p:AnyCancellable?
        
        p = dragoman.translate(texts, from: "sv").sink { completion in
            if case .failure(let error) = completion {
                debugPrint(error)
            }
            remove(cancellable:p)
        } receiveValue: {
            debugPrint("Done translating")
            remove(cancellable:p)
        }
        insert(cancellable:p)
    }
}
```

## Using with SwiftUI
Make the most out of dragoman using SwiftUI. You can either use `ATText("String")` or `Text(LocalizedStringKey(text), bundle: dragoman.bundle)` if you want to display strings from the dragoman bundle.
There's also the option of asking dragoman directly by calling the `dragoman.string(forKey:in)`.

```swift
@main struct TestDragomanApp: App {
    @StateObject var state = MyState()
    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .environmentObject(state)
                .environmentObject(state.dragoman)
                .environment(\.locale, state.locale)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state:MyState
    @EnvironmentObject var dragoman:Dragoman
    
    var text:String = "Nu testar vi den automatiska översättningen!"

    public var body: some View {
        VStack(spacing: 15) {
            Text("Current language: \(state.locale.languageCode!)").font(.title).padding(.bottom)
            HStack {
                Button.init("Change to EN") {
                    state.locale = Locale(identifier: "en-US")
                }.disabled(state.locale == Locale(identifier: "en-US"))
                Button.init("Change to SV") {
                    state.locale = Locale(identifier: "sv-SE")
                }.disabled(state.locale == Locale(identifier: "sv-SE"))
            }
            Button("Translate") {
                /// Checking if a string has been translated is not strictly nessesary.
                /// It is up to the implementor of TextTranslationService to check if a value is already translated or not.
                if dragoman.isTranslated(text) == false {
                    state.translate([text])
                }
            }
            Spacer()
            Text(LocalizedStringKey(text), bundle: dragoman.bundle)
            ATText(LocalizedStringKey(text))
            Spacer()
        }
    }
}
```

## TODO

- [x] code-documentation
- [x] write tests
- [x] complete package documentation
- [ ] Preparations for translations are made on the main queue, might become an issue. We whould make each translation into queuable and lock all files when preparing  
