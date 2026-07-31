import CoreGraphics

enum UsageTimelineMetrics {
  static let percentageColumnWidth: CGFloat = 34
  static let providerColumnWidth: CGFloat = 78
  static let accountColumnWidth: CGFloat = 84
  static let resetColumnWidth: CGFloat = 52
  static let columnSpacing: CGFloat = 6
  static let rowHeight: CGFloat = 23
  static let barHeight: CGFloat = 12
  static let nowLineHeight: CGFloat = 18
  static let naturalTimelineWidth: CGFloat = 115
  static let minimumTimelineWidth: CGFloat = 112
  static let outerHorizontalPadding: CGFloat = 12
  static let outerVerticalPadding: CGFloat = 10
  static let sectionSpacing: CGFloat = 9
  static let sectionContentSpacing: CGFloat = 4

  static let naturalWidth: CGFloat =
    (outerHorizontalPadding * 2)
    + percentageColumnWidth
    + providerColumnWidth
    + accountColumnWidth
    + naturalTimelineWidth
    + resetColumnWidth
    + (columnSpacing * 4)
}
