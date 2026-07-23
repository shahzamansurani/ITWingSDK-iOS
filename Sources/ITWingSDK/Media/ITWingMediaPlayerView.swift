import AVFoundation
import AVKit
import UIKit

open class ITWingMediaPlayerView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private let playButton = UIButton(type: .system)

    public var url: URL? {
        didSet { configurePlayer() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        layer.cornerRadius = 16
        clipsToBounds = true
        playButton.setTitle("Play", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.backgroundColor = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        playButton.layer.cornerRadius = 18
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 96),
            playButton.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    public func setMedia(_ item: ITWingMediaItem) {
        url = URL(string: item.mediaUrl)
        let event = item.mimeType?.hasPrefix("video/") == true ? "play" : "play"
        ITWingSDK.trackMediaEvent(kind: item.mimeType?.hasPrefix("video/") == true ? "videos" : "ringtones", itemId: item.id, eventType: event)
    }

    public func play() {
        player?.play()
        playButton.setTitle("Pause", for: .normal)
    }

    public func pause() {
        player?.pause()
        playButton.setTitle("Play", for: .normal)
    }

    @objc private func toggle() {
        if player?.timeControlStatus == .playing {
            pause()
        } else {
            play()
        }
    }

    private func configurePlayer() {
        playerLayer?.removeFromSuperlayer()
        guard let url else { return }
        let player = AVPlayer(url: url)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.player = player
        self.playerLayer = layer
        self.layer.insertSublayer(layer, at: 0)
        setNeedsLayout()
    }
}
