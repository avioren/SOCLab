import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { renderMermaidSVG } from 'beautiful-mermaid';

const sourceDir = process.env.DIAGRAM_SOURCE_DIR ?? 'docs/diagrams/src';
const outputDir = process.env.DIAGRAM_OUTPUT_DIR ?? 'docs/diagrams/generated';

await mkdir(outputDir, { recursive: true });

const files = (await readdir(sourceDir))
  .filter((name) => name.endsWith('.mmd'))
  .sort();

if (files.length === 0) {
  throw new Error(`No Mermaid sources found in ${sourceDir}`);
}

for (const file of files) {
  const sourcePath = join(sourceDir, file);
  const targetName = `${basename(file, '.mmd')}.svg`;
  const targetPath = join(outputDir, targetName);
  const source = await readFile(sourcePath, 'utf8');
  const svg = renderMermaidSVG(source);
  await writeFile(targetPath, `${svg.trim()}\n`, 'utf8');
  console.log(`rendered ${sourcePath} -> ${targetPath}`);
}

console.log(`Rendered ${files.length} SOCLab diagram(s).`);
