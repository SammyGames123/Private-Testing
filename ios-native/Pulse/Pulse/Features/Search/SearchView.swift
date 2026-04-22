import AVKit
import MapKit
import SwiftUI
import UIKit

struct SearchView: View {
    @StateObject private var model = MomentMapViewModel()
    @State private var selectedMoment: MapMoment?
    @State private var previewMoment: MapMoment?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -28.0167, longitude: 153.4000),
        span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
    )

    var body: some View {
        NavigationStack {
            ZStack {
                PulseMomentMapView(
                    moments: model.moments,
                    region: $mapRegion,
                    selectedMomentId: selectedMoment?.id,
                    onTapMoment: { moment in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            selectedMoment = moment
                        }
                    }
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if model.isLoading && model.moments.isEmpty {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                topOverlay
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomOverlay
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .task {
            await model.loadIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await model.load(forceRefresh: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { _ in
            Task {
                await model.load(forceRefresh: true)
            }
        }
        .fullScreenCover(item: $previewMoment) { moment in
            MomentMapPreviewView(moment: moment)
        }
    }

    private var topOverlay: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Map")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Text(model.moments.isEmpty ? "No moments nearby" : "\(model.moments.count) live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.42))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )

            Spacer()

            PulseInboxLaunchButton()
        }
        .overlay(alignment: .bottomLeading) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.78))
                    .clipShape(Capsule())
                    .offset(y: 42)
            }
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        if let selectedMoment {
            MomentMapCard(
                moment: selectedMoment,
                onView: {
                    previewMoment = selectedMoment
                },
                onClose: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        self.selectedMoment = nil
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

@MainActor
private final class MomentMapViewModel: ObservableObject {
    @Published private(set) var moments: [MapMoment] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func loadIfNeeded() async {
        guard moments.isEmpty else { return }
        await load(forceRefresh: false)
    }

    func load(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            moments = try await FeedService.shared.fetchMapMoments(forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseMomentMapView: UIViewRepresentable {
    let moments: [MapMoment]
    @Binding var region: MKCoordinateRegion
    let selectedMomentId: String?
    let onTapMoment: (MapMoment) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(region: $region, selectedMomentId: selectedMomentId, onTapMoment: onTapMoment)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.setRegion(region, animated: false)
        context.coordinator.syncAnnotations(on: mapView, moments: moments)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.region = $region
        context.coordinator.selectedMomentId = selectedMomentId
        context.coordinator.onTapMoment = onTapMoment
        context.coordinator.syncAnnotations(on: mapView, moments: moments)
        context.coordinator.syncSelection(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var region: Binding<MKCoordinateRegion>
        var selectedMomentId: String?
        var onTapMoment: (MapMoment) -> Void

        init(
            region: Binding<MKCoordinateRegion>,
            selectedMomentId: String?,
            onTapMoment: @escaping (MapMoment) -> Void
        ) {
            self.region = region
            self.selectedMomentId = selectedMomentId
            self.onTapMoment = onTapMoment
        }

        func syncAnnotations(on mapView: MKMapView, moments: [MapMoment]) {
            let existing = mapView.annotations.compactMap { $0 as? PulseMomentAnnotation }
            let nextIds = Set(moments.map(\.id))
            let existingIds = Set(existing.map(\.moment.id))

            let stale = existing.filter { !nextIds.contains($0.moment.id) }
            mapView.removeAnnotations(stale)

            for moment in moments where !existingIds.contains(moment.id) {
                mapView.addAnnotation(PulseMomentAnnotation(moment: moment))
            }
        }

        func syncSelection(on mapView: MKMapView) {
            for annotation in mapView.annotations.compactMap({ $0 as? PulseMomentAnnotation }) {
                guard let view = mapView.view(for: annotation) as? PulseMomentAnnotationView else { continue }
                view.configure(with: annotation.moment, isSelected: annotation.moment.id == selectedMomentId)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? PulseMomentAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: PulseMomentAnnotationView.reuseIdentifier
            ) as? PulseMomentAnnotationView ?? PulseMomentAnnotationView(
                annotation: annotation,
                reuseIdentifier: PulseMomentAnnotationView.reuseIdentifier
            )

            view.annotation = annotation
            view.configure(with: annotation.moment, isSelected: annotation.moment.id == selectedMomentId)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? PulseMomentAnnotation else { return }
            mapView.setCenter(annotation.coordinate, animated: true)
            onTapMoment(annotation.moment)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            region.wrappedValue = mapView.region
        }
    }
}

private final class PulseMomentAnnotation: NSObject, MKAnnotation {
    let moment: MapMoment
    let coordinate: CLLocationCoordinate2D

    init(moment: MapMoment) {
        self.moment = moment
        self.coordinate = moment.coordinate
        super.init()
    }
}

private final class PulseMomentAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PulseMomentAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .circle
        centerOffset = CGPoint(x: 0, y: -8)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with moment: MapMoment, isSelected: Bool) {
        image = Self.image(initial: moment.creatorInitial, isSelected: isSelected)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.24
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private static func image(initial: String, isSelected: Bool) -> UIImage {
        let size = CGSize(width: isSelected ? 56 : 46, height: isSelected ? 56 : 46)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let cgContext = context.cgContext
            let colors = [
                UIColor(red: 0.35, green: 0.25, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.72, blue: 1.0, alpha: 1).cgColor,
            ]

            cgContext.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            cgContext.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cgContext.saveGState()
                cgContext.addEllipse(in: rect)
                cgContext.clip()
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
                cgContext.restoreGState()
            }

            cgContext.setStrokeColor(UIColor.white.withAlphaComponent(isSelected ? 0.95 : 0.72).cgColor)
            cgContext.setLineWidth(isSelected ? 3 : 2)
            cgContext.strokeEllipse(in: rect)

            let text = initial.isEmpty ? "P" : initial
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: isSelected ? 22 : 18, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes
            )
        }
    }
}

private struct MomentMapCard: View {
    let moment: MapMoment
    let onView: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MomentAvatar(moment: moment, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(moment.creatorName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(moment.relativeTimestamp)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Text(moment.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(moment.visibility.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Button("View", action: onView)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.13))
                .clipShape(Capsule())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.black.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct MomentMapPreviewView: View {
    let moment: MapMoment
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MomentMediaView(moment: moment, player: player)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.56), .clear, .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.34))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                HStack(alignment: .bottom, spacing: 12) {
                    MomentAvatar(moment: moment, size: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(moment.creatorHandle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(moment.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        if let caption = moment.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            if moment.mediaKind == .video, let url = moment.playbackURL {
                let nextPlayer = AVPlayer(url: url)
                player = nextPlayer
                nextPlayer.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct MomentMediaView: View {
    let moment: MapMoment
    let player: AVPlayer?

    var body: some View {
        Group {
            if moment.mediaKind == .image, let url = moment.playbackURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        unavailableView
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        unavailableView
                    }
                }
            } else if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.largeTitle)
            Text("Moment unavailable")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.72))
    }
}

private struct MomentAvatar: View {
    let moment: MapMoment
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.25, blue: 1.0),
                            Color(red: 0.02, green: 0.72, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let url = moment.creatorAvatarURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(moment.creatorInitial)
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(moment.creatorInitial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: 1.5)
        )
    }
}

