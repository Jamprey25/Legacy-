import APIClient
import CoreLocation
import DesignSystem
import MapKit
import SwiftUI

#if os(iOS)

/// Full-screen muted zones manager. Shows existing zones as red circles on a map,
/// lets the user add a new zone at their current location or a map tap, and adjust
/// the radius with a slider.
public struct MutedZonesView: View {
    @Bindable var coordinator: MutedZonesCoordinator

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showAddSheet = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var locationManager = CLLocationManager()

    public init(coordinator: MutedZonesCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            map

            VStack(spacing: LegacySpacing.sm) {
                if !coordinator.zones.isEmpty {
                    mutedZonesList
                }
                tapHint
                addButton
            }
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.bottom, LegacySpacing.lg)
        }
        .navigationTitle("Muted zones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if coordinator.isLoading {
                    ProgressView().tint(LegacyColor.accent)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMutedZoneSheet(
                coordinator: coordinator,
                currentLocation: pendingCoordinate ?? currentLocation
            )
        }
        .task { await coordinator.load() }
        .onAppear { locationManager.requestWhenInUseAuthorization() }
        .onChange(of: showAddSheet) { _, isPresented in
            if !isPresented {
                pendingCoordinate = nil
            }
        }
        .overlay(alignment: .top) {
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.danger)
                    .padding(.horizontal, LegacySpacing.lg)
                    .padding(.vertical, LegacySpacing.sm)
                    .background(LegacyColor.surface.opacity(0.95))
                    .clipShape(Capsule())
                    .padding(.top, LegacySpacing.sm)
            }
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                ForEach(coordinator.zones) { zone in
                    MapCircle(
                        center: CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lng),
                        radius: CLLocationDistance(zone.radiusM)
                    )
                    .foregroundStyle(LegacyColor.danger.opacity(0.18))
                    .stroke(LegacyColor.danger.opacity(0.7), lineWidth: 2)

                    Annotation(zone.label ?? "Muted", coordinate: CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lng)) {
                        MutedZonePin(label: zone.label) {
                            Task { await coordinator.deleteZone(id: zone.id) }
                        }
                    }
                }

                if showAddSheet, let pendingCoordinate {
                    Annotation("New muted zone", coordinate: pendingCoordinate) {
                        PendingMutedZonePin()
                    }
                }
            }
            .onTapGesture(coordinateSpace: .local) { point in
                guard let tappedCoordinate = proxy.convert(point, from: .local) else { return }
                pendingCoordinate = tappedCoordinate
                showAddSheet = true
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .top)
        }
    }

    private var mutedZonesList: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.xs) {
            Text("Your muted zones")
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textSecondary)
                .padding(.horizontal, LegacySpacing.xs)

            List {
                ForEach(coordinator.zones) { zone in
                    MutedZoneListRow(zone: zone) {
                        Task { await coordinator.deleteZone(id: zone.id) }
                    }
                    .listRowBackground(LegacyColor.surface.opacity(0.92))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await coordinator.deleteZone(id: zone.id) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: min(CGFloat(coordinator.zones.count) * 58 + 8, 240))
        }
        .padding(LegacySpacing.sm)
        .background(LegacyColor.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
    }

    private var addButton: some View {
        Button {
            pendingCoordinate = nil
            showAddSheet = true
        } label: {
            Label("Add muted zone", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.legacyPrimary)
        .disabled(coordinator.zones.count >= 10 || coordinator.isLoading)
    }

    private var tapHint: some View {
        Text("Tip: Tap anywhere on the map to place a zone there.")
            .font(LegacyFont.caption)
            .foregroundStyle(LegacyColor.textSecondary)
            .padding(.horizontal, LegacySpacing.md)
            .padding(.vertical, LegacySpacing.xs)
            .frame(maxWidth: .infinity)
            .background(LegacyColor.surface.opacity(0.92))
            .clipShape(Capsule())
    }

    private var currentLocation: CLLocationCoordinate2D? {
        locationManager.location?.coordinate
    }
}

// MARK: - Zone list row

