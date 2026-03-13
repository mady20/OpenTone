import UIKit

final class DailyGoalAchievementViewController: UIViewController {

    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.cardBackground
        view.layer.cornerRadius = 24
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.cardBorder.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.layer.shadowRadius = 24
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Daily Goal Complete"
        label.font = .systemFont(ofSize: 28, weight: .heavy)
        label.textColor = AppColors.textPrimary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "You finished today's communication target. Keep this streak alive."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let trophyLabel: UILabel = {
        let label = UILabel()
        label.text = "GOAL"
        label.font = .systemFont(ofSize: 56)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Awesome", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        UIHelper.stylePrimaryButton(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.animate(withDuration: 0.25) {
            self.dimView.alpha = 1
        }

        cardView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.5) {
            self.cardView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    private func setupUI() {
        view.addSubview(dimView)
        view.addSubview(cardView)

        cardView.addSubview(trophyLabel)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            trophyLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 28),
            trophyLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: trophyLabel.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22),
            actionButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            actionButton.heightAnchor.constraint(equalToConstant: 50),
            actionButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20)
        ])

        actionButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        dimView.addGestureRecognizer(tap)
    }

    @objc private func closeTapped() {
        UIView.animate(withDuration: 0.2, animations: {
            self.dimView.alpha = 0
            self.cardView.alpha = 0
            self.cardView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            self.dismiss(animated: false)
        }
    }
}