private struct LegacyVenueSearchView: View {
    @StateObject private var model = HotVenuesViewModel()
    @StateObject private var locationManager = PulseLocationManager()
    @State private var searchText = ""
    @State private var selectedVenueSummary: HotVenueSummary?
    @State private var venueDistanceLabels: [String: String] = [:]
    @State private var venueMapCoordinates: [String: CLLocationCoordinate2D] = [:]
    @State private var highlightedVenueId: String?
    @State private var selectedStatuses: Set<PulseVenueStatus> = []
    @State private var mapRegion: MKCoordinateRegion = Self.defaultMapRegion

    var body: some View {
        NavigationStack {
            ZStack {
                fullScreenMap

                LinearGradient(
                    colors: [.black.opacity(0.48), .clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if model.isLoading && model.snapshot == nil {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                topOverlay
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomOverlay
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .task {
            await model.loadIfNeeded()
        }
        .task {
            activateRecommendationLocation()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await model.load(forceRefresh: true)
            }
        }
        .task(id: venueDistanceTaskKey) {
            await refreshVenueDistances()
        }
        .task(id: venueCoordinateTaskKey) {
            await refreshVenueCoordinates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { _ in
            Task {
                await model.load(forceRefresh: true)
            }
        }
        .onDisappear {
            locationManager.setContinuousTrackingEnabled(false)
            venueDistanceLabels = [:]
        }
        .onChange(of: filteredVenueIds) { _, _ in
            guard let highlightedVenueId else { return }
            if !filteredVenueIds.contains(highlightedVenueId) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    self.highlightedVenueId = nil
                }
            }
        }
        .fullScreenCover(item: $selectedVenueSummary) { summary in
            PulseVenueDetailSheet(
                summary: summary,
                recentCheckIns: model.snapshot?.recentCheckIns.filter { $0.venueId == summary.venue.id } ?? [],
                distanceLabel: venueDistanceLabels[summary.venue.id]
            )
        }
        .dismissKeyboardOnTap()
    }

    private var filteredVenues: [HotVenueSummary] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.hotVenues.filter { summary in
            let matchesStatus = selectedStatuses.isEmpty || selectedStatuses.contains(summary.status)
            guard matchesStatus else { return false }
            guard !trimmedQuery.isEmpty else { return true }

            let haystack = [
                summary.venue.name,
                summary.venue.area,
                summary.venue.city,
                summary.venue.category ?? "",
                summary.venue.vibeBlurb ?? "",
            ]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(trimmedQuery.lowercased())
        }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recommendedSummary: HotVenueSummary? {
        guard let venueId = model.snapshot?.recommendation?.venue.id else { return nil }
        return model.hotVenues.first(where: { $0.venue.id == venueId })
    }

    private var recommendationDistanceLabel: String? {
        guard let venueId = recommendedSummary?.venue.id else { return nil }
        return venueDistanceLabels[venueId]
    }

    private var filteredVenueIds: [String] {
        filteredVenues.map(\.id)
    }

    private var venueDistanceTaskKey: String {
        let venueIds = model.hotVenues.map(\.venue.id).joined(separator: ",")
        let timestamp = locationManager.currentLocation?.timestamp.timeIntervalSince1970 ?? 0
        return "\(venueIds)-\(locationManager.authorizationStatus.rawValue)-\(timestamp)"
    }

    private var venueCoordinateTaskKey: String {
        model.hotVenues.map(\.venue.id).joined(separator: ",")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search venues", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.44))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField
                .frame(maxWidth: .infinity)

            PulseInboxLaunchButton()
        }
    }

    private var statusFilters: some View {
        HStack(spacing: 8) {
            filterChip(emoji: "🔥", title: "Hot", status: .hot)
            filterChip(emoji: "⚡️", title: "Building", status: .building)
            filterChip(emoji: "↘︎", title: "Slowing", status: .slowingDown)
            filterChip(emoji: "✨", title: "Quiet", status: .quiet)
        }
    }

    private var fullScreenMap: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PulseHotVenueMapView(
                summaries: filteredVenues,
                coordinatesByVenueId: venueMapCoordinates,
                region: $mapRegion,
                highlightedVenueId: highlightedVenueId,
                onTapVenue: { summary in
                    focus(on: summary)
                }
            )
            .ignoresSafeArea()
        }
    }

