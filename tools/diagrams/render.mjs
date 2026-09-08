import fs from 'node:fs';
import path from 'node:path';
import { renderMermaidSVG, THEMES } from 'beautiful-mermaid';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error('usage: render.mjs <input.mmd> <output.svg>');
  process.exit(2);
}

const source = fs.readFileSync(input, 'utf8');
const svg = renderMermaidSVG(source, THEMES['github-light']);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, svg, 'utf8');
console.log(`rendered ${input} -> ${output}`);
