import WidgetKit
import SwiftUI

private enum WidgetKeys {
    static let appGroup = "group.app.legacy.shared"
    static let title = "widget.onThisDay.title"
    static let subtitle = "widget.onThisDay.subtitle"
}

/// Home-screen widget — owner "on this day" teaser (no coordinates).
struct OnThisDayWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
}

struct OnThisDayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayWidgetEntry {
        OnThisDayWidgetEntry(date: .now, title: "On this day", subtitle: "Open Legacy to see memories")
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(21_600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> OnThisDayWidgetEntry {
        let defaults = UserDefaults(suiteName: WidgetKeys.appGroup)
        let title = defaults?.string(forKey: WidgetKeys.title) ?? "On this day"
        let subtitle = defaults?.string(forKey: WidgetKeys.subtitle) ?? "Return to places that remember you"
        return OnThisDayWidgetEntry(date: .now, title: title, subtitle: subtitle)
    }
}

struct OnThisDayWidgetView: View {
    let entry: OnThisDayWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.55, blue: 0.98))
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text(entry.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.07, blue: 0.12),
                    Color(red: 0.14, green: 0.10, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct OnThisDayWidget: Widget {
    let kind = "OnThisDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OnThisDayWidgetProvider()) { entry in
            OnThisDayWidgetView(entry: entry)
        }
        .configurationDisplayName("On this day")
        .description("Memories from this week in prior years.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

@main
struct LegacyWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
    }
}