    private var topOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchRow
            statusFilters

            if let errorMessage = model.errorMessage {
                inlineMessage(errorMessage, tint: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        if let activeMapSummary {
            MapVenueActionSheet(
                summary: activeMapSummary,
                distanceLabel: venueDistanceLabels[activeMapSummary.venue.id],
                onViewVenue: {
                    selectedVenueSummary = activeMapSummary
                },
                onCheckIn: {
                    NotificationCenter.default.post(
                        name: .pulseOpenCreate,
                        object: PulseCreateRoute(mode: "check-in", venueId: activeMapSummary.venue.id)
                    )
                },
                onClose: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        highlightedVenueId = nil
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !model.isLoading {
            EmptyView()
        }
    }

    private var activeMapSummary: HotVenueSummary? {
        guard let highlightedVenueId else { return nil }
        return filteredVenues.first(where: { $0.id == highlightedVenueId })
    }

    private func filterChip(emoji: String, title: String, status: PulseVenueStatus) -> some View {
        let isSelected = selectedStatuses.contains(status)

        return Button {
            if isSelected {
                selectedStatuses.remove(status)
            } else {
                selectedStatuses.insert(status)
            }
        } label: {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.subheadline)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? status.mapTint.opacity(0.28) : Color.black.opacity(0.42))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? status.mapTint.opacity(0.9) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func focus(on summary: HotVenueSummary) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            highlightedVenueId = summary.id
        }
    }

    private static let defaultMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -28.0167, longitude: 153.4000),
        span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
    )

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }

    private func activateRecommendationLocation() {
        locationManager.setContinuousTrackingEnabled(true)
        locationManager.requestLocationAccessIfNeeded()
        locationManager.refreshLocation()
    }

    private func refreshVenueDistances() async {
        guard !model.hotVenues.isEmpty else {
            venueDistanceLabels = [:]
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined, .restricted, .denied:
            venueDistanceLabels = [:]
            return
        @unknown default:
            venueDistanceLabels = [:]
            return
        }

        guard let currentLocation = locationManager.currentLocation else {
            venueDistanceLabels = [:]
            return
        }

        var nextLabels: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for summary in model.hotVenues where summary.venue.resolvedAddress != nil {
                let venue = summary.venue
                group.addTask {
                    do {
                        let venueLocation = try await PulseVenueLocationResolver.shared.location(for: venue)
                        let distance = currentLocation.distance(from: venueLocation)
                        return (venue.id, PulseDistanceFormatter.proximityLabel(for: distance))
                    } catch {
                        return (venue.id, nil)
                    }
                }
            }

            for await (venueId, label) in group {
                if let label {
                    nextLabels[venueId] = label
                }
            }
        }

        venueDistanceLabels = nextLabels
    }

    private func refreshVenueCoordinates() async {
        guard !model.hotVenues.isEmpty else {
            venueMapCoordinates = [:]
            return
        }

        var nextCoordinates: [String: CLLocationCoordinate2D] = [:]
        for summary in model.hotVenues {
            if let fallbackCoordinate = summary.venue.mapCoordinate {
                nextCoordinates[summary.venue.id] = fallbackCoordinate
            }
        }

        await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
            for summary in model.hotVenues where summary.venue.resolvedAddress != nil {
                let venue = summary.venue
                if venue.latitude != nil && venue.longitude != nil { continue }
                group.addTask {
                    do {
                        let venueLocation = try await PulseVenueLocationResolver.shared.location(for: venue)
                        return (venue.id, venueLocation.coordinate)
                    } catch {
                        return (venue.id, venue.mapCoordinate)
                    }
                }
            }

            for await (venueId, coordinate) in group {
                if let coordinate {
                    nextCoordinates[venueId] = coordinate
                }
            }
        }

        venueMapCoordinates = Self.fanOutOverlapping(nextCoordinates)
    }

    private static func fanOutOverlapping(
        _ input: [String: CLLocationCoordinate2D]
    ) -> [String: CLLocationCoordinate2D] {
        // Group venues whose coords collapse to the same ~20 m bucket so we
        // can place their pins side by side rather than stacked.
        let bucketScale = 10_000.0
        let groups = Dictionary(grouping: input.keys) { id -> String in
            guard let coord = input[id] else { return id }
            let lat = (coord.latitude * bucketScale).rounded() / bucketScale
            let lng = (coord.longitude * bucketScale).rounded() / bucketScale
            return "\(lat),\(lng)"
        }

        var result = input
        let spacing = 0.00028 // ≈ 27 m of longitude at GC latitude

        for ids in groups.values where ids.count > 1 {
            let sortedIds = ids.sorted()
            let coords = sortedIds.compactMap { input[$0] }
            let centerLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
            let centerLng = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
            let offsetOrigin = (Double(sortedIds.count) - 1) / 2.0

            for (index, id) in sortedIds.enumerated() {
                let offset = (Double(index) - offsetOrigin) * spacing
                result[id] = CLLocationCoordinate2D(
                    latitude: centerLat,
                    longitude: centerLng + offset
                )
            }
        }

        return result
    }
}

