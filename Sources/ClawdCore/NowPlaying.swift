// NowPlaying.swift
// What Music or Spotify reported through their play-state notifications (docs/05 "Now playing", REQ-13).

import Foundation

/// The latest play state of one music app. Title, artist and album are stored for later features, never shown.
public struct NowPlaying: Equatable, Sendable {
    public enum App: Sendable, CaseIterable {
        case music, spotify

        /// The distributed notification each app posts on every play, pause, stop or track change.
        public var notificationName: String {
            switch self {
            case .music: "com.apple.Music.playerInfo"
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    public let app: App
    public let isPlaying: Bool
    public let title: String?
    public let artist: String?
    public let album: String?

    public init(app: App, isPlaying: Bool, title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.app = app
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
    }

    /// Decodes a notification: `Player State` is `Playing`, `Paused` or `Stopped` (anything else, or a missing key,
    /// counts as not playing); `Name`, `Artist` and `Album` are optional. Nil for a notification of another app.
    public init?(notificationName name: String, userInfo: [AnyHashable: Any]?) {
        guard let app = App.allCases.first(where: { $0.notificationName == name }) else { return nil }
        self.init(
            app: app,
            isPlaying: userInfo?["Player State"] as? String == "Playing",
            title: userInfo?["Name"] as? String,
            artist: userInfo?["Artist"] as? String,
            album: userInfo?["Album"] as? String)
    }
}
