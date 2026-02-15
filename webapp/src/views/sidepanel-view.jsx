import React, { useState, useEffect } from 'react';
import { api, onWSMessage, updateTopicSeq } from '../api';
import t from '../i18n';
import CreateGroup from '../widgets/create-group';

export default function ChatListView({ activeTopic, onSelectTopic, user, onlineUsers }) {
  const [chats, setChats] = useState([]);
  const [search, setSearch] = useState('');
  const [showCreateGroup, setShowCreateGroup] = useState(false);

  useEffect(() => {
    loadChats();
  }, []);

  // Listen for real-time message updates and group events
  useEffect(() => {
    const unsub = onWSMessage((msg) => {
      if (msg.data) {
        const topicId = msg.data.topic;
        const content = typeof msg.data.content === 'string' ? msg.data.content : '';
        const seq = msg.data.seq;
        updateTopicSeq(topicId, seq);
        setChats((prev) => {
          // If topic already in list, update it
          const exists = prev.some((c) => c.id === topicId);
          if (exists) {
            return prev.map((c) =>
              c.id === topicId
                ? { ...c, preview: content, time: formatTime(new Date()), seq }
                : c
            );
          }
          // If it's a new group topic we haven't seen, reload
          if (topicId.startsWith('grp_')) {
            loadChats();
          }
          return prev;
        });
      }

      // Reload chat list on group events
      if (msg.pres && msg.pres.what && msg.pres.what.startsWith('group_')) {
        loadChats();
      }
      if (msg.pres && msg.pres.what === 'members_invited') {
        loadChats();
      }
    });
    return () => unsub();
  }, []);

  const loadChats = async () => {
    try {
      const [friendsRes, groupsRes] = await Promise.all([
        api.getFriends(),
        api.getGroups(),
      ]);

      const friends = friendsRes.friends || [];
      const groups = groupsRes.groups || [];

      const p2pChats = friends.map((f) => {
        const topicId = p2pTopicId(user.uid, f.id);
        return {
          id: topicId,
          friendId: f.id,
          name: f.display_name || f.username,
          preview: '',
          time: '',
          isGroup: false,
        };
      });

      const groupChats = groups.map((g) => ({
        id: `grp_${g.id}`,
        groupId: g.id,
        name: g.name,
        preview: '',
        time: '',
        isGroup: true,
      }));

      setChats([...groupChats, ...p2pChats]);
    } catch (e) {
      console.error('Failed to load chats:', e);
    }
  };

  const handleGroupCreated = () => {
    loadChats();
  };

  const filtered = chats.filter(
    (c) => c.name.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <>
      <div className="oc-header">
        {t('chats_title')}
        <button
          className="oc-header-action"
          onClick={() => setShowCreateGroup(true)}
          title={t('group_create')}
        >
          +
        </button>
      </div>
      <div className="oc-search">
        <input
          placeholder={t('chats_search_placeholder')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <div className="oc-chat-list">
        {filtered.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: '#888' }}>
            {t('chats_empty')}
          </div>
        ) : (
          filtered.map((chat) => {
            const isOnline = !chat.isGroup && onlineUsers && onlineUsers[chat.friendId];
            return (
              <div
                key={chat.id}
                className={`oc-chat-item ${activeTopic === chat.id ? 'active' : ''}`}
                onClick={() => onSelectTopic({ topicId: chat.id, name: chat.name, isGroup: chat.isGroup, groupId: chat.groupId })}
              >
                <div className="oc-chat-avatar">
                  {chat.isGroup ? (
                    <span className="oc-group-icon" aria-label="group">G</span>
                  ) : (
                    <span className={`oc-online-dot ${isOnline ? 'online' : ''}`} />
                  )}
                </div>
                <div className="oc-chat-info">
                  <div className="oc-chat-name">
                    <span>{chat.name}</span>
                    <span className="oc-chat-time">{chat.time}</span>
                  </div>
                  <div className="oc-chat-preview">
                    {chat.preview || (isOnline ? t('online') : '')}
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>

      {showCreateGroup && (
        <CreateGroup
          onClose={() => setShowCreateGroup(false)}
          onCreated={handleGroupCreated}
        />
      )}
    </>
  );
}

function p2pTopicId(uid1, uid2) {
  if (uid1 > uid2) [uid1, uid2] = [uid2, uid1];
  return `p2p_${uid1}_${uid2}`;
}

function formatTime(date) {
  const h = date.getHours().toString().padStart(2, '0');
  const m = date.getMinutes().toString().padStart(2, '0');
  return `${h}:${m}`;
}