private struct PulseHotVenueMapView: UIViewRepresentable {
    let summaries: [HotVenueSummary]
    let coordinatesByVenueId: [String: CLLocationCoordinate2D]
    @Binding var region: MKCoordinateRegion
    let highlightedVenueId: String?
    let onTapVenue: (HotVenueSummary) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            region: $region,
            coordinatesByVenueId: coordinatesByVenueId,
            highlightedVenueId: highlightedVenueId,
            onTapVenue: onTapVenue
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setRegion(region, animated: false)
        context.coordinator.installTapRecognizer(on: mapView)
        context.coordinator.syncAnnotations(on: mapView, summaries: summaries)
        context.coordinator.syncAppearance(on: mapView, highlightedVenueId: highlightedVenueId)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.region = $region
        context.coordinator.coordinatesByVenueId = coordinatesByVenueId
        context.coordinator.highlightedVenueId = highlightedVenueId
        context.coordinator.onTapVenue = onTapVenue
        context.coordinator.syncAnnotations(on: mapView, summaries: summaries)
        context.coordinator.syncAppearance(on: mapView, highlightedVenueId: highlightedVenueId)

        if context.coordinator.shouldApplyExternalRegion(mapView.region, target: region) {
            context.coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(region, animated: false)
            context.coordinator.isProgrammaticRegionChange = false
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var region: Binding<MKCoordinateRegion>
        var coordinatesByVenueId: [String: CLLocationCoordinate2D]
        var highlightedVenueId: String?
        var onTapVenue: (HotVenueSummary) -> Void
        var isProgrammaticRegionChange = false

        init(
            region: Binding<MKCoordinateRegion>,
            coordinatesByVenueId: [String: CLLocationCoordinate2D],
            highlightedVenueId: String?,
            onTapVenue: @escaping (HotVenueSummary) -> Void
        ) {
            self.region = region
            self.coordinatesByVenueId = coordinatesByVenueId
            self.highlightedVenueId = highlightedVenueId
            self.onTapVenue = onTapVenue
        }

        func installTapRecognizer(on mapView: MKMapView) {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            tapRecognizer.cancelsTouchesInView = false
            mapView.addGestureRecognizer(tapRecognizer)

            for recognizer in mapView.gestureRecognizers ?? [] {
                guard recognizer !== tapRecognizer,
                      let tap = recognizer as? UITapGestureRecognizer,
                      tap.numberOfTapsRequired > 1
                else { continue }
                tapRecognizer.require(toFail: tap)
            }
        }

        func syncAnnotations(on mapView: MKMapView, summaries: [HotVenueSummary]) {
            let pairs: [(String, HotVenueSummary)] = summaries.compactMap { summary in
                guard coordinatesByVenueId[summary.venue.id] != nil else { return nil }
                return (summary.id, summary)
            }
            let nextSummariesById = Dictionary(uniqueKeysWithValues: pairs)

            let existingAnnotations = mapView.annotations.compactMap { $0 as? PulseHotVenueAnnotation }
            let existingIds = Set(existingAnnotations.map(\.summary.id))
            let nextIds = Set(nextSummariesById.keys)

            let annotationsToRemove = existingAnnotations.filter { !nextIds.contains($0.summary.id) }
            mapView.removeAnnotations(annotationsToRemove)

            for annotation in existingAnnotations {
                guard let summary = nextSummariesById[annotation.summary.id],
                      let coordinate = coordinatesByVenueId[summary.venue.id] else { continue }
                annotation.summary = summary
                annotation.coordinate = coordinate
            }

            let annotationsToAdd = nextSummariesById.values
                .filter { !existingIds.contains($0.id) }
                .compactMap { summary -> PulseHotVenueAnnotation? in
                    guard let coordinate = coordinatesByVenueId[summary.venue.id] else { return nil }
                    return PulseHotVenueAnnotation(summary: summary, coordinate: coordinate)
                }
            mapView.addAnnotations(annotationsToAdd)
        }

        func syncAppearance(on mapView: MKMapView, highlightedVenueId: String?) {
            for annotation in mapView.annotations.compactMap({ $0 as? PulseHotVenueAnnotation }) {
                let isHighlighted = annotation.summary.id == highlightedVenueId
                if let view = mapView.view(for: annotation) as? PulseHotVenueAnnotationView {
                    view.configure(summary: annotation.summary, isHighlighted: isHighlighted)
                }
            }
        }

        func shouldApplyExternalRegion(_ current: MKCoordinateRegion, target: MKCoordinateRegion) -> Bool {
            let latitudeDeltaDiff = abs(current.span.latitudeDelta - target.span.latitudeDelta)
            let longitudeDeltaDiff = abs(current.span.longitudeDelta - target.span.longitudeDelta)
            let latitudeDiff = abs(current.center.latitude - target.center.latitude)
            let longitudeDiff = abs(current.center.longitude - target.center.longitude)

            return latitudeDeltaDiff > 0.0005
                || longitudeDeltaDiff > 0.0005
                || latitudeDiff > 0.0005
                || longitudeDiff > 0.0005
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isProgrammaticRegionChange else { return }
            region.wrappedValue = mapView.region
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? PulseHotVenueAnnotation else { return nil }

            let reuseIdentifier = PulseHotVenueAnnotationView.reuseIdentifier
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? PulseHotVenueAnnotationView)
                ?? PulseHotVenueAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
            view.annotation = annotation
            view.configure(summary: annotation.summary, isHighlighted: annotation.summary.id == highlightedVenueId)
            return view
        }

