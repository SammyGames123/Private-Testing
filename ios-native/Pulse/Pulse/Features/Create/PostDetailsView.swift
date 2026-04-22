import CoreLocation
import SwiftUI
import UIKit

/// Step 3 of the create flow. Shows a preview of what the user just
/// captured, lets them add title/caption/tags, and posts.
struct PostDetailsView: View {
    let media: EditedMedia
    let onBack: () -> Void
    let onPosted: () -> Void
    let postKindTitle: String
    let submitButtonTitle: String
    let presetCategory: String?

    @State private var title = ""
    @State private var caption = ""
    @State private var tags = ""
    @State private var mapVisibility: MapMomentVisibility = .publicMap
    @State private var venueOptions: [Venue]
    @State private var selectedVenueId: String?

    @StateObject private var locationManager = PulseLocationManager()

    @State private var isPosting = false
    @State private var isLoadingVenues = false
    @State private var errorMessage: String?
    @State private var previewImage: UIImage?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && !isPosting && locationManager.currentLocation != nil
    }

    private var isVideo: Bool {
        if case .video = media.original {
            return true
        }
        return false
    }

    init(
        media: EditedMedia,
        onBack: @escaping () -> Void,
        onPosted: @escaping () -> Void,
        postKindTitle: String = "New post",
        submitButtonTitle: String = "Post",
        presetCategory: String? = nil,
        initialTitle: String = "",
        initialVenueId: String? = nil,
        availableVenues: [Venue] = []
    ) {
        self.media = media
        self.onBack = onBack
        self.onPosted = onPosted
        self.postKindTitle = postKindTitle
        self.submitButtonTitle = submitButtonTitle
        self.presetCategory = presetCategory
        _title = State(initialValue: initialTitle)
        _venueOptions = State(initialValue: availableVenues)
        _selectedVenueId = State(initialValue: initialVenueId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    previewSection
                    fieldsSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            submitBar
        }
        .navigationTitle(postKindTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Edit")
                    }
                    .foregroundStyle(.white)
                }
                .disabled(isPosting)
            }
        }
        .task(id: media) { await buildPreview() }
        .task {
            activateMapLocation()
        }
        .onDisappear {
            locationManager.setContinuousTrackingEnabled(false)
        }
        .dismissKeyboardOnTap()
        // Disable the inter-tab swipe gesture here. Horizontal swipes on
        // this screen too easily kick the user back to a different tab
        // mid-compose and they'd lose their caption.
        .pulseDisablesTabSwipe()
    }

    // MARK: - Preview

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(postKindTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                metaPill(title: isVideo ? "Video" : "Photo", tint: Color(red: 1.0, green: 0.44, blue: 0.24))
                if let presetCategory {
                    metaPill(title: presetCategory == "out-now" ? "Out Now" : "Pre's", tint: Color(red: 0.98, green: 0.25, blue: 0.78))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.07, blue: 0.48),
                            Color(red: 0.22, green: 0.16, blue: 0.74),
                            Color(red: 0.08, green: 0.42, blue: 0.94),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var previewSection: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.08))
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay {
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .overlay {
                                if isVideo {
                                    VStack(spacing: 10) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 38, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.96))

                                        Text("Ready to post")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.92))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .background(Color.black.opacity(0.34))
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .shadow(radius: 10)
                                }
                            }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            mapSection
            field(label: "TITLE", placeholder: "Say what it is", text: $title)
            field(label: "CAPTION", placeholder: "Optional", text: $caption, multiline: true)
            field(label: "TAGS", placeholder: "music, travel, food", text: $tags)
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .foregroundStyle(locationReady ? .green : .white.opacity(0.55))

                VStack(alignment: .leading, spacing: 2) {
                    Text("MAP")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(0.5)

                    Text(locationStatusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                if !locationReady {
                    Button("Retry") {
                        locationManager.refreshLocation(forceRefresh: true)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                mapAudienceChip(.publicMap)
                mapAudienceChip(.mutuals)
            }
        }
    }

    private var locationReady: Bool {
        locationManager.currentLocation != nil
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return locationReady ? "Added for 24h" : "Finding location"
        case .notDetermined:
            return "Allow location"
        case .denied, .restricted:
            return "Location needed"
        @unknown default:
            return "Location needed"
        }
    }

    private func mapAudienceChip(_ visibility: MapMomentVisibility) -> some View {
        let isSelected = mapVisibility == visibility

        return Button {
            mapVisibility = visibility
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(visibility.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(visibility.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.purple.opacity(0.22) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.purple.opacity(0.82) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VENUE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)

            if isLoadingVenues && venueOptions.isEmpty {
                ProgressView()
                    .tint(.white)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        venueChip(title: "None", subtitle: nil, venueId: nil)

                        ForEach(venueOptions) { venue in
                            venueChip(
                                title: venue.name,
                                subtitle: venue.area,
                                venueId: venue.id
                            )
                        }
                    }
                }
            }
        }
    }

    private func venueChip(title: String, subtitle: String?, venueId: String?) -> some View {
        let isSelected = selectedVenueId == venueId

        return Button {
            selectedVenueId = venueId
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.purple.opacity(0.78) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)

            Group {
                if multiline {
                    TextField(placeholder, text: text, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.body)
            .foregroundStyle(.white)
            .tint(.accentColor)
            .autocorrectionDisabled(label == "TAGS")
            .textInputAutocapitalization(label == "TAGS" ? .never : .sentences)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.12))
            )
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                if isPosting {
                    ProgressView().tint(.white)
                } else {
                    Text(submitButtonTitle)
                        .font(.body.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                canSubmit
                    ? LinearGradient(
                        colors: [
                            Color(red: 0.43, green: 0.28, blue: 1.0),
                            Color(red: 0.08, green: 0.48, blue: 0.95),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    : LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            submitButton
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .background(Color.black.opacity(0.94))
        }
    }

    private func metaPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.26))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
    }

    // MARK: - Actions

    private func buildPreview() async {
        switch media.original {
        case .photo:
            let image = media.photoPreviewImage()
            await MainActor.run { previewImage = image }

        case .video:
            let duration = await media.videoDuration()
            let image = await media.thumbnailImage(at: media.resolvedTrimRange(duration: duration).lowerBound)
            await MainActor.run { previewImage = image }
        }
    }

    private func loadVenuesIfNeeded() async {
        guard venueOptions.isEmpty else { return }
        isLoadingVenues = true
        defer { isLoadingVenues = false }

        do {
            venueOptions = try await FeedService.shared.fetchLaunchVenues(limit: FeedService.launchVenueFetchLimit)
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        guard let coordinate = locationManager.currentLocation?.coordinate else {
            errorMessage = "Turn on location so this moment can appear on the map."
            locationManager.requestLocationAccessIfNeeded()
            locationManager.refreshLocation(forceRefresh: true)
            return
        }
        isPosting = true
        errorMessage = nil

        Task {
            defer { isPosting = false }

            do {
                let preparedMedia = try await media.prepareForUpload()
                defer {
                    if let temporaryURL = preparedMedia.temporaryURL {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }
                }

                let request = CreatePostRequest(
                    title: trimmedTitle,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: presetCategory,
                    venueId: selectedVenueId,
                    tagsInput: tags.isEmpty ? nil : tags,
                    mediaData: preparedMedia.data,
                    thumbnailData: preparedMedia.thumbnailData,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mapVisibility: mapVisibility,
                    contentType: preparedMedia.contentType,
                    fileExtension: preparedMedia.fileExtension
                )
                try await CreateService.shared.createPost(request)
                media.cleanup()
                NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
                onPosted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func activateMapLocation() {
        locationManager.setContinuousTrackingEnabled(true)
        locationManager.requestLocationAccessIfNeeded()
        locationManager.refreshLocation(forceRefresh: true)
    }
}
