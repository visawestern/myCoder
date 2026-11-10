import SwiftUI
import AppKit

struct AttachedFilesStrip: View {
    @Binding var attachedFiles: [FileInfo]
    @State private var hoveredFileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if !attachedFiles.isEmpty {
                HStack {
                    Text(attachedFiles.count == 1 ? L.t(AppLocalizationKey.locFileAttached, attachedFiles.count) : L.t(AppLocalizationKey.locFilesAttached, attachedFiles.count))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textMuted)
                    Spacer()
                    Button(action: { attachedFiles.removeAll() }) {
                        Text(L.t(AppLocalizationKey.locClearAll))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedFiles) { file in
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(for: file))
                                    .interfaceFont(size: 12)
                                    .foregroundColor(Color.mimo.brand)

                                Text(file.name)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textSecondary)
                                    .lineLimit(1)

                                if hoveredFileID == file.id, let path = file.path {
                                    Button(action: { revealInFinder(path) }) {
                                        Image(systemName: "folder")
                                            .interfaceFont(size: 10)
                                            .foregroundColor(Color.mimo.textMuted)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .help(L.t(AppLocalizationKey.locShowInFinder))
                                }

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        attachedFiles.removeAll { $0.id == file.id }
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .interfaceFont(size: 12)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                .buttonStyle(HandCursorButtonStyle())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.mimo.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(hoveredFileID == file.id ? Color.mimo.brand : Color.clear, lineWidth: 1)
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredFileID = hovering ? file.id : nil
                                }
                            }
                            .onTapGesture(count: 2) {
                                if let path = file.path {
                                    revealInFinder(path)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()
            }
        }
        .background(attachedFiles.isEmpty ? Color.clear : Color.mimo.surface.opacity(0.5))
    }

    private func fileIcon(for file: FileInfo) -> String {
        switch file.type {
        case .swift, .python, .javascript, .typescript, .dart: return "chevron.left.forwardslash.chevron.right"
        case .json, .yaml: return "curlybraces"
        case .markdown: return "doc.richtext"
        case .html, .css: return "globe"
        case .unknown:
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ClipboardPasteLogic.imageExtensions.contains(ext) { return "photo" }
            if ext == "pdf" { return "doc.fill" }
            return "doc"
        }
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

struct ImagePreviewStrip: View {
    @Binding var attachedImages: [ClipboardImage]
    @State private var hoveredImageID: UUID?
    @State private var previewImage: ClipboardImage?
    
    var body: some View {
        VStack(spacing: 0) {
            if !attachedImages.isEmpty {
                HStack {
                    Text(attachedImages.count == 1 ? L.t(AppLocalizationKey.locPhotoAttached, attachedImages.count) : L.t(AppLocalizationKey.locPhotosAttached, attachedImages.count))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textMuted)
                    Spacer()
                    Button(action: { attachedImages.removeAll() }) {
                        Text(L.t(AppLocalizationKey.locClearAll))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedImages) { img in
                            if let data = Data(base64Encoded: img.base64),
                               let nsImage = NSImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(hoveredImageID == img.id ? Color.mimo.brand : Color.clear, lineWidth: 2)
                                        )
                                        .onHover { hovering in
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                hoveredImageID = hovering ? img.id : nil
                                            }
                                        }
                                        .onTapGesture {
                                            previewImage = img
                                        }
                                    
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            attachedImages.removeAll { $0.id == img.id }
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .interfaceFont(size: 14)
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.5), radius: 2)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .offset(x: 6, y: -6)
                                    .opacity(hoveredImageID == img.id ? 1 : 0.7)
                                }
                                .frame(width: 80, height: 80)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
            }
        }
        .background(attachedImages.isEmpty ? Color.clear : Color.mimo.surface.opacity(0.5))
        .sheet(item: $previewImage) { img in
            ImagePreviewSheet(image: img, attachedImages: $attachedImages, onDismiss: { previewImage = nil })
        }
    }
}

struct ImagePreviewSheet: View {
    let image: ClipboardImage
    @Binding var attachedImages: [ClipboardImage]
    let onDismiss: () -> Void
    
