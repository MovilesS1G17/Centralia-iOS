import SwiftUI

struct LibraryHeader: View {
    let presentSave: () -> Void

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            Image("CentraliaMark")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            Text("Centralia")
                .font(CentraliaTheme.Typography.brand)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: presentSave) {
                Image(systemName: "plus")
                    .font(.title2.weight(.regular))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.centraliaInk, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityLabel("Save a short")
        }
    }
}

struct LibrarySearchEntry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CentraliaTheme.Spacing.medium) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)

                Text("Search your library")
                    .font(.body)

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.centraliaSecondaryText)
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityHint("Opens Global Search")
    }
}

struct LibraryFilterChip: View {
    let filter: LibrarySourceFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(filter.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.centraliaInk)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(minHeight: 44)
                .background(
                    isSelected ? Color.centraliaInk : Color.centraliaSoftSurface,
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule()
                            .stroke(Color.centraliaDivider, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FolderShortcut: View {
    let folder: LibraryFolder
    let itemCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                Image(systemName: folder.symbolName)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("\(itemCount) \(itemCount == 1 ? "short" : "shorts")")
                        .font(.caption)
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
            }
            .foregroundStyle(Color.centraliaInk)
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .frame(minHeight: 58)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CentraliaPressStyle())
    }
}

struct LibraryVideoCard: View {
    let video: VideoItem
    let styleIndex: Int
    let isPlaying: Bool
    let openDetail: () -> Void
    let togglePlayback: () -> Void
    let requestMove: () -> Void
    let requestDelete: () -> Void

    @ScaledMetric(relativeTo: .body) private var previewHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var metadataHeight: CGFloat = 76

    private var cardColor: Color {
        [
            .centraliaVideoSand,
            .centraliaVideoMint,
            .centraliaVideoClay,
            .centraliaVideoLavender
        ][styleIndex % 4]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button(action: openDetail) {
                    cardColor
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(video.displayTitle)")

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.centraliaInk.opacity(0.92), in: Circle())
                }
                .buttonStyle(CentraliaPressStyle())
                .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

                Text(video.platform.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.centraliaInk)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Color.centraliaSurface.opacity(0.94), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)

                Text(video.formattedDuration)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 28)
                    .background(Color.centraliaInk.opacity(0.88), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }

            ZStack(alignment: .bottomTrailing) {
                Button(action: openDetail) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(video.displayTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.centraliaInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(video.creator)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .lineLimit(1)
                            .padding(.trailing, 36)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Move to Folder", systemImage: "folder") {
                        requestMove()
                    }

                    ShareLink(
                        item: video.sourceURL,
                        subject: Text(video.displayTitle),
                        message: Text("\(video.displayTitle) — \(video.creator)")
                    ) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        requestDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .tint(Color.centraliaSecondaryText)
                .accessibilityLabel("More actions for \(video.displayTitle)")
            }
            .frame(height: metadataHeight)
            .padding(.trailing, 4)
        }
        .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MoveVideoSheet: View {
    let video: VideoItem
    let folders: [LibraryFolder]
    let move: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    move(nil)
                    dismiss()
                } label: {
                    Label("Unorganized", systemImage: "tray")
                }

                ForEach(folders) { folder in
                    Button {
                        move(folder.id)
                        dismiss()
                    } label: {
                        Label(folder.name, systemImage: folder.symbolName)
                    }
                }
            }
            .navigationTitle("Move Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct LibraryUndoToast: View {
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            Text("Video removed")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button("Undo", action: undo)
                .font(.subheadline.weight(.bold))

            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CentraliaTheme.Spacing.medium)
        .frame(minHeight: 52)
        .background(Color.centraliaInk, in: Capsule())
        .padding(.horizontal, CentraliaTheme.Spacing.medium)
        .padding(.bottom, CentraliaTheme.Spacing.small)
    }
}