        @objc
        private func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView = recognizer.view as? MKMapView
            else { return }

            let tapPoint = recognizer.location(in: mapView)
            guard let annotation = tappedAnnotation(at: tapPoint, on: mapView) else { return }

            center(on: annotation, in: mapView)
        }

        private func tappedAnnotation(at point: CGPoint, on mapView: MKMapView) -> PulseHotVenueAnnotation? {
            mapView.annotations
                .compactMap { $0 as? PulseHotVenueAnnotation }
                .compactMap { annotation -> (PulseHotVenueAnnotation, CGFloat)? in
                    guard let view = mapView.view(for: annotation) else { return nil }
                    let hitFrame = view.frame.insetBy(dx: -14, dy: -14)
                    guard hitFrame.contains(point) else { return nil }

                    let center = CGPoint(x: view.frame.midX, y: view.frame.midY)
                    let distance = hypot(center.x - point.x, center.y - point.y)
                    return (annotation, distance)
                }
                .min(by: { $0.1 < $1.1 })?
                .0
        }

        private func center(on annotation: PulseHotVenueAnnotation, in mapView: MKMapView) {
            let currentSpan = mapView.region.span
            isProgrammaticRegionChange = true
            mapView.setCenter(annotation.coordinate, animated: true)
            region.wrappedValue = MKCoordinateRegion(center: annotation.coordinate, span: currentSpan)
            isProgrammaticRegionChange = false
            onTapVenue(annotation.summary)
        }
    }
}

