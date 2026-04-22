import Combine
import CoreLocation
import SwiftUI
import UIKit

private let pulseComposerBackground = LinearGradient(
    colors: [
        Color(red: 0.04, green: 0.01, blue: 0.08),
        Color(red: 0.18, green: 0.05, blue: 0.34),
        Color(red: 0.22, green: 0.15, blue: 0.62),
        Color(red: 0.08, green: 0.34, blue: 0.86),
        Color(red: 0.03, green: 0.08, blue: 0.2),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct CreateView: View {
    @StateObject private var venueContextModel = QuickCheckInViewModel()
    @State private var requestedMode: PulseCreateRouteMode = .moment
    @State private var requestedVenueId: String?
    @State private var requestedNonce = UUID()

    var body: some View {
        NavigationStack {
            MomentComposerScreen(
                suggestedVenueId: venueContextModel.selectedVenueId,
                availableVenues: venueContextModel.venues,
                requestedMode: requestedMode,
                requestedVenueId: requestedVenueId,
                requestedNonce: requestedNonce
            )
            .background(pulseComposerBackground.ignoresSafeArea())
        }
        .task {
            await venueContextModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseOpenCreate)) { notification in
            guard let route = notification.object as? PulseCreateRoute else { return }
            switch route.normalizedMode {
            case .moment:
                if let venueId = route.venueId {
                    venueContextModel.selectVenue(id: venueId)
                }
                requestedMode = .moment
                requestedVenueId = route.venueId ?? venueContextModel.selectedVenueId
                requestedNonce = UUID()
            case .live:
                if let venueId = route.venueId {
                    venueContextModel.selectVenue(id: venueId)
                }
                requestedMode = .live
                requestedVenueId = route.venueId
                requestedNonce = UUID()
            case .checkIn:
                break
            }
        }
    }
}

struct CheckInView: View {
    @StateObject private var model = QuickCheckInViewModel()

    var body: some View {
        NavigationStack {
            CheckInComposerScreen(model: model)
                .background(pulseComposerBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        PulseInboxLaunchButton()
                    }
                }
        }
        .task {
            await model.loadIfNeeded()
            model.activateLocationServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseOpenCreate)) { notification in
            guard let route = notification.object as? PulseCreateRoute,
                  route.normalizedMode == .checkIn else { return }
            if let venueId = route.venueId {
                model.selectVenue(id: venueId)
            }
            model.activateLocationServices(forceRefresh: true)
        }
    }
}

