/**
 * SkillRegistry — manages registered skills and converts them
 * to OpenAI-compatible tool definitions for function calling.
 *
 * Runtime-agnostic: any agent runtime can use this registry.
 */

import type { Skill, FunctionDef } from './types';

export class SkillRegistry {
  private skills = new Map<string, Skill>();

  register(skill: Skill): void {
    this.skills.set(skill.name, skill);
  }

  get(name: string): Skill | undefined {
    return this.skills.get(name);
  }

  has(name: string): boolean {
    return this.skills.has(name);
  }

  /** Convert all registered skills to OpenAI tools format. */
  toTools(): Array<{ type: 'function'; function: FunctionDef }> {
    return Array.from(this.skills.values()).map((s) => ({
      type: 'function' as const,
      function: {
        name: s.name,
        description: s.description,
        parameters: s.parameters,
      },
    }));
  }

  /** List all registered skill names. */
  names(): string[] {
    return Array.from(this.skills.keys());
  }

  get size(): number {
    return this.skills.size;
  }
}
