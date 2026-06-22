#if os(iOS)
import APIClient
import DesignSystem
import SwiftUI

/// A memory's full photo set, hero-first. Swipe the hero or tap a filmstrip thumb to move
/// through the set; the strip auto-scrolls to keep the selection centered. Collapses to a
/// single image (no strip, no counter) when a memory has one photo — so normal drops look
/// exactly as before.
struct MemoryPhotoGallery: View {
    let photos: [MemoryMediaItem]

    @State private var selection = 0

    private var isMulti: Bool { photos.count > 1 }

    var body: some View {
        VStack(spacing: LegacySpacing.sm) {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    AsyncImage(url: URL(string: photo.url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder(icon: "photo")
                        default:
                            placeholder(icon: nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()
                    .tag(index)
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
            .tabViewStyle(.page(indexDisplayMode: isMulti ? .automatic : .never))

            if isMulti {
                filmstrip
                Text("\(selection + 1) of \(photos.count)")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LegacySpacing.xs) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selection = index }
                        } label: {
                            AsyncImage(url: URL(string: photo.thumbnailURL ?? photo.url)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                                    .fill(LegacyColor.surface)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                                    .strokeBorder(LegacyColor.accent, lineWidth: index == selection ? 2 : 0)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            LegacyColor.surface
            if let icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(LegacyColor.textSecondary)
            } else {
                ProgressView().tint(LegacyColor.accent)
            }
        }
    }
}
#endif
