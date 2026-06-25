import WidgetKit
import SwiftUI

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
        let defaults = UserDefaults(suiteName: "group.app.legacy.shared")
        let title = defaults?.string(forKey: "widget.onThisDay.title") ?? "On this day"
        let subtitle = defaults?.string(forKey: "widget.onThisDay.subtitle") ?? "Return to places that remember you"
        return OnThisDayWidgetEntry(date: .now, title: title, subtitle: subtitle)
    }
}

struct OnThisDayWidgetView: View {
    let entry: OnThisDayWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
            Text(entry.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
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
