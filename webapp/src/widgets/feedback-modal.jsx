import React, { useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../api';

const MAX_ATTACHMENTS = 5;

const CATEGORY_OPTIONS = [
  { value: 'bug', label: '问题反馈' },
  { value: 'suggestion', label: '功能建议' },
  { value: 'other', label: '其他' },
];

export default function FeedbackModal({ onClose }) {
  const [category, setCategory] = useState('bug');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [attachments, setAttachments] = useState([]);
  const [isDragging, setIsDragging] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const attachmentsRef = useRef([]);

  const remainingSlots = MAX_ATTACHMENTS - attachments.length;
  const canSubmit = useMemo(() => description.trim().length > 0 && !submitting, [description, submitting]);

  useEffect(() => {
    attachmentsRef.current = attachments;
  }, [attachments]);

  useEffect(() => {
    return () => {
      attachmentsRef.current.forEach((item) => URL.revokeObjectURL(item.previewUrl));
    };
  }, []);

  const addFiles = (fileList) => {
    const files = Array.from(fileList || []);
    if (files.length === 0) return;

    const images = files.filter((file) => file.type && file.type.startsWith('image/'));
    if (images.length === 0) {
      setError('请上传图片截图，支持 PNG、JPG、GIF、WebP。');
      return;
    }

    const nextImages = images.slice(0, remainingSlots);
    if (nextImages.length === 0) {
      setError(`最多上传 ${MAX_ATTACHMENTS} 张截图。`);
      return;
    }

    setAttachments((prev) => [
      ...prev,
      ...nextImages.map((file) => ({
        id: `${file.name}-${file.lastModified}-${Math.random().toString(16).slice(2)}`,
        file,
        previewUrl: URL.createObjectURL(file),
      })),
    ]);
    setError(images.length > nextImages.length ? `最多上传 ${MAX_ATTACHMENTS} 张截图，已保留前 ${MAX_ATTACHMENTS} 张。` : '');
  };

  const removeAttachment = (id) => {
    setAttachments((prev) => {
      const target = prev.find((item) => item.id === id);
      if (target) URL.revokeObjectURL(target.previewUrl);
      return prev.filter((item) => item.id !== id);
    });
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (!description.trim()) {
      setError('请先写一下问题或建议描述。');
      return;
    }

    setSubmitting(true);
    setError('');
    try {
      const uploaded = [];
      for (const item of attachments) {
        const result = await api.uploadFeedbackImage(item.file);
        uploaded.push({
          file_key: result.file_key,
          url: result.url,
          name: result.name || item.file.name,
          size: result.size || item.file.size,
          type: 'image',
        });
      }

      await api.submitFeedback({
        category,
        title: title.trim(),
        description: description.trim(),
        page_url: window.location.href,
        user_agent: navigator.userAgent,
        attachments: uploaded,
      });

      setSubmitted(true);
    } catch (err) {
      setError(err.message || '提交失败，请稍后再试。');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDrop = (event) => {
    event.preventDefault();
    setIsDragging(false);
    addFiles(event.dataTransfer.files);
  };

  return (
    <div className="oc-modal-overlay" onClick={onClose}>
      <div className="oc-modal oc-feedback-modal" onClick={(event) => event.stopPropagation()}>
        <div className="oc-modal-header">
          <h3>问题反馈与建议</h3>
          <button type="button" onClick={onClose}>×</button>
        </div>

        {submitted ? (
          <div className="oc-modal-body">
            <div className="oc-feedback-success">
              <div className="oc-feedback-success-title">已收到，谢谢你的反馈</div>
              <div className="oc-feedback-success-text">我们会结合截图和描述尽快排查处理。</div>
              <button type="button" className="oc-btn oc-btn-primary" onClick={onClose}>关闭</button>
            </div>
          </div>
        ) : (
          <form className="oc-modal-body" onSubmit={handleSubmit}>
            <div className="oc-form-group">
              <label>反馈类型</label>
              <div className="oc-feedback-category-grid">
                {CATEGORY_OPTIONS.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    className={`oc-feedback-category ${category === option.value ? 'active' : ''}`}
                    onClick={() => setCategory(option.value)}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="oc-form-group">
              <label>标题（可选）</label>
              <input
                className="oc-input"
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                maxLength={160}
                placeholder="一句话说明问题"
              />
            </div>

            <div className="oc-form-group">
              <label>描述</label>
              <textarea
                className="oc-input oc-feedback-textarea"
                value={description}
                onChange={(event) => setDescription(event.target.value)}
                maxLength={5000}
                placeholder="请描述你遇到的问题、期望效果，或复现步骤。"
              />
            </div>

            <div className="oc-form-group">
              <label>截图说明（最多 {MAX_ATTACHMENTS} 张）</label>
              <div
                className={`oc-feedback-dropzone ${isDragging ? 'dragging' : ''}`}
                onDragOver={(event) => {
                  event.preventDefault();
                  setIsDragging(true);
                }}
                onDragLeave={() => setIsDragging(false)}
                onDrop={handleDrop}
              >
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  onChange={(event) => addFiles(event.target.files)}
                />
                <div>点击选择截图，或直接拖拽图片到这里</div>
                <small>支持 PNG、JPG、GIF、WebP</small>
              </div>
            </div>

            {attachments.length > 0 && (
              <div className="oc-feedback-preview-grid">
                {attachments.map((item) => (
                  <div className="oc-feedback-preview" key={item.id}>
                    <img src={item.previewUrl} alt={item.file.name} />
                    <button type="button" onClick={() => removeAttachment(item.id)}>移除</button>
                  </div>
                ))}
              </div>
            )}

            {error && <div className="oc-bot-error compact">{error}</div>}

            <div className="oc-modal-footer">
              <button type="button" className="oc-btn oc-btn-default" onClick={onClose} disabled={submitting}>
                取消
              </button>
              <button type="submit" className="oc-btn oc-btn-primary" disabled={!canSubmit}>
                {submitting ? '提交中...' : '提交反馈'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