private struct CheckInComposerScreen: View {
    @ObservedObject var model: QuickCheckInViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case note
    }

    private let vibeOptions = ["🔥", "🍻", "💃", "🎉", "😎"]

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard

                    if let successMessage = model.successMessage {
                        inlineMessage(successMessage, tint: .green)
                    }

                    if let errorMessage = model.errorMessage {
                        inlineMessage(errorMessage, tint: .red)
                    }

                    activeCheckInSection
                    venueSection
                    locationSection
                    vibeSection
                    noteSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            submitBar
        }
        .navigationTitle("Here")
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnTap()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check in fast")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.purple.opacity(0.95))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedVenue?.name ?? "Choose a venue")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(model.selectedVenue?.shortLocation ?? "Surfers Paradise")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    Text(model.isCheckedInToSelectedVenue ? "Checked in" : "Ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.14))
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    Image(systemName: model.verificationState.iconName)
                        .foregroundStyle(model.verificationState.tint)

                    Text(model.verificationState.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.09, blue: 0.34),
                            Color(red: 0.09, green: 0.04, blue: 0.16),
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

    @ViewBuilder
    private var activeCheckInSection: some View {
        if let activeCheckIn = model.activeCheckIn,
           let activeVenue = model.activeVenue {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Live")

                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(Color.green.opacity(0.94))
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeVenue.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            if let vibe = activeCheckIn.vibeEmoji, !vibe.isEmpty {
                                Text(vibe)
                                    .font(.caption)
                            }

                            Text(activeCheckIn.relativeTimestamp)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    Spacer()

                    Button {
                        focusedField = nil
                        Task {
                            await model.checkOut()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isCheckingOut {
                                ProgressView()
                                    .tint(.black)
                            }

                            Text(model.isCheckingOut ? "Checking out..." : "Check out")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isCheckingOut)
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Venue")

            if model.isLoading && model.venues.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.venues) { venue in
                            Button {
                                model.selectVenue(id: venue.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(venue.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)

                                    Text(venue.shortLocation)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.56))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            model.selectedVenueId == venue.id
                                                ? Color.purple.opacity(0.18)
                                                : Color.white.opacity(0.05)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            model.selectedVenueId == venue.id
                                                ? Color.purple.opacity(0.78)
                                                : Color.white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Location")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.verificationState.iconName)
                        .font(.headline)
                        .foregroundStyle(model.verificationState.tint)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.verificationState.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(model.verificationState.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        focusedField = nil
                        model.activateLocationServices(forceRefresh: true)
                    } label: {
                        Text(model.verificationState.refreshButtonTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.09))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if model.verificationState.showsSettingsButton {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("Open Settings")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Vibe")

            HStack(spacing: 10) {
                ForEach(vibeOptions, id: \.self) { vibe in
                    Button {
                        model.selectedVibe = model.selectedVibe == vibe ? nil : vibe
                        model.successMessage = nil
                    } label: {
                        Text(vibe)
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(
                                        model.selectedVibe == vibe
                                            ? Color.purple.opacity(0.22)
                                            : Color.white.opacity(0.05)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        model.selectedVibe == vibe
                                            ? Color.purple.opacity(0.78)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Note")

            TextField("Optional note", text: $model.note, axis: .vertical)
                .focused($focusedField, equals: .note)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var submitBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                focusedField = nil
                Task {
                    await model.submit()
                }
            } label: {
                HStack {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(.black)
                    }

                    Text(model.submitButtonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(model.canSubmit ? Color.white : Color.white.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)

            if !model.canSubmit {
                Text("Choose a venue and verify your location to check in.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.92), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.98))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

private struct MomentComposerScreen: View {
    let suggestedVenueId: String?
    let availableVenues: [Venue]
    let requestedMode: PulseCreateRouteMode
    let requestedVenueId: String?
    let requestedNonce: UUID
    @State private var step: Step = .camera
    @State private var momentType: MomentType = .goingOut
    @State private var activeLiveStream: LiveStream?
    @StateObject private var nearestFinder = NearestVenueFinder()

    private enum Step: Equatable {
        case camera
        case details(EditedMedia)
        case liveSetup
    }

    private enum MomentType: String, CaseIterable, Identifiable {
        // Raw values are user-facing pill labels. DB category slugs
        // ("going-out" / "out-now") are still keyed off the `category`
        // property, so renaming the label won't break existing rows.
        case goingOut = "Pre's"
        case outNow = "Out Now"

        var id: String { rawValue }

        var category: String {
            switch self {
            case .goingOut:
                return "going-out"
            case .outNow:
                return "out-now"
            }
        }

        var defaultTitle: String {
            switch self {
            case .goingOut:
                return "Pre's tonight"
            case .outNow:
                return "Out right now"
            }
        }

        var iconName: String {
            switch self {
            case .goingOut:
                return "sparkles"
            case .outNow:
                return "music.note"
            }
        }
    }

    var body: some View {
        Group {
            switch step {
            case .camera:
                ZStack(alignment: .top) {
                    CameraCaptureView(
                        onCancel: {
                            // No "intro" screen to back out to anymore — bail
                            // out of the create tab entirely by returning to
                            // the feed.
                            NotificationCenter.default.post(name: .pulseExitCreate, object: nil)
                        },
                        onCapture: { media in
                            step = .details(EditedMedia(original: media))
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)

                    intentOverlay
                        .padding(.top, 56)
                        .padding(.horizontal, 16)
                }
            case .details(let media):
                PostDetailsView(
                    media: media,
                    onBack: {
                        step = .camera
                    },
                    onPosted: {
                        step = .camera
                    },
                    postKindTitle: "New moment",
                    submitButtonTitle: "Share moment",
                    presetCategory: momentType.category,
                    initialTitle: momentType.defaultTitle,
                    initialVenueId: venueIdForDetails(),
                    availableVenues: availableVenues
                )
            case .liveSetup:
                LiveComposerView(
                    suggestedVenueId: requestedVenueId,
                    availableVenues: availableVenues,
                    onBack: {
                        step = .camera
                    },
                    onStarted: { stream in
                        activeLiveStream = stream
                    }
                )
            }
        }
        .onChange(of: requestedNonce) { _, _ in
            applyExternalRoute()
        }
        .onChange(of: momentType) { _, newValue in
            // Pre-warm location + nearest venue when the user flips to
            // Out Now, so by the time they tap capture we already have a
            // suggestion ready to pre-fill the venue chip.
            if newValue == .outNow {
                nearestFinder.activate(with: availableVenues)
            }
        }
        .onChange(of: availableVenues) { _, newValue in
            // Venues load asynchronously on the outer screen — if we already
            // activated the finder before they arrived, re-evaluate now.
            if momentType == .outNow {
                nearestFinder.updateVenues(newValue)
            }
        }
        .fullScreenCover(item: $activeLiveStream) { stream in
            LiveStreamViewerView(stream: stream, isOwner: true)
        }
    }

    /// Pill-style intent selector overlaid on the camera. Live bounces
    /// straight to the live setup screen; Pre's / Out Now stay on the
    /// camera and just flip the category the captured media will be
    /// tagged with.
    private var intentOverlay: some View {
        HStack(spacing: 8) {
            intentPill(
                title: "Live",
                systemImage: "dot.radiowaves.left.and.right",
                tint: Color(red: 1.0, green: 0.19, blue: 0.32),
                isActive: false
            ) {
                step = .liveSetup
            }

            intentPill(
                title: "Pre's",
                systemImage: "sparkles",
                tint: Color(red: 0.98, green: 0.25, blue: 0.78),
                isActive: momentType == .goingOut
            ) {
                momentType = .goingOut
            }

            intentPill(
                title: "Out Now",
                systemImage: "mappin.and.ellipse",
                tint: Color(red: 1.0, green: 0.46, blue: 0.22),
                isActive: momentType == .outNow
            ) {
                momentType = .outNow
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func intentPill(
        title: String,
        systemImage: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? tint.opacity(0.85) : Color.black.opacity(0.45))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.white.opacity(0.9) : Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func venueIdForDetails() -> String? {
        // Priority: explicit route request → nearest-venue suggestion when
        // Out Now → whatever the QuickCheckInViewModel already picked.
        if let requestedVenueId {
            return requestedVenueId
        }
        if momentType == .outNow, let nearest = nearestFinder.nearestVenue {
            return nearest.id
        }
        return suggestedVenueId
    }

    private func applyExternalRoute() {
        switch requestedMode {
        case .moment:
            step = .camera
        case .live:
            step = .liveSetup
        case .checkIn:
            break
        }
    }
}

/// Resolves the user's nearest venue from a list. Wraps `PulseLocationManager`
/// so the composer doesn't own the CoreLocation lifecycle directly — same
/// pattern as `QuickCheckInViewModel`, just scoped to "find closest" instead
/// of "verify I'm at this specific one".
@MainActor
private final class NearestVenueFinder: ObservableObject {
    @Published private(set) var nearestVenue: Venue?

    private let locationManager = PulseLocationManager()
    private var venues: [Venue] = []
    private var cancellables = Set<AnyCancellable>()
    private var isActive = false

    init() {
        locationManager.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recompute()
            }
            .store(in: &cancellables)
    }

    func activate(with venues: [Venue]) {
        self.venues = venues
        guard !isActive else {
            recompute()
            return
        }
        isActive = true
        locationManager.requestLocationAccessIfNeeded()
        locationManager.refreshLocation(forceRefresh: true)
        recompute()
    }

    func updateVenues(_ venues: [Venue]) {
        self.venues = venues
        recompute()
    }

    private func recompute() {
        guard isActive, let here = locationManager.currentLocation else {
            return
        }

        // Filter to venues with coords, compute distance, take the minimum.
        // No radius cap — we *suggest* the nearest regardless of distance so
        // users posting from home (getting-ready shots) still get a hint.
        let candidates: [(Venue, CLLocationDistance)] = venues.compactMap { venue in
            guard let lat = venue.latitude, let lon = venue.longitude else { return nil }
            let venueLoc = CLLocation(latitude: lat, longitude: lon)
            return (venue, here.distance(from: venueLoc))
        }

        nearestVenue = candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

@MainActor
private final class QuickCheckInViewModel: ObservableObject {
    @Published private(set) var venues: [Venue] = []
    @Published private(set) var selectedVenueId: String?
    @Published var selectedVibe: String?
    @Published var note = ""
    @Published private(set) var activeCheckIn: NightlifeCheckIn?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var isCheckingOut = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var verificationState: VenueVerificationState = .idle

    let locationManager = PulseLocationManager()

    private let service = FeedService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncLocationTracking()
                Task { await self?.handleLocationStateChange() }
            }
            .store(in: &cancellables)

        locationManager.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.handleLocationStateChange() }
            }
            .store(in: &cancellables)
    }

    var selectedVenue: Venue? {
        venues.first(where: { $0.id == selectedVenueId })
    }

    var activeVenue: Venue? {
        guard let activeCheckIn else { return nil }
        return venues.first(where: { $0.id == activeCheckIn.venueId }) ?? activeCheckIn.venue
    }

    var isCheckedInToSelectedVenue: Bool {
        guard let selectedVenueId else { return false }
        return activeCheckIn?.venueId == selectedVenueId
    }

    var submitButtonTitle: String {
        if isSubmitting {
            if activeCheckIn == nil {
                return "Checking in..."
            }
            return isCheckedInToSelectedVenue ? "Updating..." : "Switching..."
        }

        if activeCheckIn == nil {
            return "Check in"
        }

        return isCheckedInToSelectedVenue ? "Update check-in" : "Switch venue"
    }

    var canSubmit: Bool {
        guard !isLoading, !isSubmitting, !isCheckingOut, selectedVenueId != nil else { return false }
        if case .verified = verificationState {
            return true
        }
        return false
    }

    func loadIfNeeded() async {
        guard venues.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedVenues = try await service.fetchLaunchVenues(limit: FeedService.launchVenueFetchLimit)
            venues = loadedVenues

            if let userId = await SupabaseManager.shared.currentUserId() {
                let loadedActiveCheckIn = try await service.fetchActiveCheckIn(userId: userId)
                activeCheckIn = loadedActiveCheckIn

                if let activeVenue = loadedActiveCheckIn?.venue,
                   !venues.contains(where: { $0.id == activeVenue.id }) {
                    venues.insert(activeVenue, at: 0)
                }
            }

            if let activeCheckIn {
                selectedVenueId = activeCheckIn.venueId
            } else if selectedVenueId == nil {
                selectedVenueId = loadedVenues.first?.id
            }

            syncLocationTracking()
            await refreshVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectVenue(id: String) {
        selectedVenueId = id
        successMessage = nil

        Task {
            await refreshVerification()
        }
    }

    func activateLocationServices(forceRefresh: Bool = false) {
        locationManager.requestLocationAccessIfNeeded()
        syncLocationTracking()
        locationManager.refreshLocation(forceRefresh: forceRefresh)
    }

    func submit() async {
        guard let selectedVenueId else { return }
        guard let userId = await SupabaseManager.shared.currentUserId() else {
            errorMessage = "You need to be signed in to check in."
            return
        }

        guard case .verified = verificationState else {
            errorMessage = "We need to verify you're near the venue before we post this check-in."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let coordinate = locationManager.currentLocation?.coordinate
            let createdCheckIn = try await service.createCheckIn(
                userId: userId,
                venueId: selectedVenueId,
                vibeEmoji: selectedVibe,
                note: note,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            )

            activeCheckIn = createdCheckIn
            if let activeVenue = createdCheckIn.venue,
               !venues.contains(where: { $0.id == activeVenue.id }) {
                venues.insert(activeVenue, at: 0)
            }
            self.selectedVenueId = createdCheckIn.venueId
            syncLocationTracking()

            let venueName = (venues.first { $0.id == createdCheckIn.venueId } ?? createdCheckIn.venue)?.name ?? "your venue"
            successMessage = "You're live at \(venueName)."
            selectedVibe = nil
            note = ""

            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            activateLocationServices(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkOut() async {
        let venueName = activeVenue?.name ?? activeCheckIn?.venue?.name ?? "the venue"
        await performCheckout(successText: "Checked out of \(venueName).")
    }

    private func handleLocationStateChange() async {
        await refreshVerification()
        await evaluateAutomaticCheckoutIfNeeded()
    }

    private func refreshVerification() async {
        guard let venue = selectedVenue else {
            verificationState = .venueUnavailable
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            verificationState = .needsPermission
            return
        case .restricted, .denied:
            verificationState = .permissionDenied
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            verificationState = .needsPermission
            return
        }

        guard let currentLocation = locationManager.currentLocation else {
            verificationState = .locating
            return
        }

        guard venue.verificationAddress != nil else {
            verificationState = .venueUnavailable
            return
        }

        verificationState = .resolvingVenue

        do {
            let venueLocation = try await PulseVenueLocationResolver.shared.location(for: venue)
            let distance = currentLocation.distance(from: venueLocation)
            if distance <= venue.verificationRadiusMeters {
                verificationState = .verified(distanceMeters: distance)
            } else {
                verificationState = .tooFar(
                    distanceMeters: distance,
                    allowedMeters: venue.verificationRadiusMeters
                )
            }
        } catch {
            verificationState = .locationUnavailable
        }
    }

    private func evaluateAutomaticCheckoutIfNeeded() async {
        guard !isCheckingOut,
              let activeCheckIn,
              let venue = activeVenue,
              let currentLocation = locationManager.currentLocation,
              venue.verificationAddress != nil else {
            return
        }

        do {
            let venueLocation = try await PulseVenueLocationResolver.shared.location(for: venue)
            let distance = currentLocation.distance(from: venueLocation)
            guard activeCheckIn.isActive, distance > venue.verificationRadiusMeters else { return }
            await performCheckout(successText: "Left \(venue.name). Checked out.")
        } catch {
            return
        }
    }

    private func performCheckout(successText: String) async {
        guard !isCheckingOut, let activeCheckIn else { return }
        guard let userId = await SupabaseManager.shared.currentUserId() else {
            errorMessage = "You need to be signed in to check out."
            return
        }

        isCheckingOut = true
        errorMessage = nil
        defer { isCheckingOut = false }

        do {
            _ = try await service.checkoutCheckIn(
                checkInId: activeCheckIn.id,
                userId: userId
            )
            self.activeCheckIn = nil
            syncLocationTracking()
            successMessage = successText
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            activateLocationServices(forceRefresh: true)
            await refreshVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncLocationTracking() {
        locationManager.setContinuousTrackingEnabled(activeCheckIn != nil)
    }
}

private enum VenueVerificationState {
    case idle
    case needsPermission
    case locating
    case resolvingVenue
    case verified(distanceMeters: Double)
    case tooFar(distanceMeters: Double, allowedMeters: Double)
    case permissionDenied
    case locationUnavailable
    case venueUnavailable

    var iconName: String {
        switch self {
        case .verified:
            return "checkmark.seal.fill"
        case .tooFar:
            return "location.slash.fill"
        case .needsPermission, .permissionDenied:
            return "location.circle.fill"
        case .locating, .resolvingVenue:
            return "location.viewfinder"
        case .locationUnavailable, .venueUnavailable, .idle:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .verified:
            return .green
        case .tooFar:
            return .orange
        case .needsPermission, .permissionDenied:
            return .purple
        case .locating, .resolvingVenue:
            return .white.opacity(0.82)
        case .locationUnavailable, .venueUnavailable, .idle:
            return .red
        }
    }

    var title: String {
        switch self {
        case .verified(let distanceMeters):
            return "Location verified (\(Self.formattedDistance(distanceMeters)))"
        case .tooFar:
            return "You're too far from this venue"
        case .needsPermission:
            return "Location permission needed"
        case .permissionDenied:
            return "Location access is off"
        case .locating:
            return "Checking your location"
        case .resolvingVenue:
            return "Matching the venue location"
        case .locationUnavailable:
            return "We couldn't verify your location"
        case .venueUnavailable:
            return "This venue isn't ready for location verification"
        case .idle:
            return "Choose a venue to verify"
        }
    }

    var subtitle: String {
        switch self {
        case .verified:
            return "You're within the venue radius, so this check-in can go live."
        case .tooFar(let distanceMeters, let allowedMeters):
            return "You're about \(Self.formattedDistance(distanceMeters)) away. Move within \(Int(allowedMeters))m and try again."
        case .needsPermission:
            return "Allow location access so Spilltop can verify you're actually there."
        case .permissionDenied:
            return "Turn location back on in Settings to post verified venue check-ins."
        case .locating:
            return "Grab a fresh GPS fix so we can confirm the venue."
        case .resolvingVenue:
            return "Matching your GPS with the selected venue."
        case .locationUnavailable:
            return "Try refreshing your GPS fix and check that Location Services are enabled."
        case .venueUnavailable:
            return "Pick another launch venue for now."
        case .idle:
            return "Select a launch venue first."
        }
    }

    var refreshButtonTitle: String {
        switch self {
        case .verified:
            return "Refresh GPS"
        case .needsPermission:
            return "Enable location"
        case .permissionDenied:
            return "Try again"
        case .locating, .resolvingVenue:
            return "Refresh location"
        case .tooFar, .locationUnavailable:
            return "Check again"
        case .venueUnavailable, .idle:
            return "Refresh"
        }
    }

    var showsSettingsButton: Bool {
        if case .permissionDenied = self {
            return true
        }
        return false
    }

    private static func formattedDistance(_ meters: Double) -> String {
        PulseDistanceFormatter.compactDistance(meters)
    }
}

struct LiveComposerView: View {
    let suggestedVenueId: String?
    let availableVenues: [Venue]
    let onBack: () -> Void
    let onStarted: (LiveStream) -> Void

    @StateObject private var model: LiveComposerViewModel
    @FocusState private var titleFocused: Bool

    init(
        suggestedVenueId: String?,
        availableVenues: [Venue],
        onBack: @escaping () -> Void,
        onStarted: @escaping (LiveStream) -> Void
    ) {
        self.suggestedVenueId = suggestedVenueId
        self.availableVenues = availableVenues
        self.onBack = onBack
        self.onStarted = onStarted
        _model = StateObject(
            wrappedValue: LiveComposerViewModel(
                suggestedVenueId: suggestedVenueId,
                initialVenues: availableVenues
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard

                    if let successMessage = model.successMessage {
                        inlineMessage(successMessage, tint: .green)
                    }

                    if let errorMessage = model.errorMessage {
                        inlineMessage(errorMessage, tint: .red)
                    }

                    if let activeStream = model.activeStream {
                        activeLiveSection(stream: activeStream)
                    }

                    modeSection
                    venueSection
                    titleSection
                    helperSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            submitBar
        }
        .navigationTitle("Go Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    onBack()
                }
                .foregroundStyle(.white)
            }
        }
        .task {
            await model.loadIfNeeded()
            model.activateLocationServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { _ in
            Task {
                await model.load()
            }
        }
        .dismissKeyboardOnTap()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Go live from home or a real venue")
                .font(.title2.bold())
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                Image(systemName: model.verificationState.iconName)
                    .foregroundStyle(model.verificationState.tint)

                Text(model.verificationState.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.09, blue: 0.34),
                            Color(red: 0.09, green: 0.04, blue: 0.16),
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

    private func activeLiveSection(stream: LiveStream) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Live now")

            LiveStreamFeatureCard(
                stream: stream,
                primaryActionTitle: "Open live"
            ) {
                onStarted(stream)
            }

            Button {
                Task {
                    await model.endCurrentLive()
                }
            } label: {
                Text(model.isEnding ? "Ending live..." : "End current live")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.isEnding)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Where are you live from?")

            HStack(spacing: 10) {
                modeCard(
                    title: "Getting Ready",
                    subtitle: "Stream from home while getting ready.",
                    systemImage: "house.fill",
                    isSelected: model.entryMode == .gettingReady
                ) {
                    titleFocused = false
                    model.selectEntryMode(.gettingReady)
                }

                modeCard(
                    title: "At Venue",
                    subtitle: "Verified live from the venue.",
                    systemImage: "location.fill",
                    isSelected: model.entryMode == .atVenue
                ) {
                    titleFocused = false
                    model.selectEntryMode(.atVenue)
                }
            }
        }
    }

    @ViewBuilder
    private var venueSection: some View {
        if model.entryMode == .atVenue {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Venue")

                if model.isLoading && model.venues.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.venues) { venue in
                                venueChip(venue: venue, isSelected: venue.id == model.selectedVenueId)
                            }
                        }
                    }
                }
            }
        }
    }

    private func modeCard(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.purple.opacity(0.95) : .white.opacity(0.76))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.purple.opacity(0.14) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.purple.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func venueChip(venue: Venue, isSelected: Bool) -> some View {
        Button {
            titleFocused = false
            model.selectVenue(id: venue.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(venue.shortLocation)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.purple.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.purple.opacity(0.78) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Title")

            TextField(model.titlePlaceholder, text: $model.title)
                .focused($titleFocused)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Phase 1")

            Text(model.helperCopy)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(2)
                .padding(16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            Button {
                titleFocused = false
                Task {
                    if let stream = await model.submit() {
                        onStarted(stream)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if model.isStarting {
                        ProgressView()
                            .tint(.black)
                    }

                    Text(model.submitButtonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(model.canSubmit ? Color.white : Color.white.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(.black.opacity(0.96))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.98))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

@MainActor
private final class LiveComposerViewModel: ObservableObject {
    enum EntryMode: String, Hashable {
        case gettingReady
        case atVenue
    }

    @Published private(set) var venues: [Venue]
    @Published private(set) var selectedVenueId: String?
    @Published private(set) var entryMode: EntryMode
    @Published var title: String
    @Published private(set) var activeStream: LiveStream?
    @Published private(set) var isLoading = false
    @Published private(set) var isStarting = false
    @Published private(set) var isEnding = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var verificationState: LiveVenueVerificationState = .idle

    let locationManager = PulseLocationManager()

    private let suggestedVenueId: String?
    private let service = FeedService.shared
    private var cancellables = Set<AnyCancellable>()

    init(suggestedVenueId: String?, initialVenues: [Venue]) {
        self.suggestedVenueId = suggestedVenueId
        self.venues = initialVenues
        self.entryMode = suggestedVenueId == nil ? .gettingReady : .atVenue
        self.selectedVenueId = suggestedVenueId ?? initialVenues.first?.id
        self.title = ""

        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refreshVerification() }
            }
            .store(in: &cancellables)

        locationManager.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refreshVerification() }
            }
            .store(in: &cancellables)
    }

    var canSubmit: Bool {
        if activeStream != nil {
            return !isEnding && !isStarting
        }
        guard !isLoading, !isStarting else { return false }
        switch entryMode {
        case .gettingReady:
            return true
        case .atVenue:
            guard selectedVenueId != nil else { return false }
            guard case .verified = verificationState else { return false }
            return true
        }
    }

    var submitButtonTitle: String {
        if isStarting {
            return "Starting live..."
        }
        if activeStream != nil {
            return "Open live"
        }
        return "Start live"
    }

    var selectedVenue: Venue? {
        venues.first(where: { $0.id == selectedVenueId })
    }

    var titlePlaceholder: String {
        switch entryMode {
        case .gettingReady:
            return "Getting ready for tonight"
        case .atVenue:
            return "What's happening at the venue?"
        }
    }

    var helperCopy: String {
        switch entryMode {
        case .gettingReady:
            return "Getting Ready lives do not need venue GPS. Use them for pre-drinks, outfit checks, and the lead-up before going out."
        case .atVenue:
            return "Venue lives still require GPS verification so people cannot fake the crowd at a venue."
        }
    }

    func loadIfNeeded() async {
        guard activeStream == nil || venues.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if venues.isEmpty {
                venues = try await service.fetchLaunchVenues(limit: FeedService.launchVenueFetchLimit)
            }

            if let currentUserId = await SupabaseManager.shared.currentUserId() {
                activeStream = try await service.fetchActiveLiveStream(creatorId: currentUserId)

                if let liveVenue = activeStream?.venue,
                   !venues.contains(where: { $0.id == liveVenue.id }) {
                    venues.insert(liveVenue, at: 0)
                }

                if let activeStream {
                    entryMode = activeStream.isGettingReadyStream ? .gettingReady : .atVenue
                }
            }

            if activeStream == nil {
                successMessage = nil
            }

            if entryMode == .atVenue, selectedVenueId == nil {
                selectedVenueId = suggestedVenueId ?? activeStream?.venueId ?? venues.first?.id
            }

            hydrateTitleIfNeeded()
            syncLocationTracking(forceRefresh: false)
            await refreshVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectEntryMode(_ mode: EntryMode) {
        entryMode = mode
        successMessage = nil
        if mode == .atVenue, selectedVenueId == nil {
            selectedVenueId = suggestedVenueId ?? venues.first?.id
        }
        hydrateTitleIfNeeded(force: true)
        syncLocationTracking(forceRefresh: true)

        Task {
            await refreshVerification()
        }
    }

    func selectVenue(id: String) {
        selectedVenueId = id
        successMessage = nil
        hydrateTitleIfNeeded(force: true)

        Task {
            await refreshVerification()
        }
    }

    func activateLocationServices(forceRefresh: Bool = false) {
        syncLocationTracking(forceRefresh: forceRefresh)
    }

    func submit() async -> LiveStream? {
        if let activeStream {
            return activeStream
        }

        let selectedVenue = selectedVenue
        if entryMode == .atVenue {
            guard selectedVenue != nil else {
                errorMessage = "Choose a venue before starting live."
                return nil
            }

            guard case .verified = verificationState else {
                errorMessage = "We need to verify you're near the venue before you can go live there."
                return nil
            }
        }

        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            errorMessage = "You need to be signed in to go live."
            return nil
        }

        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveTitle: String
        if !trimmedTitle.isEmpty {
            liveTitle = trimmedTitle
        } else if entryMode == .gettingReady {
            liveTitle = "Getting ready for tonight"
        } else {
            liveTitle = "Live at \(selectedVenue?.name ?? "the venue")"
        }

        do {
            let stream = try await service.createLiveStream(
                userId: currentUserId,
                venueId: entryMode == .atVenue ? selectedVenue?.id : nil,
                title: liveTitle,
                requiresGeoVerification: entryMode == .atVenue
            )
            activeStream = stream
            successMessage = entryMode == .gettingReady
                ? "Your getting ready live is on."
                : "Live session started for \(selectedVenue?.name ?? "the venue")."
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            syncLocationTracking(forceRefresh: true)
            return stream
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func endCurrentLive() async {
        guard let activeStream else { return }
        guard !isEnding else { return }
        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            errorMessage = "You need to be signed in to end the live."
            return
        }

        isEnding = true
        errorMessage = nil
        defer { isEnding = false }

        do {
            _ = try await service.endLiveStream(
                streamId: activeStream.id,
                userId: currentUserId
            )
            self.activeStream = nil
            successMessage = "Live ended."
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            await refreshVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hydrateTitleIfNeeded(force: Bool = false) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard force || trimmed.isEmpty || trimmed.hasPrefix("Live at ") || trimmed == "Getting ready for tonight" else { return }
        switch entryMode {
        case .gettingReady:
            title = "Getting ready for tonight"
        case .atVenue:
            guard let selectedVenue else { return }
            title = "Live at \(selectedVenue.name)"
        }
    }

    private func refreshVerification() async {
        guard entryMode == .atVenue else {
            verificationState = .notRequired
            return
        }

        guard let venue = selectedVenue else {
            verificationState = .venueUnavailable
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            verificationState = .needsPermission
            return
        case .restricted, .denied:
            verificationState = .permissionDenied
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            verificationState = .needsPermission
            return
        }

        guard let currentLocation = locationManager.currentLocation else {
            verificationState = .locating
            return
        }

        guard venue.verificationAddress != nil else {
            verificationState = .venueUnavailable
            return
        }

        verificationState = .resolvingVenue

        do {
            let venueLocation = try await PulseVenueLocationResolver.shared.location(for: venue)
            let distance = currentLocation.distance(from: venueLocation)
            if distance <= venue.verificationRadiusMeters {
                verificationState = .verified(distanceMeters: distance)
            } else {
                verificationState = .tooFar(
                    distanceMeters: distance,
                    allowedMeters: venue.verificationRadiusMeters
                )
            }
        } catch {
            verificationState = .locationUnavailable
        }
    }

    private func syncLocationTracking(forceRefresh: Bool) {
        let needsVenueTracking = entryMode == .atVenue || activeStream?.requiresGeoVerification == true
        if needsVenueTracking {
            locationManager.requestLocationAccessIfNeeded()
            locationManager.setContinuousTrackingEnabled(true)
            locationManager.refreshLocation(forceRefresh: forceRefresh)
        } else {
            locationManager.setContinuousTrackingEnabled(false)
        }
    }
}

private enum LiveVenueVerificationState {
    case idle
    case notRequired
    case needsPermission
    case locating
    case resolvingVenue
    case verified(distanceMeters: Double)
    case tooFar(distanceMeters: Double, allowedMeters: Double)
    case permissionDenied
    case locationUnavailable
    case venueUnavailable

    var iconName: String {
        switch self {
        case .notRequired:
            return "house.fill"
        case .verified:
            return "checkmark.seal.fill"
        case .tooFar:
            return "location.slash.fill"
        case .needsPermission, .permissionDenied:
            return "location.circle.fill"
        case .locating, .resolvingVenue:
            return "location.viewfinder"
        case .locationUnavailable, .venueUnavailable, .idle:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notRequired:
            return Color.purple.opacity(0.92)
        case .verified:
            return Color.green.opacity(0.95)
        case .tooFar, .locationUnavailable, .venueUnavailable:
            return Color.red.opacity(0.9)
        case .needsPermission, .permissionDenied:
            return Color.orange.opacity(0.9)
        case .locating, .resolvingVenue, .idle:
            return Color.white.opacity(0.85)
        }
    }

    var title: String {
        switch self {
        case .notRequired:
            return "No venue verification needed for getting ready lives."
        case .idle:
            return "Choose a venue to get started."
        case .needsPermission:
            return "Turn on location so we can verify you're really there."
        case .locating:
            return "Finding your location..."
        case .resolvingVenue:
            return "Checking venue distance..."
        case .verified(let distanceMeters):
            return "Verified • \(PulseDistanceFormatter.compactDistance(distanceMeters)) from the venue"
        case .tooFar(let distanceMeters, let allowedMeters):
            return "Too far away • \(PulseDistanceFormatter.compactDistance(distanceMeters)) from the venue. Move within \(Int(allowedMeters))m."
        case .permissionDenied:
            return "Location access is off. Enable it to go live from a venue."
        case .locationUnavailable:
            return "Couldn't verify your location right now."
        case .venueUnavailable:
            return "This venue isn't ready for live verification yet."
        }
    }
}
