import SwiftUI
import QuickLook

struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var onReply: (() -> Void)?

    @ObservedObject private var identities = IdentityStore.shared
    @State private var showImagePreview = false
    @State private var previewImageUrl: String?

    private var senderName: String {
        identities.displayName(forRawID: message.fromUid, fallback: message.fromUid)
    }

    private var senderAvatarURL: String? {
        identities.avatarURL(forRawID: message.fromUid)
    }

    private var senderIsBot: Bool {
        identities.isBot(forRawID: message.fromUid)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            if !isMe {
                AvatarView(name: senderName, avatarURL: senderAvatarURL, isBot: senderIsBot, size: 32)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Reply quote
                if message.replyTo != nil {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(CatColor.primary.opacity(0.6))
                            .frame(width: 2.5)
                        Text("回复消息 #\(message.replyTo!)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                // Content
                contentView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? CatColor.bubbleSelf : CatColor.bubbleOther)
                    .foregroundStyle(isMe ? CatColor.bubbleSelfText : CatColor.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CatLayout.radius))
                    .contextMenu {
                        Button { onReply?() } label: {
                            Label("回复", systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            UIPasteboard.general.string = message.content.displayText
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .fullScreenCover(isPresented: $showImagePreview) {
            ImagePreviewView(urlString: previewImageUrl) {
                showImagePreview = false
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .font(.body)

        case .rich(let rich):
            VStack(alignment: .leading, spacing: 6) {
                if rich.type == "image", let urlStr = rich.url ?? rich.imageUrl {
                    let fullUrl = urlStr.hasPrefix("http") ? urlStr : APIClient.shared.baseURL + urlStr
                    AsyncImage(url: URL(string: fullUrl)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                previewImageUrl = fullUrl
                                showImagePreview = true
                            }
                    } placeholder: {
                        ProgressView()
                            .frame(width: 100, height: 100)
                    }
                } else if rich.type == "file" {
                    FileContentView(rich: rich)
                } else if rich.type == "link" || rich.type == "card" || rich.type == "link_preview" {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = rich.title {
                            Text(title).font(.subheadline.bold())
                        }
                        if let desc = rich.description {
                            Text(desc).font(.caption).lineLimit(2)
                        }
                        if let imgUrl = rich.imageUrl {
                            let fullUrl = imgUrl.hasPrefix("http") ? imgUrl : APIClient.shared.baseURL + imgUrl
                            if let url = URL(string: fullUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                                    .frame(maxHeight: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } placeholder: { EmptyView() }
                            }
                        }
                    }
                } else {
                    Text(rich.text ?? rich.title ?? "")
                        .font(.body)
                }
            }
        }
    }
}

// MARK: - File Content View

struct FileContentView: View {
    let rich: RichContent
    @State private var isDownloading = false
    @State private var previewURL: URL?
    @State private var textPreview: TextPreviewFile?
    @State private var sharedFile: SharedPreviewFile?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.title)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(rich.fileName ?? "文件")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let size = rich.fileSize {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isPreviewable {
                        Text("· 可预览")
                            .font(.caption)
                            .foregroundStyle(CatColor.primary)
                    }
                }
            }

            Spacer()

            if isDownloading {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else {
                HStack(spacing: 8) {
                    if isPreviewable {
                        Button {
                            openFile()
                        } label: {
                            Image(systemName: "eye.circle.fill")
                                .font(.title2)
                                .foregroundStyle(CatColor.primary)
                        }
                    }

                    Button {
                        shareFile()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(CatColor.primary)
                    }
                }
            }
        }
        .frame(minWidth: 180, maxWidth: 240)
        .onTapGesture {
            if isPreviewable && !isDownloading {
                openFile()
            }
        }
        .contextMenu {
            if isPreviewable {
                Button {
                    openFile()
                } label: {
                    Label("预览", systemImage: "eye")
                }
            }

            Button {
                shareFile()
            } label: {
                Label("下载/分享", systemImage: "square.and.arrow.down")
            }
        }
        .quickLookPreview($previewURL)
        .sheet(item: $textPreview) { file in
            TextFilePreviewSheet(file: file) {
                sharedFile = SharedPreviewFile(url: file.url)
            }
        }
        .sheet(item: $sharedFile) { item in
            ShareSheet(items: [item.url])
        }
        .alert("文件打开失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var isPreviewable: Bool {
        isTextPreviewable || isQuickLookPreviewable
    }

    private var fileExtension: String {
        let name = rich.fileName ?? rich.url ?? ""
        return URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    private var isMarkdown: Bool {
        ["md", "markdown"].contains(fileExtension)
    }

    private var isTextPreviewable: Bool {
        ["md", "markdown", "txt", "json", "csv", "xml", "log", "yml", "yaml"].contains(fileExtension)
    }

    private var isQuickLookPreviewable: Bool {
        ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt",
         "rtf", "png", "jpg", "jpeg", "gif", "heic", "webp"].contains(fileExtension)
    }

    private var fileIcon: String {
        guard let name = rich.fileName?.lowercased() else { return "doc.fill" }
        if name.hasSuffix(".pdf") { return "doc.text.fill" }
        if name.hasSuffix(".docx") || name.hasSuffix(".doc") { return "doc.richtext.fill" }
        if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") || name.hasSuffix(".csv") { return "tablecells.fill" }
        if name.hasSuffix(".pptx") || name.hasSuffix(".ppt") { return "rectangle.fill.on.rectangle.fill" }
        if name.hasSuffix(".zip") || name.hasSuffix(".rar") { return "doc.zipper" }
        if name.hasSuffix(".mp3") || name.hasSuffix(".wav") { return "music.note" }
        if name.hasSuffix(".mp4") || name.hasSuffix(".mov") { return "video.fill" }
        if name.hasSuffix(".txt") || name.hasSuffix(".rtf") || name.hasSuffix(".md") || name.hasSuffix(".json") {
            return "doc.plaintext.fill"
        }
        return "doc.fill"
    }

    private var iconColor: Color {
        guard let name = rich.fileName?.lowercased() else { return CatColor.primary }
        if name.hasSuffix(".pdf") { return .red }
        if name.hasSuffix(".docx") || name.hasSuffix(".doc") { return .blue }
        if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") || name.hasSuffix(".csv") { return .green }
        if name.hasSuffix(".pptx") || name.hasSuffix(".ppt") { return .orange }
        return CatColor.primary
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }

    private func resolveFullURL() -> URL? {
        guard let urlStr = rich.url else { return nil }
        let full = urlStr.hasPrefix("http") ? urlStr : APIClient.shared.baseURL + urlStr
        return URL(string: full)
    }

    private func openFile() {
        Task {
            await withDownloadTask {
                let localURL = try await ensureLocalFile()
                if isTextPreviewable {
                    textPreview = try buildTextPreview(from: localURL)
                } else {
                    previewURL = localURL
                }
            }
        }
    }

    private func shareFile() {
        Task {
            await withDownloadTask {
                let localURL = try await ensureLocalFile()
                sharedFile = SharedPreviewFile(url: localURL)
            }
        }
    }

    @MainActor
    private func withDownloadTask(_ operation: @escaping () async throws -> Void) async {
        guard !isDownloading else { return }
        guard resolveFullURL() != nil else {
            errorMessage = "文件地址缺失，当前消息还不能下载。"
            return
        }

        isDownloading = true
        defer { isDownloading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            print("File open/share error: \(error)")
        }
    }

    private func ensureLocalFile() async throws -> URL {
        guard let remoteURL = resolveFullURL() else {
            throw FilePreviewError.missingURL
        }

        let destinationURL = cachedFileURL(for: remoteURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }

    private func cachedFileURL(for remoteURL: URL) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let downloadsDir = cachesDir.appendingPathComponent("ChatDownloads", isDirectory: true)

        let displayName = rich.fileName?.replacingOccurrences(of: "/", with: "_") ?? remoteURL.lastPathComponent
        let displayURL = URL(fileURLWithPath: displayName)
        let basename = displayURL.deletingPathExtension().lastPathComponent
        let ext = displayURL.pathExtension
        let uniquePrefix = remoteURL.deletingPathExtension().lastPathComponent
        let finalName = ext.isEmpty ? "\(uniquePrefix)_\(basename)" : "\(uniquePrefix)_\(basename).\(ext)"

        return downloadsDir.appendingPathComponent(finalName)
    }

    private func buildTextPreview(from localURL: URL) throws -> TextPreviewFile {
        let data = try Data(contentsOf: localURL)
        guard !data.isEmpty else {
            throw FilePreviewError.emptyFile
        }

        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return TextPreviewFile(
            title: rich.fileName ?? localURL.lastPathComponent,
            text: text,
            isMarkdown: isMarkdown,
            url: localURL
        )
    }
}

// MARK: - Image Preview View

struct ImagePreviewView: View {
    let urlString: String?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let urlStr = urlString, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .gesture(
                            TapGesture(count: 1)
                                .onEnded { onDismiss() }
                        )
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

private struct TextPreviewFile: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let isMarkdown: Bool
    let url: URL
}

private struct SharedPreviewFile: Identifiable {
    let id = UUID()
    let url: URL
}

private enum FilePreviewError: LocalizedError {
    case missingURL
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "文件链接还没解析出来，请重新进入会话后再试。"
        case .emptyFile:
            return "文件内容为空。"
        }
    }
}

private struct TextFilePreviewSheet: View {
    let file: TextPreviewFile
    let onShare: () -> Void

    private var markdownContent: AttributedString? {
        guard file.isMarkdown else { return nil }
        return try? AttributedString(markdown: file.text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let markdownContent {
                        Text(markdownContent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(file.text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding(16)
            }
            .background(CatColor.chatBg)
            .navigationTitle(file.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
