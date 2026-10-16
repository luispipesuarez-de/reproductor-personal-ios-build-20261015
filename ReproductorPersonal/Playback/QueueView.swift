import SwiftUI

@MainActor
struct QueueView: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if playback.queue.entries.isEmpty { Text("Añade contenido desde Buscar para formar tu cola.").foregroundStyle(.secondary) }
                ForEach(playback.queue.entries) { entry in
                    Button { Task { await playback.playQueueEntry(id: entry.id) } } label: {
                        HStack(spacing: 12) {
                            if playback.queue.current?.id == entry.id {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).accessibilityLabel("Selección actual")
                            }
                            VideoRow(video: entry.video)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reproduce esta entrada de la cola")
                }
                .onDelete { offsets in
                    let ids = offsets.map { playback.queue.entries[$0].id }
                    Task { for id in ids { await playback.removeQueueEntry(id: id) } }
                }
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: playback.shuffleUpcoming) {
                        Image(systemName: "shuffle").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Mezclar próximos elementos")
                    .disabled(playback.queue.upcomingCount < 2)
                }
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }
}
