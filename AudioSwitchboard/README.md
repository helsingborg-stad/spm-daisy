# AudioSwitchboard

This is a support package for other libraries that uses audio servies in iOS. The reason for it's existence is to make it a little easier to manage multiple audio services for a single application without causing crashes or unexpected behaviour when using the AVAudioEngine. 

- Manages start, stop and AVAudioEngine resets
- Manages/Activates and monitors AVAudioSession 

## Usage

```swift
import AVFoundation
import Combine
import AudioSwitchboard

class AppState {
    let audioSwitchboard = AudioSwitchboard()
    let myAudioLibrary:MyAudioLibrary
    init() {
        myAudioLibrary = MyAudioLibrary(switchboard:audioSwitchboard)
    }
    func play() {
        myAudioLibrary.play(URL(string:"file:///myaudiofile.wav")!)
    }
}
class MyAudioLibrary {
    private var cancellables = Set<AnyCancellable>()
    private let switchboard:AudioSwitchboard
    private let player = AVAudioPlayerNode()
    init(switchboard:AudioSwitchboard) {
        self.switchboard = switchboard
    }
    func stop() {
        player.stop()
        switchboard.stop(owner: "MyAudioLibrary")
    }
    func play(_ url:URL) {
        switchboard.claim(owner: "MyAudioLibrary").sink {
            self.stop()
        }.store(in: &cancellables)
        do {
            let audioEngine = switchboard.audioEngine  
            let audioFile = let audioFile = try AVAudioFile(forReading: url)
            let mainMixer = audioEngine.mainMixerNode
            
            audioEngine.attach(player)
            audioEngine.connect(player, to: mainMixer, format: mainMixer.outputFormat(forBus: 0))
            
            player.play()
            player.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { (_) in
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        } catch {
            debugPrint(error)
            self.stop()
        }
    }
}
```
