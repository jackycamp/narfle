import SwiftUI
import SwiftData

struct LibraryView: View {
    @EnvironmentObject var appState: AppState 
    // @Query private var bundles: [NarfBundle]
    @Query(sort: \NarfBundle.lastOpened, order: .reverse) 
    private var bundles: [NarfBundle]

    @Environment(\.modelContext) private var modelContext
    @State private var showFilePicker = false

    var body: some View {
        VStack {
            Text("Your Library")
                .font(.title)
                .fontWeight(.bold)

            List(bundles) { bundle in 
                if let title = bundle.title {
                    Text(title)
                        .font(.headline)
                }

                Text(bundle.id.uuidString)
                    .font(.body)
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
                print("picked!")
                // TODO: once file is picked, need to process it, load it
                // and then redirect to ReaderView
                print("file picked: \(url)")
                appState.selectedFile = url
            }
        }
    }
}
