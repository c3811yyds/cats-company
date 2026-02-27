/**
 * Built-in skill: get_time — returns current date/time info.
 */

import type { Skill, SkillResult } from '../types';

export const timeSkill: Skill = {
  name: 'get_time',
  description: '获取当前日期和时间信息，包括星期几、时区等',
  parameters: {
    type: 'object',
    properties: {
      timezone: {
        type: 'string',
        description: '时区名称，如 Asia/Shanghai、America/New_York。默认 Asia/Shanghai',
      },
    },
  },

  async execute(args): Promise<SkillResult> {
    const tz = (args.timezone as string) || 'Asia/Shanghai';
    try {
      const now = new Date();
      const formatted = now.toLocaleString('zh-CN', {
        timeZone: tz,
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
      });
      return { success: true, data: `当前时间（${tz}）：${formatted}` };
    } catch {
      return { success: false, data: `无效的时区: ${tz}` };
    }
  },
};
