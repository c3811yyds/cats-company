import SwiftUI

/// A single conversation item for the chat list.
struct Conversation: Identifiable {
    let id: String // topic_id
    let name: String
    let isGroup: Bool
    let isBot: Bool
    var lastMessage: String?
    var lastTime: Date?
    var isOnline: Bool
    var avatarUrl: String?
    var peerUid: Int64? // for P2P chats
}

struct ChatListView: View {
    @ObservedObject var auth = AuthManager.shared
    @ObservedObject var ws = WebSocketManager.shared
    @State private var conversations: [Conversation] = []
    @State private var selectedTopic: Conversation?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "暂无会话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("添加好友或创建群聊开始聊天")
                    )
                } else {
                    List(conversations) { conv in
                        NavigationLink(value: conv.id) {
                            ConversationRow(conversation: conv)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadConversations() }
                }
            }
            .navigationTitle("消息")
            .navigationDestination(for: String.self) { topicId in
                if let conv = conversations.first(where: { $0.id == topicId }) {
                    ChatDetailView(topicId: conv.id, title: conv.name)
                }
            }
            .task { await loadConversations() }
            .onAppear { setupWSHandlers() }
            .onReceive(NotificationCenter.default.publisher(for: .botDeleted)) { _ in
                Task { await loadConversations() }
            }
        }
    }

    private func setupWSHandlers() {
        ws.onData = { [self] data in
            if let idx = conversations.firstIndex(where: { $0.id == data.topic }) {
                conversations[idx].lastMessage = data.content.displayText
                conversations[idx].lastTime = Date()
                let conv = conversations.remove(at: idx)
                conversations.insert(conv, at: 0)
            } else {
                Task { await loadConversations() }
            }
        }
        ws.onPres = { pres in
            if pres.what == "on", let src = pres.src {
                if let idx = conversations.firstIndex(where: { $0.id.contains(src) }) {
                    conversations[idx].isOnline = true
                }
            } else if pres.what == "off", let src = pres.src {
                if let idx = conversations.firstIndex(where: { $0.id.contains(src) }) {
                    conversations[idx].isOnline = false
                }
            }
        }
    }

    private func loadConversations() async {
        do {
            let friends = try await APIClient.shared.getFriends()
            let groups = try await APIClient.shared.getGroups()
            guard let myId = auth.currentUser?.id else { return }

            var convs: [Conversation] = []

            for friend in friends {
                let ids = [myId, friend.id].sorted()
                let topicId = "p2p_\(ids[0])_\(ids[1])"
                let msgs = try? await APIClient.shared.getMessages(topicId: topicId, limit: 1)
                convs.append(Conversation(
                    id: topicId,
                    name: friend.label,
                    isGroup: false,
                    isBot: friend.isBot,
                    lastMessage: msgs?.last?.content.displayText,
                    lastTime: nil,
                    isOnline: friend.isOnline,
                    peerUid: friend.id
                ))
            }

            for group in groups {
                let topicId = group.topicId
                let msgs = try? await APIClient.shared.getMessages(topicId: topicId, limit: 1)
                convs.append(Conversation(
                    id: topicId,
                    name: group.name,
                    isGroup: true,
                    isBot: false,
                    lastMessage: msgs?.last?.content.displayText,
                    lastTime: nil,
                    isOnline: false
                ))
            }

            conversations = convs
            isLoading = false
        } catch {
            print("Load conversations error: \(error)")
            isLoading = false
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    private var timeText: String? {
        guard let date = conversation.lastTime else { return nil }
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    name: conversation.name,
                    isBot: conversation.isBot,
                    isGroup: conversation.isGroup,
                    size: 48
                )
                if !conversation.isGroup && conversation.isOnline {
                    Circle()
                        .fill(CatColor.primary)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if conversation.isBot {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(CatColor.primary)
                    }
                    Spacer()
                    if let time = timeText {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(CatColor.textSecondary)
                    }
                }
                if let last = conversation.lastMessage {
                    Text(last)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 72 }
    }
}
