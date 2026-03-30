import UIKit

class SuggestionCell: UITableViewCell {

    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupStack()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStack()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .clear
        selectionStyle = .none
    }

    private func setupStack() {
        backgroundColor = .clear
        selectionStyle = .none

        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .trailing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        for view in stackView.arrangedSubviews {
            view.removeFromSuperview()
        }
    }

    func configure(_ suggestions: [String]) {
        for view in stackView.arrangedSubviews {
            view.removeFromSuperview()
        }

        for suggestion in suggestions {
            let view = makeHintView(title: suggestion)
            stackView.addArrangedSubview(view)
        }
    }

    private func makeHintView(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = AppColors.primaryLight.withAlphaComponent(0.6)
        container.layer.cornerRadius = 18
        container.layer.borderWidth = 1
        container.layer.borderColor = AppColors.primary.withAlphaComponent(0.25).cgColor
        container.clipsToBounds = true

        // Match chat bubble corner style — round top-left, top-right, bottom-left
        container.layer.maskedCorners = [
            .layerMinXMinYCorner,  // top-left
            .layerMaxXMinYCorner,  // top-right
            .layerMinXMaxYCorner   // bottom-left
        ]

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = AppColors.primary

        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])

        return container
    }
}
