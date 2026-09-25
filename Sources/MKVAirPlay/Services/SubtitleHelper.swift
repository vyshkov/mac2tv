import Foundation

public enum SubtitleHelper {
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

    public static func probeSubtitleTracks(for videoURL: URL) async -> [SubtitleTrack] {
        var tracks: [SubtitleTrack] = [SubtitleTrack.off]

        // 1. Probe embedded streams via ffprobe
        if let ffprobePath = findFFprobe() {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ffprobePath)
            task.arguments = [
                "-v", "error",
                "-select_streams", "s",
                "-show_entries", "stream=index,codec_name:stream_tags=language,title",
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
                            let tags = stream["tags"] as? [String: Any]
                            let lang = tags?["language"] as? String
                            let title = tags?["title"] as? String ?? ""

                            let track = SubtitleTrack(
                                id: "stream_\(index)",
                                title: title,
                                language: lang,
                                streamIndex: index,
                                externalURL: nil
                            )
                            tracks.append(track)
                        }
                    }
                }
            } catch {
                NSLog("[SubtitleHelper] ffprobe error: %@", error.localizedDescription)
            }
        }

        // 2. Discover companion external subtitle files (.srt, .vtt) in same directory
        let dir = videoURL.deletingLastPathComponent()
        let videoBaseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()

        if let enumerator = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in enumerator {
                let ext = file.pathExtension.lowercased()
                if ext == "srt" || ext == "vtt" {
                    let subBase = file.deletingPathExtension().lastPathComponent.lowercased()
                    // Match if same prefix (e.g. Movie.srt, Movie.en.srt, Movie.Spanish.srt)
                    if subBase.starts(with: videoBaseName) || enumerator.count < 10 {
                        let diff = subBase.replacingOccurrences(of: videoBaseName, with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
                        let title = diff.isEmpty ? file.lastPathComponent : diff.uppercased()

                        let externalTrack = SubtitleTrack(
                            id: "file_\(file.path)",
                            title: title,
                            language: diff.isEmpty ? nil : diff,
                            streamIndex: nil,
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

    public static func prepareSubtitleFile(track: SubtitleTrack, for videoURL: URL) async throws -> URL? {
        if track.isOff {
            return nil
        }

        if let external = track.externalURL {
            return external
        }

        guard let streamIndex = track.streamIndex, let ffmpegPath = findFFmpeg() else {
            return nil
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mkvairplay_subtitles_\(streamIndex).srt")

        // If track already extracted and valid, reuse immediately
        if FileManager.default.fileExists(atPath: outputURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           (attrs[.size] as? Int64 ?? 0) > 0 {
            return outputURL
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpegPath)
        task.arguments = [
            "-y",
            "-i", videoURL.path,
            "-map", "0:\(streamIndex)",
            "-c:s", "srt",
            outputURL.path
        ]

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "SubtitleHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract subtitle track \(streamIndex)"])
        }

        return outputURL
    }
}
