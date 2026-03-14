import UIKit

class CalendarViewController: UIViewController {
    private let calendarContainer = UIView()
    private let calendarView = UICalendarView()
    private var selectedDate: DateComponents?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        view.backgroundColor = AppColors.screenBackground
        setupCalendarView()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: CalendarViewController, _) in
            self.view.backgroundColor = AppColors.screenBackground
        }
    }

    private func setupLayout() {
        calendarContainer.translatesAutoresizingMaskIntoConstraints = false
        calendarContainer.backgroundColor = .systemBackground
        view.addSubview(calendarContainer)

        NSLayoutConstraint.activate([
            calendarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            calendarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            calendarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            calendarContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func setupCalendarView() {
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        calendarView.locale = Locale(identifier: "en_US")
        calendarView.fontDesign = .rounded
        calendarView.tintColor = AppColors.primary
        calendarView.delegate = self
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: self)

        let calendar = Calendar.current
        let today = Date()
        if let startDate = calendar.date(byAdding: .month, value: -1, to: today) {
            calendarView.availableDateRange = DateInterval(start: startDate, end: today)
        }

        calendarContainer.addSubview(calendarView)
        NSLayoutConstraint.activate([
            calendarView.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor),
            calendarView.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor),
            calendarView.topAnchor.constraint(equalTo: calendarContainer.topAnchor),
            calendarView.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor)
        ])
    }

    private func hasActivity(on date: Date) -> Bool {
        return !HistoryDataModel.shared.getActivities(for: date).isEmpty
    }

    private func getHistoryItems(for date: Date) -> [HistoryItem] {
        return HistoryDataModel.shared.getActivities(for: date).map { activity in
            let iconName: String
            switch activity.type {
            case .jam:
                iconName = "mic.fill"
            case .roleplay:
                iconName = "person.2.fill"
            case .aiCall:
                iconName = "phone.fill"
            }

            let durationText: String
            if activity.type == .roleplay, activity.duration > 45 {
                durationText = "\(max(1, Int(round(Double(activity.duration) / 60.0)))) min"
            } else {
                durationText = "\(max(1, activity.duration)) min"
            }

            return HistoryItem(
                title: activity.title,
                subtitle: activity.type.rawValue,
                topic: activity.topic,
                duration: durationText,
                iconName: iconName,
                date: activity.date,
                activityType: activity.type,
                scenarioId: activity.scenarioId,
                isCompleted: activity.isCompleted,
                feedback: activity.feedback
            )
        }
    }
}

extension CalendarViewController: UICalendarViewDelegate {
    func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        if hasActivity(on: date) {
            return .default(color: AppColors.primary)
        }
        return nil
    }
}

extension CalendarViewController: UICalendarSelectionSingleDateDelegate {

    func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
        guard let dc = dateComponents, let date = Calendar.current.date(from: dc) else { return false }
        return hasActivity(on: date)
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        guard let dc = dateComponents, let date = Calendar.current.date(from: dc) else { return }

        let items = getHistoryItems(for: date)
        let vc = HistoryViewController()
        vc.items = items
        vc.selectedDate = date
        navigationController?.pushViewController(vc, animated: true)
    }
}