    var body: some View {
        if let data = Data(base64Encoded: image.base64),
           let nsImage = NSImage(data: data) {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text(L.t(AppLocalizationKey.locImagePreview))
                        .interfaceFont(size: 14, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .interfaceFont(size: 18)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600, maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                
                HStack(spacing: 12) {
                    Button(action: {
                        if let idx = attachedImages.firstIndex(where: { $0.id == image.id }) {
                            attachedImages.remove(at: idx)
                        }
                        onDismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .interfaceFont(size: 12)
                            Text(L.t(AppLocalizationKey.locRemove))
                                .interfaceFont(size: 12)
                        }
                        .foregroundColor(.red)
                .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    
                    Button(action: onDismiss) {
                        Text(L.t(AppLocalizationKey.locKeep))
                            .interfaceFont(size: 12, weight: .medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.mimo.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.bottom, 16)
            }
            .frame(width: 640, height: 600)
            .background(Color.mimo.background)
        } else {
            VStack {
                Text(L.t(AppLocalizationKey.locCannotPreviewImage))
                    .foregroundColor(Color.mimo.textMuted)
                Button(L.t(AppLocalizationKey.locClose)) { onDismiss() }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
            }
            .frame(width: 300, height: 200)
            .background(Color.mimo.background)
        }
    }
}

struct CompactChatPromptField: View {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void
    var focusRequest: Int = 0
    var maxHeightOverride: CGFloat? = nil

    var body: some View {
        CompactMessageTextField(
            text: $text,
            placeholder: placeholder,
            onSubmit: onSubmit,
            compactSingleLine: true,
            focusRequest: focusRequest,
            maxHeightOverride: maxHeightOverride
        )
    }
}



/// The composer status line, turned into an upward spoiler over the full
/// context-assembly journal (user directive 2026-11-07). One line shows what
/// is happening right now; expanding it lists every action of the run, and
/// every action opens into what was requested, how it was processed and what
/// actually came back.
struct ContextAssemblyStatusPanel: View {
    let log: ContextAssemblyLogLogic.Log
    var isCompiling: Bool = false
    var currentStage: String = ""
    var isLoadingMessages: Bool = false
    @State private var isExpanded = false
    @State private var expandedEntryID: UUID?

    private var showsJournal: Bool { log.hasEntries || isCompiling }

    var body: some View {
        if showsJournal {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    Divider().opacity(0.5)
                    journal
                }
            }
            .background(Color.mimo.surface.opacity(0.5))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.mimo.border.opacity(0.5)).frame(height: 0.5)
            }
        } else if isLoadingMessages {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(L.t(AppLocalizationKey.locLoadingMessages))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                if isCompiling {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: log.hasProblems ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(log.hasProblems ? Color.mimo.warning : Color.mimo.success)
                }
                Text(headerText)
                    .lineLimit(1)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer(minLength: 4)
                Text(L.t(AppLocalizationKey.locContextActionsCount, log.entries.count))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locContextAssemblyLog))
    }

    private var headerText: String {
        if isCompiling {
            return currentStage.isEmpty ? L.t(AppLocalizationKey.locCompilingPointContext) : currentStage
        }
        if !log.summary.isEmpty { return log.summary }
        return currentStage.isEmpty ? L.t(AppLocalizationKey.locCompilingPointContext) : currentStage
    }

    private var journal: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(log.entries) { entry in
                    ContextAssemblyEntryRow(
                        entry: entry,
                        isExpanded: expandedEntryID == entry.id
                    ) {
                        expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 260)
    }
}

/// One action of the assembly journal. Clicking it opens the three parts the
/// user asked for: what was requested, how it was processed, what came back.
struct ContextAssemblyEntryRow: View {
    let entry: ContextAssemblyLogLogic.Entry
    var isExpanded: Bool = false
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .interfaceFont(size: 10)
                        .foregroundColor(statusColor)
                    Text(entry.title)
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(statusLabel)
                        .interfaceFont(size: 10)
                        .foregroundColor(statusColor)
                    Spacer(minLength: 4)
                    if let duration = entry.durationMilliseconds {
                        Text("\(duration) мс")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .interfaceFont(size: 8, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    detail(L.t(AppLocalizationKey.locContextRequestLabel), entry.request)
                    detail(L.t(AppLocalizationKey.locContextProcessingLabel), entry.processing)
                    detail(L.t(AppLocalizationKey.locContextResultLabel), entry.result.isEmpty ? "—" : entry.result)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
    }

    private func detail(_ label: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
            Text(body)
                .interfaceFont(size: 10, design: .monospaced)
                .foregroundColor(Color.mimo.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(Color.mimo.codeBg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statusLabel: String {
        switch entry.status {
        case .running: return L.t(AppLocalizationKey.locContextStatusRunning)
        case .done: return L.t(AppLocalizationKey.locContextStatusDone)
        case .warning: return L.t(AppLocalizationKey.locContextStatusWarning)
        case .failed: return L.t(AppLocalizationKey.locContextStatusFailed)
        case .skipped: return L.t(AppLocalizationKey.locContextStatusSkipped)
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .running: return Color.mimo.brand
        case .done: return Color.mimo.success
        case .warning: return Color.mimo.warning
        case .failed: return Color.mimo.error
        case .skipped: return Color.mimo.textMuted
        }
    }
}

struct WorkspaceDropdown: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty { return appState.workspaces }
        return appState.workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locSearchWorkspaces), text: $searchText).textFieldStyle(.plain).interfaceFont(size: 13)
            }.padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredWorkspaces) { workspace in
                        Button(action: { appState.selectWorkspace(workspace); isPresented = false }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                                Text(workspace.name).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                if appState.selectedWorkspace?.id == workspace.id {
                                    Image(systemName: "checkmark").interfaceFont(size: 12).foregroundColor(Color.mimo.brand)
                                }
                            }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(HandCursorButtonStyle())
                    }
                    Divider().padding(.vertical, 4)
                    Button(action: { openFolder() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                            Text(L.t(AppLocalizationKey.locOpenFolder)).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(HandCursorButtonStyle())
                    Button(action: { isPresented = false; appState.showRemoteConnection = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "cloud").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                            Text(L.t(AppLocalizationKey.locRemoteConnection)).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(HandCursorButtonStyle())
                }
            }
        }.frame(width: 280, height: 320)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appState.addWorkspace(path: url.path)
            isPresented = false
        }
    }
}
