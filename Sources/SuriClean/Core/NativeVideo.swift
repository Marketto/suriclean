import Foundation
import AVFoundation
import VideoToolbox

/// Videos on the Mac (docs/SCHIACCIA.md): Monterey's WebKit can't encode video, so Schiaccia's numbers drive
/// macOS's own encoder. HEVC when the Mac has a hardware HEVC encoder, otherwise H.264 (hardware on every Mac).
/// Same frame rate; Martellata fits the video in Schiaccia's 1080p box; the result is kept only if it is
/// below CONFIG.video.fileKeep (90%) of the original; HDR videos are left alone.
enum NativeVideo {
    struct Outcome {
        var status: String          // "done" | "same" | "err"
        var note: String = ""
        var out: URL? = nil         // temp file next to the original (only with "done")
    }

    /// A 2015 MacBook Air has no HEVC hardware encoder: the software one would take ages, so H.264 there.
    static let hevcHardware: Bool = {
        var session: VTCompressionSession?
        let spec = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue] as CFDictionary
        let st = VTCompressionSessionCreate(allocator: nil, width: 1280, height: 720, codecType: kCMVideoCodecType_HEVC,
                                            encoderSpecification: spec, imageBufferAttributes: nil,
                                            compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                            compressionSessionOut: &session)
        if let s = session { VTCompressionSessionInvalidate(s) }
        return st == noErr && session != nil
    }()

    private final class Pump {
        var finished = false
    }

    private static func fourCC(_ c: FourCharCode) -> String {
        let b = [UInt8((c >> 24) & 255), UInt8((c >> 16) & 255), UInt8((c >> 8) & 255), UInt8(c & 255)]
        return String(bytes: b, encoding: .ascii) ?? ""
    }

    static func squeeze(_ src: URL, level: SqueezeLevel,
                        progress: @escaping (Double) -> Void, cancelled: @escaping () -> Bool) async -> Outcome {
        let tu = Squeeze.tuning
        let asset = AVURLAsset(url: src)
        guard let vt = asset.tracks(withMediaType: .video).first else { return Outcome(status: "err", note: "noVideo") }
        if vt.hasMediaCharacteristic(.containsHDRVideo) { return Outcome(status: "same", note: "hdr") }

        let nat = vt.naturalSize
        let w = Double(abs(nat.width)), h = Double(abs(nat.height))
        guard w >= 16, h >= 16 else { return Outcome(status: "err", note: "unreadable") }
        let fps = Double(vt.nominalFrameRate > 0 ? vt.nominalFrameRate : 30)
        let srcRate = Double(vt.estimatedDataRate)
        let dur = max(0.1, CMTimeGetSeconds(asset.duration))
        var codec = ""
        if let f = vt.formatDescriptions.first { codec = fourCC(CMFormatDescriptionGetMediaSubType(f as! CMFormatDescription)) }
        let fam = Squeeze.family(fourCC: codec)
        let target = Squeeze.targetSize(level: level, w: w, h: h)
        let ow = target.map { $0.0 } ?? Int(w / 2) * 2
        let oh = target.map { $0.1 } ?? Int(h / 2) * 2
        let hevc = hevcHardware
        guard let rate = Squeeze.videoBitrate(level: level, family: fam, srcBitrate: srcRate, srcW: w, srcH: h,
                                              outW: Double(ow), outH: Double(oh), fps: fps, outHEVC: hevc) else {
            return Outcome(status: "same", note: "noGainV")
        }
        let origSize = Double(SqueezeFiles.size(src))

        // audio: copied as it is, or AAC (CONFIG.video.aacBitrate) when it is PCM or very heavy (R-VID-08)
        let at = asset.tracks(withMediaType: .audio).first
        var audioPCM = false, audioRate = 0.0, channels = 2, sampleRate = 48_000.0
        if let a = at {
            audioRate = Double(a.estimatedDataRate)
            if let f = a.formatDescriptions.first {
                let fd = f as! CMFormatDescription
                audioPCM = CMFormatDescriptionGetMediaSubType(fd) == kAudioFormatLinearPCM
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                    channels = Int(asbd.mChannelsPerFrame)
                    if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
                }
            }
        }
        let heavyAudio = audioRate > 256_000 && (audioRate - tu.aacBitrate) * dur / 8 >= tu.audioGain * origSize
        let reencodeAudio = audioPCM || heavyAudio
        let aRate = at == nil ? 0 : (reencodeAudio ? tu.aacBitrate : audioRate)
        if (rate + aRate) * dur / 8 >= tu.fileKeep * origSize { return Outcome(status: "same", note: "noGainV") }

        let ext = src.pathExtension.lowercased()
        let fileType: AVFileType = ext == "mov" ? .mov : (ext == "m4v" ? .m4v : .mp4)
        let out = SqueezeFiles.tempURL(for: src)
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: out, fileType: fileType) else {
            return Outcome(status: "err", note: "unreadable")
        }
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = asset.metadata                       // date, place, camera

        let vOut = AVAssetReaderTrackOutput(track: vt, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        vOut.alwaysCopiesSampleData = false
        var comp: [String: Any] = [
            AVVideoAverageBitRateKey: Int(rate),
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int((fps * 2).rounded()))
        ]
        if !hevc { comp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        var vSettings: [String: Any] = [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: ow,
            AVVideoHeightKey: oh,
            AVVideoCompressionPropertiesKey: comp
        ]
        if target != nil { vSettings[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspect }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = false
        vIn.transform = vt.preferredTransform
        guard reader.canAdd(vOut), writer.canAdd(vIn) else { return Outcome(status: "err", note: "unreadable") }
        reader.add(vOut)
        writer.add(vIn)

        var aOut: AVAssetReaderTrackOutput?
        var aIn: AVAssetWriterInput?
        if let a = at {
            if !reencodeAudio, let f = a.formatDescriptions.first {
                let o = AVAssetReaderTrackOutput(track: a, outputSettings: nil)
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: (f as! CMFormatDescription))
                i.expectsMediaDataInRealTime = false
                if reader.canAdd(o) && writer.canAdd(i) { reader.add(o); writer.add(i); aOut = o; aIn = i }
            }
            if aIn == nil {
                let ch = max(1, min(2, channels))
                let sr = sampleRate > 48_000 ? 48_000.0 : sampleRate
                let o = AVAssetReaderTrackOutput(track: a, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: ch, AVSampleRateKey: sr
                ])
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: ch, AVSampleRateKey: sr,
                    AVEncoderBitRateKey: Int(tu.aacBitrate)
                ])
                i.expectsMediaDataInRealTime = false
                if reader.canAdd(o) && writer.canAdd(i) { reader.add(o); writer.add(i); aOut = o; aIn = i }
            }
        }

        func fail(_ note: String) -> Outcome {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: out)
            return Outcome(status: "err", note: note)
        }

        guard writer.startWriting() else { return fail("unreadable") }
        guard reader.startReading() else { return fail("unreadable") }
        writer.startSession(atSourceTime: vt.timeRange.start)

        let group = DispatchGroup()
        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderTrackOutput, label: String, video: Bool) {
            let state = Pump()
            let q = DispatchQueue(label: "suri.squeeze.\(label)")
            group.enter()
            input.requestMediaDataWhenReady(on: q) {
                while input.isReadyForMoreMediaData && !state.finished {
                    var stop = cancelled() || reader.status != .reading
                    if !stop {
                        if let sb = output.copyNextSampleBuffer() {
                            if video {
                                let s = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                                if s.isFinite { progress(min(0.99, max(0, s / dur))) }
                            }
                            if !input.append(sb) { stop = true }
                        } else {
                            stop = true
                        }
                    }
                    if stop {
                        state.finished = true
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }
        pump(vIn, vOut, label: "video", video: true)
        if let i = aIn, let o = aOut { pump(i, o, label: "audio", video: false) }

        // wait for both tracks, but never get stuck: cancelling or a failed reader/writer ends the wait
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                while group.wait(timeout: .now() + 0.3) == .timedOut {
                    if cancelled() || reader.status == .failed || writer.status == .failed { break }
                }
                c.resume()
            }
        }

        if cancelled() { return fail("aborted") }
        if reader.status == .failed || writer.status == .failed { return fail("unreadable") }
        await writer.finishWriting()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: out)
            return Outcome(status: "err", note: "unreadable")
        }
        progress(1)
        let newSize = Double(SqueezeFiles.size(out))
        if newSize <= 0 || newSize >= tu.fileKeep * origSize {
            try? FileManager.default.removeItem(at: out)
            return Outcome(status: "same", note: "noGainV")
        }
        return Outcome(status: "done", out: out)
    }
}
