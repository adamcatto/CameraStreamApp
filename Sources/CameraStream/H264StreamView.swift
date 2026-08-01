import AppKit
import AVFoundation
import Network
import SwiftUI

struct StreamEndpoint: Identifiable, Hashable {
    let id: UUID
    var name: String
    let host: String
    let port: Int
}

struct H264StreamView: NSViewRepresentable {
    let endpoint: StreamEndpoint

    func makeCoordinator() -> Coordinator { Coordinator(endpoint: endpoint) }
    func makeNSView(context: Context) -> VideoView {
        let view = VideoView()
        context.coordinator.player.attach(to: view)
        context.coordinator.player.connect()
        return view
    }
    func updateNSView(_ nsView: VideoView, context: Context) {}
    static func dismantleNSView(_ nsView: VideoView, coordinator: Coordinator) { coordinator.player.disconnect() }

    final class Coordinator {
        let player: H264TCPPlayer
        init(endpoint: StreamEndpoint) { player = H264TCPPlayer(host: endpoint.host, port: endpoint.port) }
    }
}

final class VideoView: NSView {
    override func makeBackingLayer() -> CALayer { AVSampleBufferDisplayLayer() }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Receives the Annex-B H.264 stream emitted by rpicam-vid/libcamera-vid and
/// feeds access units directly to AVSampleBufferDisplayLayer.
final class H264TCPPlayer: @unchecked Sendable {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "edu.mountsinai.camerastream.h264")
    private var connection: NWConnection?
    private weak var view: VideoView?
    private var bytes = Data()
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var frameNumber: Int64 = 0

    init(host: String, port: Int) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: UInt16(port))!
    }

    func attach(to view: VideoView) { self.view = view }
    func connect() {
        guard connection == nil else { return }
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.disconnect() }
        }
        connection.start(queue: queue)
        receive()
    }
    func disconnect() {
        connection?.cancel()
        connection = nil
        bytes.removeAll(keepingCapacity: false)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.bytes.append(data); self.consumeAnnexB() }
            if !complete && error == nil { self.receive() }
        }
    }

    private func consumeAnnexB() {
        guard let first = startCode(in: bytes, from: 0) else { return }
        if first.lowerBound > 0 { bytes.removeSubrange(0..<first.lowerBound) }
        while let leading = startCode(in: bytes, from: 0),
              let next = startCode(in: bytes, from: leading.upperBound) {
            let nal = bytes.subdata(in: leading.upperBound..<next.lowerBound)
            bytes.removeSubrange(0..<next.lowerBound)
            consumeNAL(nal)
        }
    }

    private func startCode(in data: Data, from offset: Int) -> Range<Int>? {
        let values = [UInt8](data)
        guard values.count >= offset + 3 else { return nil }
        for index in offset..<(values.count - 2) where values[index] == 0 && values[index + 1] == 0 {
            if values[index + 2] == 1 { return (index..<(index + 3)) }
            if index + 3 < values.count && values[index + 2] == 0 && values[index + 3] == 1 { return (index..<(index + 4)) }
        }
        return nil
    }

    private func consumeNAL(_ nal: Data) {
        guard let header = nal.first else { return }
        switch header & 0x1F {
        case 7: sps = nal; createFormatDescription()
        case 8: pps = nal; createFormatDescription()
        case 1, 5: enqueue(nal)
        default: break
        }
    }

    private func createFormatDescription() {
        guard let sps, let pps else { return }
        sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                var parameterSets: [UnsafePointer<UInt8>] = [spsBuffer.bindMemory(to: UInt8.self).baseAddress!, ppsBuffer.bindMemory(to: UInt8.self).baseAddress!]
                var sizes = [sps.count, pps.count]
                var description: CMVideoFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: &parameterSets, parameterSetSizes: &sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                if status == noErr { formatDescription = description }
            }
        }
    }

    private func enqueue(_ nal: Data) {
        guard let formatDescription else { return }
        var length = UInt32(nal.count).bigEndian
        var avcc = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        avcc.append(nal)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block,
              avcc.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count) }) == kCMBlockBufferNoErr else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: frameNumber, timescale: 30), decodeTimeStamp: .invalid)
        frameNumber += 1
        var size = avcc.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return }
        DispatchQueue.main.async { [weak self] in self?.view?.displayLayer.enqueue(sample) }
    }
}
