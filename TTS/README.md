# TTS

TTS provides a common interface for Text To Speech services implementing the `TTSService` protocol.

## Usage 
The TTS instance is easy enough to utilize. There are a number of publishers to indicate the currenty service status but the most effective way of keeping track of what's going on is to subscribe the `TTSUtterance` publishers. 

Right now there are two known public implementations of `TTSService`.

|Name|Package|
|:--|:--|
|AppleTTS|included in the framework|
|MSTTS| included in https://github.com/helsingborg-stad/spm-ms-cognitive-services|

```swift
import AudioSwitchboard
import TTS

class MyState {
    let switchboard = AudioSwitchboard()
    let tts:TTS
    var cancellables = Set<AnyCancellable>()

    init() {
        tts = TTS(service: AppleTTS(audioSwitchBoard: switchboard))
    }
    func play(string:String) -> TTSUtterance {
        let u = TTSUtterance(string, locale: Locale(identifier:"en-US"))
        u.statusPublisher.sink { status in
            // you can use the status to toggle a button between play, pause or stop 
            debugPrint(status)
        }.store(in: &cancellables)
        u.wordBoundaryPublisher.sink { boundary in
            // use this if you want to display the currently spoken word, 
            // either by its own or perhaps using an atributed string
            debugPrint(boundary.string)
        }.store(in: &cancellables)

        tts.play(u)
        return u
    }
}
```

## SwiftUI

```swift
struct ContentView: View {
    var utterance:TTSUtterance
    @State var color:Color = .white
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 20,height:20)
            Text(utterance.speechString)    
        }
        .onRecieve(utterance.statusPublisher) { status in 
            if status == .failed {
                color = .red
            } else if status == .speaking {
                color = .green
            } else if status == .queued {
                color = .orange
            } else if status == .speaking {
                color = .white
            }
        }
        .onRecieve(utterance.wordBoundaryPublisher) { boundary in
            // An example on how to set up an attributed string using the word boundary:
            // 
            // let range = NSRange(boundary.range, in: speechString)
            // let attributedString = NSMutableAttributedString(string: speechString)
            // attributedString.addAttributes([.underlineStyle: NSUnderlineStyle.byWord], range: range)
            // Text(attributedString)
        }
    } 
}
```

## TODO

- [x] add list of available services
- [x] add support for multiple services
- [x] code-documentation
- [x] write tests
- [x] complete package documentation


