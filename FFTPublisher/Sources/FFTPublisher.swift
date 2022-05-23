import Foundation
import AVKit
import Combine
import Accelerate

// https://stackoverflow.com/questions/60120842/how-to-use-apples-accelerate-framework-in-swift-in-order-to-compute-the-fft-of

///  A fast fourtier transform publisher used creating visual representations of audio.
public class FFTPublisher: ObservableObject {
    /// Average magnitude publisher
    public let averageMagnitude: AnyPublisher<CGFloat, Never>
    /// Magnitude publisher
    public let magnitudes: AnyPublisher<[CGFloat], Never>
    /// Maximum decibel to process
    public var maxDB: Float = 64.0
    /// Maximum decibel to process
    public var minDB: Float = -28.0
    /// The difference betqeen maxDb and minDb
    public var headroom: Float {
        maxDB - minDB
    }
    /// The number of bands to process
    public var bands: Int = Int(150)
    /// The mininum frequency to process
    public var minFrequency: Float = 125
    /// The maximum frequency to process
    public var maxFrequency: Float = 8000
    /// Indicates whether or not the isntance is disabled
    public var disabled: Bool = false
    /// The average magnitude subject
    private let averageMagnitudeSubject: PassthroughSubject<CGFloat, Never> = .init()
    /// The magnitude subject
    private let magnitudesSubject: PassthroughSubject<[CGFloat], Never> = .init()
    /// Initializes a new instance
    public init() {
        averageMagnitude = averageMagnitudeSubject.eraseToAnyPublisher()
        magnitudes = magnitudesSubject.eraseToAnyPublisher()
    }
    /// Send empty array to signal an end of transmission
    public func end() {
        self.magnitudesSubject.send(Array(repeating: 0, count: self.bands))
        self.averageMagnitudeSubject.send(0)
    }
    
    /// Consumes a buffer and publishes the result to the averageMagnitude and magnitude publishers
    /// - Parameters:
    ///   - buffer: buffer to be read
    ///   - frames: number of frames
    ///   - rate: the audio rate
    /// - Note: Requires float audio format
    public func consume(buffer: UnsafePointer<AudioBufferList>, frames: AVAudioFrameCount, rate: Float) {
        if disabled {
            return
        }
        guard let ptr = buffer.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }
        var samples = [Float]()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(frames)))
        let fft = TempiFFT(withSize: samples.count, sampleRate: rate)
        fft.windowType = TempiFFTWindowType.hanning
        fft.fftForward(samples)
        fft.calculateLinearBands(minFrequency: minFrequency, maxFrequency: maxFrequency, numberOfBands: bands)
        let avg = CGFloat(convert(fft.averageMagnitude(lowFreq: self.minFrequency, highFreq: self.maxFrequency)))
        var scales: [CGFloat] = []
        let count = fft.numberOfBands

        for i in 0..<count {
            scales.insert(CGFloat(convert(fft.magnitudeAtBand(i))), at: 0)
        }
        self.averageMagnitudeSubject.send(avg)
        self.magnitudesSubject.send(scales)
    }
    /// Converting magnitude to decibels (positive value)
    /// - Parameter magnitude: the magnitude
    /// - Returns: the abs(decibel), always larger than 0
    private func convert(_ magnitude: Float) -> Float {
        var magnitudeDB = TempiFFT.toDB(magnitude)
        magnitudeDB = max(0, magnitudeDB + abs(minDB))
        return min(1.0, magnitudeDB / headroom)
    }
}
