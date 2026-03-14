import UIKit

enum GrowthMetric: Int, CaseIterable {
    case overall
    case clarity
    case confidence
    case fluency

    var title: String {
        switch self {
        case .overall: return "Overall"
        case .clarity: return "Clarity"
        case .confidence: return "Confidence"
        case .fluency: return "Fluency"
        }
    }

    var color: UIColor {
        switch self {
        case .overall: return AppColors.primary
        case .clarity: return .systemTeal
        case .confidence: return .systemOrange
        case .fluency: return .systemGreen
        }
    }
}

final class GrowthTrendChartView: UIView {

    private let chartInset = UIEdgeInsets(top: 18, left: 8, bottom: 24, right: 8)
    private let gridLayer = CAShapeLayer()

    private let overallLayer = CAShapeLayer()
    private let clarityLayer = CAShapeLayer()
    private let confidenceLayer = CAShapeLayer()
    private let fluencyLayer = CAShapeLayer()
    private let selectionLineLayer = CAShapeLayer()

    private let overallDotLayer = CAShapeLayer()
    private let clarityDotLayer = CAShapeLayer()
    private let confidenceDotLayer = CAShapeLayer()
    private let fluencyDotLayer = CAShapeLayer()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "Complete sessions to see growth trend"
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let legendStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var points: [FeedbackTrendPoint] = []
    private var visibleMetrics: Set<GrowthMetric> = Set(GrowthMetric.allCases)
    private var legendItems: [GrowthMetric: UIView] = [:]
    private var selectedPointIndex: Int?

