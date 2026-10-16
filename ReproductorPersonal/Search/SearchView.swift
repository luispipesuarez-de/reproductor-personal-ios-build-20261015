import SwiftUI

@MainActor
struct SearchView: View {
    @ObservedObject var search: SearchViewModel
    @ObservedObject var discovery: DiscoveryViewModel
    @ObservedObject var playback: PlaybackController
    @ObservedObject var library: LibraryStore
    let onPlay: () -> Void
    @State private var query = ""
    @State private var showLicense = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchControls.padding(.horizontal).padding(.bottom, 12)
                content
            }
            .navigationTitle("Buscar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showLicense = true } label: { Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Licencia de YouTubeKit")
                }
            }
            .sheet(isPresented: $showLicense) { licenseSheet }
        }
    }

    @ViewBuilder private var searchControls: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { searchField; submitButton }
        } else { HStack(spacing: 12) { searchField; submitButton } }
    }

    private var searchField: some View {
        TextField("Videos, canciones o artistas", text: $query)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($fieldFocused)
            .onSubmit(submit)
            .onChange(of: query) { search.queryChanged($0) }
            .accessibilityLabel("Buscar videos y música")
            .accessibilityIdentifier("searchField")
    }

    private var submitButton: some View {
        Button("Buscar", action: submit).frame(minHeight: 44)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("searchSubmit")
    }

    @ViewBuilder private var content: some View {
        switch search.state {
        case .idle:
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DiscoveryView(discovery: discovery, playback: playback, library: library) {
                    fieldFocused = false
                    onPlay()
                }
            } else {
                message(title: "Sigue escribiendo", detail: "Los resultados aparecen desde dos letras.", symbol: "magnifyingglass")
            }
        case .loading(let query):
            List {
                Text("Buscando «\(query)»…").foregroundStyle(.secondary)
                ForEach(0..<3) { _ in
                    VideoRow(video: Video(id: "", title: "Buscando contenido", author: "Autor"))
                        .redacted(reason: .placeholder).accessibilityHidden(true)
                }
            }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
        case .results(_, let videos):
            List {
                ForEach(Array(videos.enumerated()), id: \.offset) { _, video in
                    HStack {
                        Button {
                            fieldFocused = false
                            onPlay()
                            Task { await playback.play(video) }
                        } label: { VideoRow(video: video) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("result-\(video.id)")
                        .accessibilityHint("Reproduce este contenido")
                        VideoActionsMenu(video: video, library: library, playback: playback)
                    }
                }
            }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
        case .empty(let query):
            message(title: "No encontramos resultados", detail: "Prueba otro título o artista en lugar de «\(query)».", symbol: "magnifyingglass")
        case .failed(let query, let error):
            VStack(spacing: 16) {
                message(title: "No se pudo buscar", detail: error, symbol: "wifi.exclamationmark")
                Button("Reintentar") { Task { await search.submit(query: query) } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                Spacer()
            }
        }
    }

    private func submit() {
        fieldFocused = false
        let submittedQuery = query
        Task { await search.submit(query: submittedQuery) }
    }

    private func message(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var licenseSheet: some View {
        NavigationStack {
            ScrollView {
                Text(licenseText).font(.footnote).textSelection(.enabled).padding()
            }
            .navigationTitle("YouTubeKit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showLicense = false } }
            }
        }
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "YouTubeKit-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "YouTubeKit — Antoine Bollengier. Licencia MIT. https://github.com/b5i/YouTubeKit"
        }
        return text
    }
}

struct VideoRow: View {
    let video: Video
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                AsyncImage(url: video.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.12)).overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
                }
                .frame(width: 108, height: 61)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title).font(.headline).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                Text(video.author).font(.subheadline).foregroundStyle(.secondary)
                if let duration = video.durationText { Text(duration).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
