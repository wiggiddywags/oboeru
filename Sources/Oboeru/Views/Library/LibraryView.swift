import SwiftUI
import SwiftData

// MARK: - Library view (Phase 1 — curated Oboeru originals)

struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @Bindable var vm: DeckListViewModel

    @State private var installingID: String? = nil
    @State private var installedIDs: Set<String> = []
    @State private var installError: String? = nil
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                deckGrid
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refreshInstalledState() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                    Text("Oboeru Library")
                        .font(.largeTitle).fontWeight(.bold)
                }
                Text("Curated decks made by the Oboeru team — install with one click.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                Text("Official")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.tint.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
    }

    // MARK: - Deck grid

    private var deckGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 20)],
            spacing: 20
        ) {
            ForEach(LibraryService.allBundles) { bundle in
                LibraryBundleCard(
                    bundle: bundle,
                    isInstalled: installedIDs.contains(bundle.id),
                    isInstalling: installingID == bundle.id,
                    onInstall: { install(bundle) }
                )
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
    }

    // MARK: - Install

    private func install(_ bundle: LibraryBundle) {
        guard !installedIDs.contains(bundle.id) else { return }
        installingID = bundle.id
        let nextOrder = (vm.topLevelDecks.map(\.sortOrder).max() ?? -1) + 1
        do {
            try LibraryService.install(bundle, into: modelContext, nextSortOrder: nextOrder)
            vm.load()
            installedIDs.insert(bundle.id)
        } catch {
            installError = error.localizedDescription
            showError = true
        }
        installingID = nil
    }

    private func refreshInstalledState() {
        let allBundleIDs = Set(LibraryService.allBundles.map(\.id))
        let installed = vm.decks.compactMap(\.libraryBundleID).filter { allBundleIDs.contains($0) }
        installedIDs = Set(installed)
    }
}

// MARK: - Bundle card

private struct LibraryBundleCard: View {

    let bundle: LibraryBundle
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top color bar
            (Color(hex: bundle.colorHex) ?? .accentColor)
                .frame(height: 5)

            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack(alignment: .top, spacing: 14) {
                    // Icon
                    Image(systemName: bundle.iconName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color(hex: bundle.colorHex) ?? .accentColor)
                        .frame(width: 52, height: 52)
                        .background((Color(hex: bundle.colorHex) ?? .accentColor).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(bundle.title)
                                .font(.title2).fontWeight(.semibold)
                            if bundle.isOfficial {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(bundle.authorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // Description
                Text(bundle.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                // Sub-deck pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bundle.subDecks, id: \.title) { sub in
                            subDeckPill(sub)
                        }
                    }
                }

                Divider()

                // Stats + Install button
                HStack(spacing: 16) {
                    statBadge("\(bundle.totalCards)", icon: "rectangle.stack")
                    statBadge("\(bundle.subDecks.count) decks", icon: "folder")

                    Spacer()

                    installButton
                }
            }
            .padding(20)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.6),
                              lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.05), radius: isHovered ? 12 : 5, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered && !isInstalled ? 1.005 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func subDeckPill(_ sub: LibrarySubDeck) -> some View {
        HStack(spacing: 5) {
            Image(systemName: sub.iconName)
                .font(.caption2)
                .foregroundStyle(Color(hex: sub.colorHex) ?? .secondary)
            Text(sub.title)
                .font(.caption).fontWeight(.medium)
            Text("·  \(sub.cards.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((Color(hex: sub.colorHex) ?? .accentColor).opacity(0.08),
                    in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder((Color(hex: sub.colorHex) ?? .accentColor).opacity(0.2), lineWidth: 1)
        )
    }

    private func statBadge(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.green)
        } else if isInstalling {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.subheadline)
            }
        } else {
            Button {
                onInstall()
            } label: {
                Label("Install", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
}
