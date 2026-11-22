// NowPlayingTests.swift
// Notification decoding and the source rules of the store (WP-18, REQ-13).

import Foundation
import Testing
@testable import ClawdCore

private let now = Date(timeIntervalSince1970: 1_000)

@Suite("Now playing")
struct NowPlayingTests {
    @Test("Music and Spotify userInfo decode; a missing or unknown state is not playing")
    func decoding() {
        let music = NowPlaying(
            notificationName: "com.apple.Music.playerInfo",
            userInfo: ["Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "LP"])
        #expect(music == NowPlaying(app: .music, isPlaying: true, title: "Song", artist: "Band", album: "LP"))
        let spotify = NowPlaying(notificationName: "com.spotify.client.PlaybackStateChanged", userInfo: ["Player State": "Paused"])
        #expect(spotify == NowPlaying(app: .spotify, isPlaying: false))
        #expect(NowPlaying(notificationName: "com.apple.Music.playerInfo", userInfo: ["Player State": "Buffering"])?.isPlaying == false)
        #expect(NowPlaying(notificationName: "com.apple.Music.playerInfo", userInfo: nil)?.isPlaying == false)
        #expect(NowPlaying(notificationName: "other", userInfo: ["Player State": "Playing"]) == nil)
    }

    @Test("The snapshot carries the last report; nothing before the first")
    func snapshotCarries() {
        var store = SessionStore()
        #expect(store.snapshot(now: now).nowPlaying == nil)
        store.apply(nowPlaying: NowPlaying(app: .music, isPlaying: true, title: "A"))
        #expect(store.snapshot(now: now).nowPlaying?.isPlaying == true)
        store.apply(nowPlaying: NowPlaying(app: .music, isPlaying: false, title: "A"))
        #expect(store.snapshot(now: now).nowPlaying?.isPlaying == false)
    }

    @Test("Playing wins; when the source stops the other app takes over if it plays")
    func twoApps() {
        var store = SessionStore()
        store.apply(nowPlaying: NowPlaying(app: .music, isPlaying: true))
        store.apply(nowPlaying: NowPlaying(app: .spotify, isPlaying: true))
        #expect(store.snapshot(now: now).nowPlaying?.app == .spotify)
        store.apply(nowPlaying: NowPlaying(app: .spotify, isPlaying: false))
        #expect(store.snapshot(now: now).nowPlaying?.app == .music)
        #expect(store.snapshot(now: now).nowPlaying?.isPlaying == true)
        // A pause report of the non-source app must not hide the playing source.
        store.apply(nowPlaying: NowPlaying(app: .spotify, isPlaying: false))
        #expect(store.snapshot(now: now).nowPlaying?.app == .music)
        store.apply(nowPlaying: NowPlaying(app: .music, isPlaying: false))
        #expect(store.snapshot(now: now).nowPlaying?.isPlaying == false)
    }
}