private final class PulseHotVenueAnnotation: NSObject, MKAnnotation {
    var summary: HotVenueSummary
    dynamic var coordinate: CLLocationCoordinate2D

    init(summary: HotVenueSummary, coordinate: CLLocationCoordinate2D) {
        self.summary = summary
        self.coordinate = coordinate
    }
}

private final class PulseHotVenueAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PulseHotVenueAnnotationView"

    private let iconContainer = UIView()
    private let emojiLabel = UILabel()
    private let nameBackgroundView = UIView()
    private let nameLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        canShowCallout = false
        isUserInteractionEnabled = false
        collisionMode = .circle
        displayPriority = .required
        backgroundColor = .clear
        centerOffset = CGPoint(x: 0, y: -34)
        frame = CGRect(x: 0, y: 0, width: 96, height: 72)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.shadowColor = UIColor.black.withAlphaComponent(0.28).cgColor
        iconContainer.layer.shadowOpacity = 1
        iconContainer.layer.shadowRadius = 6
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

        emojiLabel.textAlignment = .center
        emojiLabel.font = UIFont.systemFont(ofSize: 22)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false

        nameBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        nameBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.74)
        nameBackgroundView.layer.cornerRadius = 10
        nameBackgroundView.layer.borderWidth = 1

        nameLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconContainer)
        iconContainer.addSubview(emojiLabel)
        addSubview(nameBackgroundView)
        nameBackgroundView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 42),
            iconContainer.heightAnchor.constraint(equalToConstant: 42),

            emojiLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            nameBackgroundView.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 4),
            nameBackgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameBackgroundView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            nameBackgroundView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            nameLabel.topAnchor.constraint(equalTo: nameBackgroundView.topAnchor, constant: 4),
            nameLabel.bottomAnchor.constraint(equalTo: nameBackgroundView.bottomAnchor, constant: -4),
            nameLabel.leadingAnchor.constraint(equalTo: nameBackgroundView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: nameBackgroundView.trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(summary: HotVenueSummary, isHighlighted: Bool) {
        emojiLabel.text = summary.status.mapEmoji
        nameLabel.text = summary.venue.name

        iconContainer.backgroundColor = UIColor.black.withAlphaComponent(isHighlighted ? 0.84 : 0.74)
        iconContainer.layer.cornerRadius = isHighlighted ? 23 : 21
        iconContainer.layer.borderWidth = isHighlighted ? 2 : 1
        iconContainer.layer.borderColor = UIColor(summary.status.mapTint)
            .withAlphaComponent(isHighlighted ? 0.92 : 0.55)
            .cgColor

        nameBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(isHighlighted ? 0.82 : 0.72)
        nameBackgroundView.layer.borderColor = UIColor(summary.status.mapTint)
            .withAlphaComponent(isHighlighted ? 0.44 : 0.22)
            .cgColor

        frame.size = CGSize(width: 96, height: 76)
        iconContainer.transform = isHighlighted
            ? CGAffineTransform(scaleX: 1.095, y: 1.095)
            : .identity
        centerOffset = CGPoint(x: 0, y: -34)
    }
}