private struct MutedZoneListRow: View {
    let zone: MutedZone
    let onRemove: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: LegacySpacing.md) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LegacyColor.danger)
                .frame(width: 28, height: 28)
                .background(LegacyColor.danger.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.label ?? "Muted zone")
                    .font(LegacyFont.body)
                    .foregroundStyle(LegacyColor.textPrimary)
                Text("\(zone.radiusM)m radius")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }

            Spacer(minLength: LegacySpacing.sm)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove muted zone")
        }
        .confirmationDialog(zone.label ?? "Muted zone", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove zone", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Notifications near this location will be re-enabled.")
        }
    }
}

// MARK: - Zone pin

private struct PendingMutedZonePin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LegacyColor.accent.opacity(0.92))
                .frame(width: 28, height: 28)
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay {
            Circle()
                .stroke(.white.opacity(0.8), lineWidth: 2)
        }
    }
}

private struct MutedZonePin: View {
    let label: String?
    let onDelete: () -> Void

    @State private var showDelete = false

    var body: some View {
        Button {
            showDelete = true
        } label: {
            ZStack {
                Circle()
                    .fill(LegacyColor.danger.opacity(0.9))
                    .frame(width: 30, height: 30)
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog(label ?? "Muted zone", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Remove zone", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Notifications near this location will be re-enabled.")
        }
    }
}

// MARK: - Add sheet

private struct AddMutedZoneSheet: View {
    @Bindable var coordinator: MutedZonesCoordinator
    let currentLocation: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var radiusM = 500
    @State private var label = ""
    @State private var isSaving = false

    private let minRadius = 100
    private let maxRadius = 5000

    var body: some View {
        NavigationStack {
            ZStack {
                LegacyColor.background.ignoresSafeArea()

                VStack(spacing: LegacySpacing.xl) {
                    // Zone preview circle — scales proportionally with the slider
                    ZStack {
                        Circle()
                            .fill(LegacyColor.danger.opacity(0.15))
                            .frame(width: previewSize, height: previewSize)
                        Circle()
                            .stroke(LegacyColor.danger.opacity(0.6), lineWidth: 2)
                            .frame(width: previewSize, height: previewSize)
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LegacyColor.danger)
                    }
                    .animation(.easeOut(duration: 0.15), value: radiusM)
                    .padding(.top, LegacySpacing.lg)

                    Text("\(radiusM)m radius")
                        .font(LegacyFont.title2)
                        .foregroundStyle(LegacyColor.textPrimary)

                    VStack(spacing: LegacySpacing.sm) {
                        Slider(value: Binding(
                            get: { Double(radiusM) },
                            set: { radiusM = Int($0) }
                        ), in: Double(minRadius)...Double(maxRadius), step: 50)
                        .tint(LegacyColor.danger)
                        .padding(.horizontal, LegacySpacing.xl)

                        HStack {
                            Text("\(minRadius)m")
                            Spacer()
                            Text("\(maxRadius / 1000)km")
                        }
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .padding(.horizontal, LegacySpacing.xl)
                    }

                    TextField("Label (optional, e.g. Home)", text: $label)
                        .font(LegacyFont.body)
                        .foregroundStyle(LegacyColor.textPrimary)
                        .padding(LegacySpacing.md)
                        .background(LegacyColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                        .padding(.horizontal, LegacySpacing.xl)
                        .autocorrectionDisabled()

                    if currentLocation == nil {
                        Text("Enable location access so we can place the zone at your current position.")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, LegacySpacing.xl)
                    }

                    Spacer()
                }
            }
            .navigationTitle("New muted zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(LegacyColor.textSecondary)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .font(LegacyFont.headline)
                        .foregroundStyle(currentLocation != nil ? LegacyColor.accent : LegacyColor.textSecondary)
                        .disabled(currentLocation == nil || isSaving)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
    }

    // Scale the preview circle: 60pt at min radius, 120pt at max.
    private var previewSize: CGFloat {
        let t = Double(radiusM - minRadius) / Double(maxRadius - minRadius)
        return 60 + CGFloat(t * 60)
    }

    private func save() async {
        guard let coord = currentLocation else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        await coordinator.addZone(
            lat: coord.latitude,
            lng: coord.longitude,
            radiusM: radiusM,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel
        )
        if coordinator.errorMessage == nil {
            dismiss()
        }
    }
}

#endif
