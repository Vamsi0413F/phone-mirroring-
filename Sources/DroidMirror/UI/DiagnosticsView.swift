import SwiftUI
import AppKit

public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText: String = ""
    @State private var copied: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Diagnostics")
                        .font(.headline)
                    Text("Structured debug logs for troubleshooting connection and streaming")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy Diagnostics")
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Console log text
            ScrollView {
                Text(logText.isEmpty ? "No log entries recorded." : logText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            refreshLogs()
        }
    }
    
    private func refreshLogs() {
        logText = DiagnosticsLogger.shared.exportLogs()
    }
    
    private func copyToClipboard() {
        refreshLogs()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
        
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}
