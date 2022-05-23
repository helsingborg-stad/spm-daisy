import SwiftUI

/// A component to visualize (horizontally) magnitude output from an FFTPublisher.
public struct FFTBarAudioVisualizer: View {
    @Environment(\.displayScale) var displayScale: CGFloat
    @ObservedObject public var fft: FFTPublisher
    @State var scales: [CGFloat] = []
    public var verticalAlignment: VerticalAlignment = .bottom
    public var color: Color = Color.accentColor
    public var frameAlignment: Alignment {
        if verticalAlignment == .bottom {
            return .bottom
        } else if verticalAlignment == .top {
            return .top
        } else if verticalAlignment == .center {
            return .center
        }
        return .center
    }
    public init(fft: FFTPublisher, verticalAlignment: VerticalAlignment = .bottom, color: Color = Color.accentColor) {
        self.fft = fft
        self.verticalAlignment = verticalAlignment
        self.color = color
    }
    public var body: some View {
        GeometryReader { proxy in
            HStack(alignment: verticalAlignment, spacing: 0) {
                if !scales.isEmpty {
                    ForEach(Array(scales.enumerated()), id: \.offset) { index, element in
                        Rectangle()
                            .fill(color)
                            .frame(width: 1/displayScale, height: proxy.size.height/2 * element)
                            .background(Color.clear)
                            .frame(maxWidth: .infinity)
                            .id("id-\(index)")
                    }
                } else {
                    EmptyView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        }.onReceive(fft.magnitudes.receive(on: DispatchQueue.main)) { scales in
            withAnimation(Animation.easeOut(duration: 0.1)) {
                self.scales = scales
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
/// A component to visualize (vertically) magnitude output from an FFTPublisher
public struct FFTVerticalBarAudioVisualizer: View {
    @Environment(\.displayScale) var displayScale: CGFloat
    @ObservedObject public var fft: FFTPublisher
    @State var scales: [CGFloat] = []
    public var horizontalAlignment: HorizontalAlignment = .leading
    public var color: Color = Color.accentColor
    public var frameAlignment: Alignment {
        if horizontalAlignment == .leading {
            return .leading
        } else if horizontalAlignment == .trailing {
            return .trailing
        } else if horizontalAlignment == .center {
            return .center
        }
        return .center
    }
    public init(fft: FFTPublisher, horizontalAlignment: HorizontalAlignment = .leading, color: Color = Color.accentColor) {
        self.fft = fft
        self.horizontalAlignment = horizontalAlignment
        self.color = color
    }
    public var body: some View {
        GeometryReader { proxy in
            VStack(alignment: horizontalAlignment, spacing: 0) {
                if !scales.isEmpty {
                    ForEach(Array(scales.enumerated()), id: \.offset) { index, element in
                        Rectangle()
                            .fill(color)
                            .frame(width: proxy.size.width/2 * element, height: 1/displayScale)
                            .background(Color.clear)
                            .frame(maxHeight: .infinity)
                            .id("id-\(index)")
                    }
                } else {
                    EmptyView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        }.onReceive(fft.magnitudes.receive(on: DispatchQueue.main)) { scales in
            withAnimation(Animation.easeOut(duration: 0.1)) {
                self.scales = scales
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
public struct FFTBarAudioVisualizer_Previews: PreviewProvider {
    public static var previews: some View {
        VStack {
            FFTBarAudioVisualizer(fft: FFTPublisher())
        }
    }
}
