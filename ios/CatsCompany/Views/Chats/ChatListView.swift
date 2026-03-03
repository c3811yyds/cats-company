import SwiftUI

extension Notification.Name {
    static let conversationListChanged = Notification.Name("conversationListChanged")
    static let contactsDataChanged = Notification.Name("contactsDataChanged")
}

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
    var latestSeq: Int?
}

struct ChatListView: View {
    @ObservedObject var ws = WebSocketManager.shared
    @ObservedObject var auth = AuthManager.shared
    @ObservedObject private var identities = IdentityStore.shared
    @State private var conversations: [Conversation] = []
    @State private var selectedTopic: Conversation?
    @State private var isLoading = true
    @State private var dataListenerID: WebSocketManager.ListenerID?
    @State private var presenceListenerID: WebSocketManager.ListenerID?

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteConversation(conv)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
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
            .onDisappear { clearWSHandlers() }
            .onReceive(NotificationCenter.default.publisher(for: .botDeleted)) { _ in
                Task { await loadConversations() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .conversationListChanged)) { _ in
                Task { await loadConversations() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .contactsDataChanged)) { _ in
                Task { await loadConversations() }
            }
        }
    }

    private func setupWSHandlers() {
        guard dataListenerID == nil, presenceListenerID == nil else { return }

        dataListenerID = ws.addDataListener { [self] data in
            MessageStore.shared.unhideConversation(topic: data.topic)
            if let idx = conversations.firstIndex(where: { $0.id == data.topic }) {
                conversations[idx].lastMessage = data.content.displayText
                conversations[idx].lastTime = Date()
                conversations[idx].latestSeq = data.seq
                let conv = conversations.remove(at: idx)
                conversations.insert(conv, at: 0)
            } else {
                Task { await loadConversations() }
            }
        }

        presenceListenerID = ws.addPresenceListener { pres in
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

    private func clearWSHandlers() {
        ws.removeDataListener(dataListenerID)
        ws.removePresenceListener(presenceListenerID)
        dataListenerID = nil
        presenceListenerID = nil
    }

    private func loadConversations() async {
        do {
            async let summariesTask = APIClient.shared.getConversations()
            async let friendsTask = APIClient.shared.getFriends()
            async let groupsTask = APIClient.shared.getGroups()

            let summaries = try await summariesTask
            let friends = try await friendsTask
            let groups = try await groupsTask

            identities.upsertCurrentUser(auth.currentUser)
            identities.upsertUsers(friends)
            identities.upsertGroups(groups)

            var convsByID: [String: Conversation] = [:]

            for summary in summaries {
                if MessageStore.shared.isConversationHidden(topic: summary.id) {
                    continue
                }
                convsByID[summary.id] = makeConversation(from: summary)
            }

            for topicID in MessageStore.shared.storedTopics() {
                guard !MessageStore.shared.isConversationHidden(topic: topicID) else { continue }
                if let existing = convsByID[topicID] {
                    convsByID[topicID] = mergedWithLocalState(existing)
                } else if let localConversation = makeLocalConversation(topicID: topicID) {
                    convsByID[topicID] = localConversation
                }
            }

            conversations = convsByID.values.sorted(by: conversationSort)
            isLoading = false
        } catch {
            print("Load conversations error: \(error)")
            isLoading = false
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        MessageStore.shared.clearMessages(for: conversation.id, upToSeq: conversation.latestSeq)
        MessageStore.shared.hideConversation(topic: conversation.id)
        conversations.removeAll { $0.id == conversation.id }
    }

    private func makeConversation(from summary: APIClient.ConversationSummary) -> Conversation {
        let localMessages = MessageStore.shared.loadMessages(for: summary.id)
        let localLastMessage = localMessages.last

        return Conversation(
            id: summary.id,
            name: summary.name,
            isGroup: summary.isGroup,
            isBot: summary.isBot,
            lastMessage: summary.preview ?? localLastMessage?.content.displayText,
            lastTime: summary.lastTime ?? localLastMessage?.timestamp,
            isOnline: summary.isOnline,
            avatarUrl: summary.avatarUrl ?? localAvatarURL(for: summary.id),
            peerUid: summary.friendId ?? peerID(for: summary.id),
            latestSeq: summary.latestSeq ?? localLastMessage?.seq
        )
    }

    private func mergedWithLocalState(_ conversation: Conversation) -> Conversation {
        let localMessages = MessageStore.shared.loadMessages(for: conversation.id)
        guard let localLastMessage = localMessages.last else { return conversation }

        return Conversation(
            id: conversation.id,
            name: conversation.name,
            isGroup: conversation.isGroup,
            isBot: conversation.isBot,
            lastMessage: conversation.lastMessage ?? localLastMessage.content.displayText,
            lastTime: conversation.lastTime ?? localLastMessage.timestamp,
            isOnline: conversation.isOnline,
            avatarUrl: conversation.avatarUrl ?? localAvatarURL(for: conversation.id),
            peerUid: conversation.peerUid ?? peerID(for: conversation.id),
            latestSeq: conversation.latestSeq ?? localLastMessage.seq
        )
    }

    private func makeLocalConversation(topicID: String) -> Conversation? {
        let localMessages = MessageStore.shared.loadMessages(for: topicID)
        guard let localLastMessage = localMessages.last else { return nil }

        let isGroup = topicID.hasPrefix("grp_")
        let peerUid = peerID(for: topicID)

        return Conversation(
            id: topicID,
            name: localConversationName(for: topicID, peerUid: peerUid),
            isGroup: isGroup,
            isBot: isGroup ? false : (peerUid.flatMap { identities.usersById[$0]?.isBot } ?? false),
            lastMessage: localLastMessage.content.displayText,
            lastTime: localLastMessage.timestamp,
            isOnline: false,
            avatarUrl: localAvatarURL(for: topicID),
            peerUid: peerUid,
            latestSeq: localLastMessage.seq
        )
    }

    private func localConversationName(for topicID: String, peerUid: Int64?) -> String {
        if topicID.hasPrefix("grp_") {
            return identities.groupName(forTopic: topicID, fallback: topicID)
        }
        if let peerUid, let user = identities.usersById[peerUid] {
            return user.label
        }
        if let peerUid {
            return "用户 \(peerUid)"
        }
        return topicID
    }

    private func localAvatarURL(for topicID: String) -> String? {
        if topicID.hasPrefix("grp_") {
            return identities.groupAvatarURL(forTopic: topicID)
        }
        guard let peerUid = peerID(for: topicID) else { return nil }
        return identities.usersById[peerUid]?.avatarUrl
    }

    private func peerID(for topicID: String) -> Int64? {
        guard !topicID.hasPrefix("grp_"), let myID = auth.currentUser?.id else { return nil }
        let ids = topicID
            .replacingOccurrences(of: "p2p_", with: "")
            .split(separator: "_")
            .compactMap { Int64($0) }
        return ids.first(where: { $0 != myID })
    }

    private func conversationSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        switch (lhs.lastTime, rhs.lastTime) {
        case let (l?, r?):
            return l == r ? lhs.name < rhs.name : l > r
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs.name < rhs.name
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
                    avatarURL: conversation.avatarUrl,
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
