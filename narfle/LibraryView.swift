import SwiftUI
import SwiftData
import os

struct LibraryView: View {
    @EnvironmentObject var appState: AppState 
    @Query(sort: \NarfBundle.lastOpened, order: .reverse) 
    private var bundles: [NarfBundle]

    @Environment(\.modelContext) private var modelContext
    @State private var showFilePicker = false

    // TODO: route to bundle
    // TODO: display cover of bundle

    var body: some View {
        VStack {
            Text("Your Library")
                .font(.title3)
                .fontWeight(.bold)

            List {
                ForEach(bundles) { bundle in 
                    VStack(alignment: .leading) {
                        if let title = bundle.title {
                            Text(title)
                                .font(.headline)
                        }
                        
                        if let author = bundle.author {
                            Text(author)
                                .font(.caption)
                        }

                        Text(bundle.id.uuidString)
                            .font(.caption2)
                    }
                }.onDelete(perform: deleteBundle)
            }

            Button(action: { showFilePicker = true }) {
                Label("Browse files", systemImage: "folder")
                    .font(.headline)
                    .padding()
                    .cornerRadius(10)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FilePicker { url in
                appState.selectedFile = url
            }
        }
    }

    private func deleteBundle(offsets: IndexSet) {
        let logger = Logger.init()
        for index in offsets {
            let bundle: NarfBundle = bundles[index]
            modelContext.delete(bundle)
            logger.debug("Deleting bundle: \(bundle.id.uuidString)")

            // FIXME: when deleting bundle, also need to clean up any artifacts
            // in application support directory
        }

        do {
            try modelContext.save()
            logger.debug("Deletion saved.")
        } catch {
            print("Failed to delete bundle: \(error)")
            
        }
    }
}
