import SwiftUI
import UniformTypeIdentifiers

/// ## FilePicker
/// conforming to the UIViewControllerRepresentable protocol
struct FilePicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    /// Required protocol method - makeUIViewController
    /// 
    /// Creates the actual UIKit view controller (once)
    /// Sets up the initial configuration
    /// Connects the delegate to our coordinator
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType(filenameExtension: "epub") ?? UTType.data
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    /// Required protocol method - updateUIViewController
    ///
    /// Called when swiftui state changes
    /// Empty here since document picker doesn't need dynamic ui updates
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }
    
    /// Required protocol method - makeCoordinator
    ///
    /// Creates a coordinator object to handle UIKit delegate methods
    /// structs can't be delegates so Coordinator bridges UIKit callbacks to swiftUi
    func makeCoordinator() -> Coordinator {
        print("make coordinator")
        return Coordinator(onPicked: onPicked)
    }
    

    /// Coordinator helps bridge SwiftUI <-> UIKit
    ///
    /// SwiftUI structs are value types and can't be delegates. UIKit expects reference types (classes) for delegate patterns. Coordinator solves this mismatch.
    /// **NSObject**: required base class for most UIKit delegate protocols
    /// **UIDocumentPickerDelegate**: the protocol that receives file picker events
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        
        /// Stores swiftui onPicked callback function
        /// **@escaping**: The callback will be called after init returns (asynchronously)
        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked 
        }
        
        /// UIKit calls this when user selects files
        /// and we call onPicked, the onPicked closure will update swiftui state
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }

        /// UIKit calls this when user cancels selection
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("document picker was cancelled")
        }
    }
}
