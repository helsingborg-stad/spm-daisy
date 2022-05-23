# STT

STT provides a common interface for Speech To Text services implementing the `STTService` protocol.

## Usage
Right now there are two known public implementations of `STTService`.

|Name|Package|
|:--|:--|
|AppleSTT|included in the framework|


```swift
import AudioSwitchboard
import STT
import Combine

var cancellables = Set<AnyCancellable>()

class MyState {
    let switchboard = AudioSwitchboard() 
    let stt:STT
    init() {
        stt = STT(service: AppleSTT(audioSwitchboard: switchboard))
        stt.locale = Locale(identifier: "en_US")
        stt.contextualStrings = ["MySpecialWord"]
        stt.$status.sink { status in 
            debugPrint(status)
        }.store(in:&cancellables)
        stt.results.sink { result in 
            debugPrint(result.string)
        }.store(in:&cancellables)
        
        stt.failures.sink { error in 
            debugPrint(error)
        }.store(in:&cancellables)
    }
    func startListening() {
        stt.start()
    }
}
```

## SwiftUI

```swift
struct ContentView : View {
    @ObservedObject var stt:STT
    @State var recognizedString:String = ""
    var body: some View {
        VStack {
            Text(recognizedString)
            Spacer()
            Button {
                if stt.status == .recording {
                    stt.done()
                } else {
                    recognizedString = ""
                    stt.start()
                }
            } label: {
                Text(stt.status == .idle ? "Start" : "Stop")
            }
            .disabled(!(stt.status == .recording || stt.status == .idle) || stt.status == .unavailable)
        }.onReceive(stt.results) { results in
            recognizedString = results.string
        }
    }
}
```

## TODO

- [ ] add list of available services
- [x] code-documentation
- [ ] write tests
- [x] complete package documentation
