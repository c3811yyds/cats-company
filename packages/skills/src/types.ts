/**
 * Skill framework types — runtime-agnostic skill interface.
 *
 * Skills can be loaded by any agent runtime: xiaoba, Claude Code,
 * OpenClaw, etc. Each runtime provides its own adapter to invoke skills.
 */

/** JSON Schema property definition (simplified). */
export interface ParamProperty {
  type: string;
  description: string;
  enum?: string[];
}

/** OpenAI-compatible function definition for tool calling. */
export interface FunctionDef {
  name: string;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, ParamProperty>;
    required?: string[];
  };
}

/** Result returned by a skill execution. */
export interface SkillResult {
  success: boolean;
  data: string;
}

/** A skill that can be registered and invoked by any agent runtime. */
export interface Skill {
  /** Unique skill name (used as function name in tool calling). */
  name: string;
  /** Human-readable description for the LLM. */
  description: string;
  /** JSON Schema for the skill's parameters. */
  parameters: FunctionDef['parameters'];
  /** Execute the skill with parsed arguments. */
  execute(args: Record<string, unknown>): Promise<SkillResult>;
}