    private let tooltipView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    private let tooltipLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleChartTap(_:)))
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawChart()
        repositionTooltipIfNeeded()
    }

    func configure(with points: [FeedbackTrendPoint], visibleMetrics: Set<GrowthMetric> = Set(GrowthMetric.allCases)) {
        self.points = points
        self.visibleMetrics = visibleMetrics
        emptyLabel.isHidden = !points.isEmpty
        legendStack.isHidden = points.isEmpty
        isUserInteractionEnabled = points.count >= 2
        if let index = selectedPointIndex, index >= points.count {
            selectedPointIndex = nil
            tooltipView.isHidden = true
        }
        updateLegendAppearance()
        setNeedsLayout()
    }

    private func setup() {
        backgroundColor = UIColor.clear
        addGestureRecognizer(tapRecognizer)

        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.25).cgColor
        gridLayer.lineWidth = 1
        gridLayer.lineDashPattern = [4, 4]

        selectionLineLayer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.6).cgColor
        selectionLineLayer.lineWidth = 1
        selectionLineLayer.lineDashPattern = [3, 3]
        selectionLineLayer.fillColor = UIColor.clear.cgColor

        [overallLayer, clarityLayer, confidenceLayer, fluencyLayer].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.lineWidth = 2
            $0.lineCap = .round
            layer.addSublayer($0)
        }

        [overallDotLayer, clarityDotLayer, confidenceDotLayer, fluencyDotLayer].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.strokeColor = UIColor.white.cgColor
            $0.lineWidth = 1.2
            layer.addSublayer($0)
        }

        overallLayer.strokeColor = GrowthMetric.overall.color.cgColor
        clarityLayer.strokeColor = GrowthMetric.clarity.color.cgColor
        confidenceLayer.strokeColor = GrowthMetric.confidence.color.cgColor
        fluencyLayer.strokeColor = GrowthMetric.fluency.color.cgColor

        overallDotLayer.fillColor = GrowthMetric.overall.color.cgColor
        clarityDotLayer.fillColor = GrowthMetric.clarity.color.cgColor
        confidenceDotLayer.fillColor = GrowthMetric.confidence.color.cgColor
        fluencyDotLayer.fillColor = GrowthMetric.fluency.color.cgColor

        layer.insertSublayer(gridLayer, at: 0)
        layer.addSublayer(selectionLineLayer)

        addSubview(emptyLabel)
        addSubview(legendStack)
        addSubview(tooltipView)
        tooltipView.addSubview(tooltipLabel)

        NSLayoutConstraint.activate([
            tooltipLabel.topAnchor.constraint(equalTo: tooltipView.topAnchor, constant: 6),
            tooltipLabel.bottomAnchor.constraint(equalTo: tooltipView.bottomAnchor, constant: -6),
            tooltipLabel.leadingAnchor.constraint(equalTo: tooltipView.leadingAnchor, constant: 8),
            tooltipLabel.trailingAnchor.constraint(equalTo: tooltipView.trailingAnchor, constant: -8)
        ])

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            legendStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            legendStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            legendStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        GrowthMetric.allCases.forEach { metric in
            let item = makeLegendItem(title: metric.title, color: metric.color)
            legendItems[metric] = item
            legendStack.addArrangedSubview(item)
        }

        updateLegendAppearance()
    }

    private func drawChart() {
        let chartRect = bounds.inset(by: chartInset)
        guard chartRect.width > 10, chartRect.height > 10 else { return }

        if points.count >= 2 {
            drawGrid(in: chartRect)
        } else {
            gridLayer.path = nil
        }

        guard points.count >= 2 else {
            [overallLayer, clarityLayer, confidenceLayer, fluencyLayer].forEach { $0.path = nil }
            [overallDotLayer, clarityDotLayer, confidenceDotLayer, fluencyDotLayer].forEach { $0.path = nil }
            selectionLineLayer.path = nil
            tooltipView.isHidden = true
            return
        }

        overallLayer.path = visibleMetrics.contains(.overall) ? path(for: points.map { $0.overall }, in: chartRect) : nil
        clarityLayer.path = visibleMetrics.contains(.clarity) ? path(for: points.map { $0.clarity }, in: chartRect) : nil
        confidenceLayer.path = visibleMetrics.contains(.confidence) ? path(for: points.map { $0.confidence }, in: chartRect) : nil
        fluencyLayer.path = visibleMetrics.contains(.fluency) ? path(for: points.map { $0.fluency }, in: chartRect) : nil

        if let index = selectedPointIndex {
            drawSelection(at: index, in: chartRect)
        } else {
            [overallDotLayer, clarityDotLayer, confidenceDotLayer, fluencyDotLayer].forEach { $0.path = nil }
            selectionLineLayer.path = nil
            tooltipView.isHidden = true
        }
    }

    private func drawSelection(at index: Int, in rect: CGRect) {
        guard index >= 0, index < points.count else { return }
        let point = points[index]
        let x = xPosition(for: index, in: rect)

        let verticalPath = UIBezierPath()
        verticalPath.move(to: CGPoint(x: x, y: rect.minY))
        verticalPath.addLine(to: CGPoint(x: x, y: rect.maxY))
        selectionLineLayer.path = verticalPath.cgPath

        drawMetricDot(layer: overallDotLayer, metric: .overall, value: point.overall, x: x, rect: rect)
        drawMetricDot(layer: clarityDotLayer, metric: .clarity, value: point.clarity, x: x, rect: rect)
        drawMetricDot(layer: confidenceDotLayer, metric: .confidence, value: point.confidence, x: x, rect: rect)
        drawMetricDot(layer: fluencyDotLayer, metric: .fluency, value: point.fluency, x: x, rect: rect)

        updateTooltip(for: point, x: x, rect: rect)
    }

    private func drawMetricDot(layer: CAShapeLayer, metric: GrowthMetric, value: Double, x: CGFloat, rect: CGRect) {
        guard visibleMetrics.contains(metric) else {
            layer.path = nil
            return
        }
        let y = yPosition(for: value, in: rect)
        let circle = UIBezierPath(arcCenter: CGPoint(x: x, y: y), radius: 3.8, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        layer.path = circle.cgPath
    }

    private func updateTooltip(for point: FeedbackTrendPoint, x: CGFloat, rect: CGRect) {
        let dateText = dateFormatter.string(from: point.date)
        var lines: [String] = [dateText]

        if visibleMetrics.contains(.overall) {
            lines.append("Overall: \(Int(round(point.overall)))")
        }
        if visibleMetrics.contains(.clarity) {
            lines.append("Clarity: \(Int(round(point.clarity)))")
        }
        if visibleMetrics.contains(.confidence) {
            lines.append("Confidence: \(Int(round(point.confidence)))")
        }
        if visibleMetrics.contains(.fluency) {
            lines.append("Fluency: \(Int(round(point.fluency)))")
        }

        tooltipLabel.text = lines.joined(separator: "\n")
        tooltipView.isHidden = false
        tooltipView.sizeToFit()

        let tooltipWidth = max(108, tooltipView.bounds.width + 16)
        let tooltipHeight = tooltipView.bounds.height + 4

        var tooltipX = x - tooltipWidth / 2
        tooltipX = max(rect.minX, min(tooltipX, rect.maxX - tooltipWidth))

        var tooltipY = rect.minY - tooltipHeight - 6
        if tooltipY < 0 {
            tooltipY = rect.minY + 6
        }

        tooltipView.frame = CGRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)
    }

    private func repositionTooltipIfNeeded() {
        guard let index = selectedPointIndex, !points.isEmpty else { return }
        let rect = bounds.inset(by: chartInset)
        guard rect.width > 10, rect.height > 10 else { return }
        drawSelection(at: index, in: rect)
    }

    @objc private func handleChartTap(_ gesture: UITapGestureRecognizer) {
        let rect = bounds.inset(by: chartInset)
        guard points.count >= 2, rect.contains(gesture.location(in: self)) else {
            selectedPointIndex = nil
            tooltipView.isHidden = true
            setNeedsLayout()
            return
        }

        let tapPoint = gesture.location(in: self)
        let nearest = nearestIndex(toX: tapPoint.x, in: rect)

        if selectedPointIndex == nearest {
            selectedPointIndex = nil
            tooltipView.isHidden = true
        } else {
            selectedPointIndex = nearest
        }
        setNeedsLayout()
    }

    private func nearestIndex(toX x: CGFloat, in rect: CGRect) -> Int {
        guard points.count > 1 else { return 0 }
        let step = rect.width / CGFloat(points.count - 1)
        let raw = Int(round((x - rect.minX) / step))
        return min(max(0, raw), points.count - 1)
    }

    private func xPosition(for index: Int, in rect: CGRect) -> CGFloat {
        guard points.count > 1 else { return rect.midX }
        return rect.minX + (CGFloat(index) / CGFloat(points.count - 1)) * rect.width
    }

    private func yPosition(for value: Double, in rect: CGRect) -> CGFloat {
        let clamped = min(max(value, 0), 100)
        return rect.maxY - (CGFloat(clamped) / 100.0) * rect.height
    }

    private func updateLegendAppearance() {
        for metric in GrowthMetric.allCases {
            legendItems[metric]?.alpha = visibleMetrics.contains(metric) ? 1.0 : 0.35
        }
    }

    private func drawGrid(in rect: CGRect) {
        let path = UIBezierPath()
        let horizontalLines = 4
        for i in 0...horizontalLines {
            let y = rect.minY + (rect.height * CGFloat(i) / CGFloat(horizontalLines))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        gridLayer.path = path.cgPath
    }

    private func path(for values: [Double], in rect: CGRect) -> CGPath {
        let path = UIBezierPath()
        let maxIndex = max(1, values.count - 1)

        for (index, value) in values.enumerated() {
            let xRatio = CGFloat(index) / CGFloat(maxIndex)
            let x = rect.minX + xRatio * rect.width
            let clamped = min(max(value, 0), 100)
            let y = rect.maxY - (CGFloat(clamped) / 100.0) * rect.height
            let point = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path.cgPath
    }

    private func makeLegendItem(title: String, color: UIColor) -> UIView {
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = color
        dot.layer.cornerRadius = 4

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.9)

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])
        return stack
    }
}
