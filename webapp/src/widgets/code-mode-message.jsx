import React, { useState } from 'react';
import ContentBlockRenderer from './content-block-renderer';
import Avatar from './avatar';

export default function CodeModeMessage({ message, isSelf, isGroup, senderName, senderAvatarUrl, senderIsBot }) {
  const [showThinking, setShowThinking] = useState(false);

  if (!message.content_blocks || message.content_blocks.length === 0) {
    return null;
  }

  // Separate thinking blocks from text blocks
  const thinkingBlocks = message.content_blocks.filter(b => b.type === 'thinking');
  const textBlocks = message.content_blocks.filter(b => b.type === 'text');
  const otherBlocks = message.content_blocks.filter(b => b.type !== 'thinking' && b.type !== 'text');

  return (
    <div className="oc-code-mode-container">
      {/* Working section - independent, above the message */}
      {thinkingBlocks.length > 0 && (
        <div className="oc-thinking-section">
          <button
            className="oc-thinking-toggle"
            onClick={() => setShowThinking(!showThinking)}
          >
            <span className="oc-thinking-icon">🐾</span>
            <span className="oc-thinking-label">Working process</span>
            <span className={`oc-thinking-chevron ${showThinking ? 'open' : ''}`}>▼</span>
          </button>

          {showThinking && (
            <div className="oc-thinking-content-wrapper">
              {thinkingBlocks.map((block, i) => (
                <div key={i} className="oc-thinking-text">
                  {block.thinking}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Main message bubble */}
      <div className={`oc-msg ${isSelf ? 'self' : ''}`}>
        {!isSelf && (
          <Avatar
            name={senderName || message.from_name || message.from_uid}
            src={senderAvatarUrl}
            size={40}
            isBot={senderIsBot}
            className="oc-msg-avatar"
          />
        )}
        <div className="oc-msg-body">
          {isGroup && !isSelf && senderName && (
            <div className="oc-msg-sender">{senderName}</div>
          )}
          <div className="oc-msg-bubble">
            {textBlocks.map((block, i) => (
              <ContentBlockRenderer key={i} block={block} />
            ))}
            {otherBlocks.map((block, i) => (
              <ContentBlockRenderer key={`other-${i}`} block={block} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
