/**
 * @catscompany/skills — runtime-agnostic skill framework.
 *
 * Can be loaded by any agent runtime: xiaoba, Claude Code, OpenClaw, etc.
 */

export { SkillRegistry } from './registry';
export type { Skill, SkillResult, FunctionDef, ParamProperty } from './types';

// Built-in skills
export { timeSkill } from './skills/time';
export { diceSkill } from './skills/dice';
export { weatherSkill } from './skills/weather';
