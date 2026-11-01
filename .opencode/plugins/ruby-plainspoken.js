import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const skillPath = fileURLToPath(new URL('../../skills/ruby-plainspoken/SKILL.md', import.meta.url));

export default {
  id: 'ruby-plainspoken',
  async setup(ctx) {
    const source = fs.readFileSync(skillPath, 'utf8');
    const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
    // The shared skill uses plain, single-line YAML fields.
    const name = match?.[1].match(/^name: (.+)$/m)?.[1];
    const description = match?.[1].match(/^description: (.+)$/m)?.[1];
    if (!name || !description) throw new Error(`Missing skill metadata: ${skillPath}`);

    await ctx.skill.transform((editor) => {
      if (!editor.get(name)) {
        editor.add({ id: name, name, path: skillPath, description, content: match[2] });
      }
    });
  }
};
