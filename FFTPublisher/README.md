# FFTPublisher

A fast fourtier transform publisher used for creating a visual representations of audio.

## FFTPublisher Usage

```swift

class MyAppState {
    /// You probably only need one in your app unless you plan to have multiple players/recorders that can be paused individually. 
    let fft = FFTPublisher()
    let audio:MyAudioClass
    init() {
        audio = MyAudioClass(fft:fft)
    }
}
class MyAudioClass {
    let fft:FFTPublisher
    init(fft:FFTPublisher {
        self.fft = fft 
    }
    func play() {
        /// code setting up an audio player/recorder of some kind
        /// ...
        
        /// get the rate
        let rate = Float(audioEngine.inputNode.inputFormat(forBus: 0).sampleRate)
        
        /// setup buffer tap
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: mainMixer.outputFormat(forBus: 0)) { [weak self] (buffer, _) in            
            /// the buffersize is ignorred by the installTap method but you can override it using an intrusive but effective way of increasing responsiveness of the fft. 
            buffer.frameLength = 512
            this.fft?.consume(buffer: buffer.audioBufferList, frames: buffer.frameLength, rate: rate)
        }
    }
    func pause() {
        /// don't call fft.end() if you pause, it will make more sense to the user if the magnitudes remain at the same place if the audio is paused.
    }
    func stop() {
        /// sends an empty output if that's what you want. It will make more sense to the user when the audio is "cut off" if the maginutes returns to 0.       
        fft.end()
    }
}
```

## FFTBarAudioVisualizer Usage

```swift
struct MyView : View {
    @ObservableObject fft:FFTPublisher
    var body: some View {
        FFTBarAudioVisualizer(fft:fft).frame(maxWidth:.infinity).frame(height: 100)
    }
}

```


## References
https://developer.apple.com/documentation/accelerate/fast_fourier_transforms
https://codereview.stackexchange.com/questions/154036/dft-discrete-fourier-transform-algorithm-in-swift

## TODO
- [ ] replace TempiFFT with https://github.com/christopherhelf/Swift-FFT-Example
- [x] code-documentation
- [ ] write tests
- [x] complete package documentation
