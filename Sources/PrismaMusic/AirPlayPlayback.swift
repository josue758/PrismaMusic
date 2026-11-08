import Foundation
import AVFoundation

@MainActor
protocol MusicPlayback:AnyObject {
    var duration:Double { get }
    var volume:Float { get set }
    var isPlaying:Bool { get }
    var isBuffering:Bool { get }
    var currentTime:Double { get set }
    var levels:(rms:Float,peak:Float) { get }
    var onFinish:(()->Void)? { get set }
    var onError:((Error)->Void)? { get set }
    func apply(_ preferences:ListeningPreferences)
    @discardableResult func play()->Bool
    func pause()
    func stop()
}
@MainActor
final class AirPlayPlayback:MusicPlayback {
    private let player:AVPlayer
    private let item:AVPlayerItem
    private var desiredRate:Float=1
    private var active=false
    private var observer:NSObjectProtocol?
    private var failure:NSKeyValueObservation?
    private let fallbackDuration:Double
    var onFinish:(()->Void)?
    var onError:((Error)->Void)?
    var duration:Double { let value=item.duration.seconds; return value.isFinite && value > 0 ? value : fallbackDuration }
    var volume:Float { get { player.volume } set { player.volume=newValue } }
    var isPlaying:Bool { active && player.currentItem === item }
    var isBuffering:Bool { isPlaying && player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
    var levels:(rms:Float,peak:Float) { (0,0) }
    var currentTime:Double {
        get { let value=player.currentTime().seconds; return value.isFinite ? max(0,value) : 0 }
        set { guard newValue.isFinite else { return }; player.seek(to:CMTime(seconds:min(duration,max(0,newValue)),preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) }
    }
    init(player:AVPlayer,track:Track) {
        self.player=player; fallbackDuration=track.duration
        var options:[String:Any]?
        if track.url.pathExtension.lowercased() == "flac",track.format?.hasPrefix("M4A") == true { options=[AVURLAssetOverrideMIMETypeKey:"audio/mp4"] }
        item=AVPlayerItem(asset:AVURLAsset(url:track.url,options:options))
        item.audioTimePitchAlgorithm = .spectral
        player.allowsExternalPlayback=true
        player.replaceCurrentItem(with:item)
        observer=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self,self.active,self.player.currentItem === self.item else { return }
                self.active=false; self.onFinish?()
            }
        }
        failure=item.observe(\.status,options:[.new]) { [weak self] item,_ in
            guard item.status == .failed else { return }
            let error=item.error ?? URLError(.cannotDecodeContentData)
            Task { @MainActor in guard let self,self.player.currentItem === self.item else { return }; self.active=false; self.onError?(error) }
        }
    }
    func apply(_ preferences:ListeningPreferences) { desiredRate=preferences.playbackRate; if active { player.rate=desiredRate } }
    @discardableResult func play()->Bool {
        guard player.currentItem === item,item.status != .failed else { return false }
        if currentTime >= duration-0.05 { currentTime=0 }
        active=true; player.playImmediately(atRate:desiredRate); return true
    }
    func pause() { active=false; if player.currentItem === item { player.pause() } }
    func stop() { active=false; item.cancelPendingSeeks(); if player.currentItem === item { player.pause() } }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; failure?.invalidate() }
}
