import XCTest
@testable import AudioSwitchboard
import AVFoundation
import Combine

var cancellables = Set<AnyCancellable>()

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
            let audioFile = try AVAudioFile(forReading: url)
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


final class AudioSwitchboardTests: XCTestCase {
    func testShouldStop() {
        let expectation = XCTestExpectation(description: "testShouldStop")
        let audioSwitchboard = AudioSwitchboard()
        audioSwitchboard.claim(owner: "Owner 1").sink {
            XCTAssert(audioSwitchboard.currentOwner == "Owner 2")
            expectation.fulfill()
        }.store(in: &cancellables)
        audioSwitchboard.claim(owner: "Owner 2").sink {
            XCTFail("Should not trigger!")
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)
    }
    func testShouldNotStop() {
        let audioSwitchboard = AudioSwitchboard()
        audioSwitchboard.claim(owner: "Owner 1").sink {
            XCTFail("Should not trigger!")
        }.store(in: &cancellables)
        audioSwitchboard.stop(owner: "Owner 2")
        audioSwitchboard.stop(owner: "Owner 1")
    }
    func testPlay() {
        let expectation = XCTestExpectation(description: "Playing nonexisting sound")
            
        let audioSwitchboard = AudioSwitchboard()
        audioSwitchboard.claim(owner: "test").sink {
            expectation.fulfill()
        }.store(in: &cancellables)

        let myAudioLibrary = MyAudioLibrary(switchboard:audioSwitchboard)
        myAudioLibrary.play(URL(string:"file:///myaudiofile.wav")!)
        
        wait(for: [expectation], timeout: 10.0)
    }
}
