/**
 * Built-in skill: roll_dice — roll one or more dice.
 */

import type { Skill, SkillResult } from '../types';

export const diceSkill: Skill = {
  name: 'roll_dice',
  description: '掷骰子，支持指定骰子数量和面数',
  parameters: {
    type: 'object',
    properties: {
      count: {
        type: 'number',
        description: '骰子数量（1-10），默认 1',
      },
      sides: {
        type: 'number',
        description: '每个骰子的面数（2-100），默认 6',
      },
    },
  },

  async execute(args): Promise<SkillResult> {
    const count = Math.min(10, Math.max(1, Number(args.count) || 1));
    const sides = Math.min(100, Math.max(2, Number(args.sides) || 6));
    const rolls = Array.from({ length: count }, () =>
      Math.floor(Math.random() * sides) + 1
    );
    const total = rolls.reduce((a, b) => a + b, 0);
    const detail = rolls.length > 1 ? ` (${rolls.join(' + ')})` : '';
    return {
      success: true,
      data: `掷 ${count}d${sides}：${total}${detail}`,
    };
  },
};
