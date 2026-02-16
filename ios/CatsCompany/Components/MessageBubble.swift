import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var onReply: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            if !isMe {
                AvatarView(name: message.fromUid, size: 32)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(message.fromUid)
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
                    } placeholder: {
                        ProgressView()
                            .frame(width: 100, height: 100)
                    }
                } else if rich.type == "file" {
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(rich.fileName ?? "文件")
                                .font(.subheadline.bold())
                            if let size = rich.fileSize {
                                Text(formatFileSize(size))
                                    .font(.caption)
                            }
                        }
                    }
                } else if rich.type == "link" || rich.type == "card" {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = rich.title {
                            Text(title).font(.subheadline.bold())
                        }
                        if let desc = rich.description {
                            Text(desc).font(.caption).lineLimit(2)
                        }
                        if let imgUrl = rich.imageUrl, let url = URL(string: imgUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                                    .frame(maxHeight: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } placeholder: { EmptyView() }
                        }
                    }
                } else {
                    Text(rich.text ?? rich.title ?? "")
                        .font(.body)
                }
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }
}