private extension PulseVenueStatus {
    var mapEmoji: String {
        switch self {
        case .hot:
            return "🔥"
        case .building:
            return "⚡️"
        case .slowingDown:
            return "↘︎"
        case .quiet:
            return "✨"
        }
    }

    var mapTint: Color {
        switch self {
        case .hot:
            return Color(red: 1.0, green: 0.43, blue: 0.25)
        case .building:
            return Color(red: 0.98, green: 0.25, blue: 0.78)
        case .slowingDown:
            return Color(red: 1.0, green: 0.76, blue: 0.3)
        case .quiet:
            return Color(red: 0.33, green: 0.84, blue: 1.0)
        }
    }
}

private struct MapVenueActionSheet: View {
    let summary: HotVenueSummary
    let distanceLabel: String?
    let onViewVenue: () -> Void
    let onCheckIn: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 42, height: 5)

                HStack {
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        PulseStatusBadge(status: summary.status)
                        PulseSignalConfidenceBadge(confidence: summary.confidence)

                        if !summary.recentVibes.isEmpty {
                            Text(summary.recentVibes.joined(separator: " "))
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Text(summary.venue.name)
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    Text(locationLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    Text(activityLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(summary.status.mapEmoji)
                    .font(.system(size: 28))
            }

            HStack(spacing: 10) {
                actionButton(
                    title: "View venue",
                    systemImage: "sparkles",
                    tint: Color.white.opacity(0.08),
                    foreground: .white,
                    action: onViewVenue
                )
                actionButton(
                    title: "Check-in",
                    systemImage: "location.fill",
                    tint: Color(red: 0.43, green: 0.36, blue: 1.0),
                    foreground: .white,
                    action: onCheckIn
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
    }

    private var locationLine: String {
        if let distanceLabel, !distanceLabel.isEmpty {
            return "\(summary.venue.shortLocation) • \(distanceLabel)"
        }
        return summary.venue.shortLocation
    }

    private var activityLine: String {
        if summary.confidence == .live {
            var parts: [String] = [summary.currentCrowdLine]

            if summary.activityCount > 0 {
                parts.append("\(summary.activityCount) check-in\(summary.activityCount == 1 ? "" : "s")")
            }

            return parts.joined(separator: " • ")
        }

        return "\(summary.currentCrowdLine) • \(summary.crowdMetaLine)"
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct BestNextStopCard: View {
    let recommendation: PulseRecommendation
    let summary: HotVenueSummary
    let distanceLabel: String?
    let onViewVenue: () -> Void
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Best Next Stop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple.opacity(0.95))

                    HStack(spacing: 10) {
                        PulseStatusBadge(status: summary.status)

                        if !summary.recentVibes.isEmpty {
                            Text(summary.recentVibes.joined(separator: " "))
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Text(summary.venue.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)

                    Text(summary.venue.shortLocation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))

                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(reasonLine)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                if let latestCheckInAt = summary.latestCheckInAt {
                    Text(PulseRelativeTimeFormatter.string(from: latestCheckInAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                reasonPill(systemImage: "person.crop.circle.badge.checkmark", value: "\(summary.friendCount)", label: "Friends")
                reasonPill(systemImage: "person.2.fill", value: "\(summary.uniquePeopleCount)", label: "People")
                reasonPill(systemImage: "bolt.fill", value: "\(summary.momentumCount)", label: "Momentum")
            }

            HStack(spacing: 10) {
                actionButton(
                    title: "View venue",
                    systemImage: "sparkles",
                    tint: .white.opacity(0.08),
                    foreground: .white,
                    action: onViewVenue
                )
                actionButton(
                    title: "Check-in",
                    systemImage: "location.fill",
                    tint: Color.purple.opacity(0.95),
                    foreground: .white,
                    action: onCheckIn
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.08, blue: 0.26),
                            Color(red: 0.07, green: 0.05, blue: 0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var reasonLine: String {
        var components: [String] = []

        if summary.friendCount > 0 {
            components.append("\(summary.friendCount) friend\(summary.friendCount == 1 ? "" : "s") there")
        } else if summary.uniquePeopleCount > 0 {
            components.append("\(summary.uniquePeopleCount) there now")
        }

        if let distanceLabel, !distanceLabel.isEmpty {
            components.append(distanceLabel)
        }

        if summary.status == .hot {
            components.append("busy now")
        } else if summary.status == .slowingDown {
            components.append("slowing down")
        } else if summary.momentumCount >= 3 || summary.status == .building {
            components.append("building fast")
        }

        if !components.isEmpty {
            return components.joined(separator: " • ")
        }

        return recommendation.subtitle
    }

    private func reasonPill(systemImage: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct HotVenueCard: View {
    let summary: HotVenueSummary
    let recentCheckIns: [NightlifeCheckIn]
    let distanceLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    PulseStatusBadge(status: summary.status)

                    Text(summary.venue.name)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(locationLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if !summary.recentVibes.isEmpty {
                        Text(summary.recentVibes.joined(separator: " "))
                            .font(.title3)
                    }

                    Text(scoreLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if !recentCheckIns.isEmpty {
                HStack(spacing: 12) {
                    PulseAvatarStack(checkIns: uniqueRecentCheckIns, maxVisible: 4, avatarSize: 30)

                    Text(presenceLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    Spacer()
                }
            }

            HStack(spacing: 10) {
                statPill(systemImage: "bolt.fill", value: "\(summary.activityCount)", title: "Check-ins")
                statPill(systemImage: "person.2.fill", value: "\(summary.uniquePeopleCount)", title: "People")
                statPill(systemImage: "person.crop.circle.badge.checkmark", value: "\(summary.friendCount)", title: "Friends")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statPill(systemImage: String, value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var scoreLabel: String {
        if let latestCheckInAt = summary.latestCheckInAt {
            return PulseRelativeTimeFormatter.string(from: latestCheckInAt)
        }
        return "No activity yet"
    }

    private var uniqueRecentCheckIns: [NightlifeCheckIn] {
        var seen = Set<String>()
        return recentCheckIns.filter { seen.insert($0.userId).inserted }
    }

    private var presenceLine: String {
        if summary.friendCount > 0 {
            return "\(summary.friendCount) friend\(summary.friendCount == 1 ? "" : "s") here now"
        }
        return "\(summary.uniquePeopleCount) here now"
    }

    private var locationLine: String {
        guard let distanceLabel, !distanceLabel.isEmpty else {
            return summary.venue.shortLocation
        }
        return "\(summary.venue.shortLocation) • \(distanceLabel)"
    }
}

@MainActor
private final class HotVenuesViewModel: ObservableObject {
    @Published private(set) var snapshot: PulseSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = FeedService.shared

    var hotVenues: [HotVenueSummary] {
        snapshot?.hotVenues ?? []
    }

    func loadIfNeeded() async {
        guard snapshot == nil, !isLoading else { return }
        await load()
    }

    func load(forceRefresh: Bool = false) async {
        isLoading = true
        if forceRefresh {
            errorMessage = nil
        }
        defer { isLoading = false }

        do {
            let currentUserId = await SupabaseManager.shared.currentUserId()
            snapshot = try await service.fetchPulseSnapshot(
                currentUserId: currentUserId,
                forceRefresh: forceRefresh
            )
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
