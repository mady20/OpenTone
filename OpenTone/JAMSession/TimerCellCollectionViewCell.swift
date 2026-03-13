
import UIKit

protocol TimerCellDelegate: AnyObject {
    func timerDidFinish()
    func timerDidUpdate(secondsLeft: Int)
}

final class TimerCellCollectionViewCell: UICollectionViewCell {

    static let reuseId = "TimerCell"

    @IBOutlet weak var timerRingView: TimerRingView!
    @IBOutlet weak var timerLabel: UILabel!

    weak var delegate: TimerCellDelegate?

    private let timerManager = TimerManager(totalSeconds: 60)
    private var didConfigure = false
    private var currentSeconds = 60

    override func awakeFromNib() {
        super.awakeFromNib()
        timerManager.delegate = self
        resetUI()

        // Dynamic background for dark/light mode
        backgroundColor = UIColor.clear
        contentView.backgroundColor = UIColor.clear
        timerRingView.backgroundColor = UIColor.clear
        timerRingView.superview?.backgroundColor = UIColor.clear
        timerLabel.textColor = UIColor.label
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        timerManager.reset()
        timerRingView.resetRing()
        didConfigure = false
        resetUI()
    }

    func setupTimer(secondsLeft: Int, reset: Bool) {
        guard !didConfigure else { return }
        didConfigure = true

        currentSeconds = reset ? 60 : secondsLeft

        timerRingView.resetRing()
        timerRingView.animateRing(
            remainingSeconds: currentSeconds,
            totalSeconds: 60
        )

        timerManager.start(from: currentSeconds)
    }

    func pauseTimer() {
        timerManager.pause()
        timerRingView.resetRing() // Stop the animation sweep
        // Set to current progress so it looks paused
        timerRingView.setProgress(value: CGFloat(currentSeconds), max: 60)
    }

    func resumeTimer() {
        timerManager.start(from: currentSeconds)
        timerRingView.animateRing(
            remainingSeconds: currentSeconds,
            totalSeconds: 60
        )
    }


    private func resetUI() {
        timerLabel.text = "01:00"
        timerLabel.isHidden = false
    }
}

extension TimerCellCollectionViewCell: TimerManagerDelegate {

    func timerManagerDidStartMainTimer() {}

    func timerManagerDidUpdateMainTimer(_ formattedTime: String) {
        timerLabel.text = formattedTime

        let parts = formattedTime.split(separator: ":")
        if parts.count == 2,
           let m = Int(parts[0]),
           let s = Int(parts[1]) {
            currentSeconds = m * 60 + s
            timerRingView.setProgress(value: CGFloat(currentSeconds), max: 60)
            delegate?.timerDidUpdate(secondsLeft: currentSeconds)
        }
    }

    func timerManagerDidFinish() {
        timerLabel.text = "00:00"
        currentSeconds = 0
        timerRingView.setProgress(value: 0, max: 60)
        delegate?.timerDidFinish()
    }
}

