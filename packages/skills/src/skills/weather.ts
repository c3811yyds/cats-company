/**
 * Built-in skill: get_weather — returns mock weather info.
 * In production this would call a real weather API.
 */

import type { Skill, SkillResult } from '../types';

export const weatherSkill: Skill = {
  name: 'get_weather',
  description: '查询指定城市的天气信息',
  parameters: {
    type: 'object',
    properties: {
      city: {
        type: 'string',
        description: '城市名称，如 北京、上海、杭州',
      },
    },
    required: ['city'],
  },

  async execute(args): Promise<SkillResult> {
    const city = (args.city as string) || '未知';
    // Mock weather data — replace with real API in production
    const conditions = ['晴', '多云', '阴', '小雨', '大风'];
    const condition = conditions[Math.floor(Math.random() * conditions.length)];
    const temp = Math.floor(Math.random() * 30) + 5;
    const humidity = Math.floor(Math.random() * 60) + 30;
    return {
      success: true,
      data: `${city}天气：${condition}，气温 ${temp}°C，湿度 ${humidity}%`,
    };
  },
};
