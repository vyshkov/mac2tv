import Foundation

public enum AudioHelper {
    public static func findFFprobe() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static func probeAudioTracks(for videoURL: URL) async -> [AudioTrack] {
        var tracks: [AudioTrack] = []

        // 1. Probe embedded audio streams via ffprobe
        if let ffprobePath = findFFprobe() {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ffprobePath)
            task.arguments = [
                "-v", "error",
                "-select_streams", "a",
                "-show_entries", "stream=index,codec_name,channels,channel_layout:stream_disposition=default:stream_tags=language,title",
                "-of", "json",
                videoURL.path
            ]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let streams = json["streams"] as? [[String: Any]] {
                    for stream in streams {
                        if let index = stream["index"] as? Int {
                            let codecName = stream["codec_name"] as? String
                            let channels = stream["channels"] as? Int
                            let channelLayout = stream["channel_layout"] as? String

                            let tags = stream["tags"] as? [String: Any]
                            let lang = tags?["language"] as? String
                            let title = tags?["title"] as? String ?? ""

                            let disposition = stream["disposition"] as? [String: Any]
                            let isDefault = (disposition?["default"] as? Int == 1)

                            let track = AudioTrack(
                                id: "stream_\(index)",
                                title: title,
                                language: lang,
                                streamIndex: index,
                                codec: codecName,
                                channels: channels,
                                channelLayout: channelLayout,
                                isDefault: isDefault,
                                externalURL: nil
                            )
                            tracks.append(track)
                        }
                    }
                }
            } catch {
                NSLog("[AudioHelper] ffprobe error: %@", error.localizedDescription)
            }
        }

        // 2. Discover companion external audio files (.m4a, .aac, .ac3, .mp3, etc.) in same directory
        let dir = videoURL.deletingLastPathComponent()
        let videoBaseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        let audioExtensions = ["m4a", "aac", "ac3", "eac3", "dts", "mp3", "flac", "wav", "mka"]

        if let enumerator = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in enumerator {
                let ext = file.pathExtension.lowercased()
                if audioExtensions.contains(ext) {
                    let audioBase = file.deletingPathExtension().lastPathComponent.lowercased()
                    if audioBase.starts(with: videoBaseName) || enumerator.count < 10 {
                        let diff = audioBase.replacingOccurrences(of: videoBaseName, with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
                        let title = diff.isEmpty ? file.lastPathComponent : diff.uppercased()

                        let externalTrack = AudioTrack(
                            id: "file_\(file.path)",
                            title: title,
                            language: diff.isEmpty ? nil : diff,
                            streamIndex: nil,
                            codec: ext,
                            channels: nil,
                            channelLayout: nil,
                            isDefault: false,
                            externalURL: file
                        )

                        if !tracks.contains(where: { $0.id == externalTrack.id }) {
                            tracks.append(externalTrack)
                        }
                    }
                }
            }
        }

        return tracks
    }

    public static func defaultTrack(in allTracks: [AudioTrack]) -> AudioTrack? {
        if let explicit = allTracks.first(where: { $0.externalURL == nil && $0.isDefault }) {
            return explicit
        }
        return allTracks.first(where: { $0.externalURL == nil }) ?? allTracks.first
    }

    public static func isDefaultOrFirstTrack(_ track: AudioTrack, in allTracks: [AudioTrack]) -> Bool {
        if track.externalURL != nil { return false }
        guard let def = defaultTrack(in: allTracks) else { return false }
        return track.id == def.id
    }

    public static func prepareAudioStream(selectedTrack: AudioTrack, for videoURL: URL, allTracks: [AudioTrack]) async throws -> URL {
        // If single track or already the default first track, stream video directly without remuxing!
        if isDefaultOrFirstTrack(selectedTrack, in: allTracks) {
            return videoURL
        }

        guard let ffmpegPath = findFFmpeg() else {
            throw NSError(domain: "AudioHelper", code: 404, userInfo: [NSLocalizedDescriptionKey: "FFmpeg is required for audio track switching."])
        }

        let safeVideoName = videoURL.deletingPathExtension().lastPathComponent.prefix(20)
        let trackId = selectedTrack.streamIndex.map { "\($0)" } ?? "ext_\(abs(selectedTrack.id.hashValue))"
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mkvairplay_\(safeVideoName)_audio_\(trackId).mkv")

        // If track already remuxed and valid, reuse immediately
        if FileManager.default.fileExists(atPath: outputURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           (attrs[.size] as? Int64 ?? 0) > 0 {
            return outputURL
        }

        let tempURL = outputURL.deletingPathExtension().appendingPathExtension("tmp.mkv")
        try? FileManager.default.removeItem(at: tempURL)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpegPath)
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        task.standardError = errPipe

        if let external = selectedTrack.externalURL {
            // Mux primary video from source with external audio file
            task.arguments = [
                "-nostdin",
                "-y",
                "-i", videoURL.path,
                "-i", external.path,
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-c", "copy",
                "-f", "matroska",
                tempURL.path
            ]
        } else if let streamIndex = selectedTrack.streamIndex {
            // Remux primary video with selected embedded audio stream to be the sole/first audio stream
            task.arguments = [
                "-nostdin",
                "-y",
                "-i", videoURL.path,
                "-map", "0:v:0",
                "-map", "0:\(streamIndex)",
                "-c", "copy",
                "-f", "matroska",
                tempURL.path
            ]
        } else {
            return videoURL
        }

        try task.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempURL.path) else {
            try? FileManager.default.removeItem(at: tempURL)
            let errString = String(data: errData, encoding: .utf8) ?? ""
            NSLog("[AudioHelper] ffmpeg failed with status %d: %@", task.terminationStatus, errString)
            throw NSError(domain: "AudioHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio track (exit code \(task.terminationStatus)): \(errString)"])
        }

        _ = try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: tempURL, to: outputURL)

        return outputURL
    }

    public static func cleanupTempFiles() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.starts(with: "mkvairplay_") && file.lastPathComponent.contains("_audio_") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
