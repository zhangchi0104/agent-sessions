#!/usr/bin/env node

import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, resolve } from "node:path";

const roots = process.argv.slice(2).map((root) => resolve(root));
if (roots.length === 0) {
  process.stderr.write("error: at least one localization scan root is required.\n");
  process.exit(2);
}

const ignoreMarker = "i18n-ignore:";
const validIgnore = /\/\/\s*i18n-ignore:\s*\S/;

// Match only presentation boundaries. The expression intentionally spans
// newlines so conventional Swift formatting cannot bypass the guard.
const candidateSource = String.raw`(?:
  \b(?:Text|Button|Label|Toggle|Picker|GroupBox|TextField|SecureField|Link|Window|Menu|Section|DisclosureGroup)
    \s*\(\s*(?:verbatim\s*:\s*)?"(?:\\.|[^"\\])
  |
  \.(?:help|accessibilityLabel|accessibilityValue|accessibilityHint|navigationTitle|confirmationDialog|alert)
    \s*\(\s*"(?:\\.|[^"\\])
  |
  \bNS(?:Button|MenuItem)\s*\([^)]*?\btitle\s*:\s*"(?:\\.|[^"\\])
  |
  \bNSTextField\s*\(\s*labelWithString\s*:\s*"(?:\\.|[^"\\])
  |
  \b(?:window|alert|menuItem|[A-Za-z_][A-Za-z0-9_]*(?:Window|Alert|MenuItem))
    \s*\.\s*(?:title|messageText|informativeText|toolTip|placeholderString)
    \s*=\s*"(?:\\.|[^"\\])
)`;

const files = roots.flatMap(swiftFiles).sort();
let invalidIgnoreCount = 0;
let hardcodedCount = 0;

for (const file of files) {
  const source = readFileSync(file, "utf8");
  const lines = source.split(/\r?\n/);

  for (const [index, line] of lines.entries()) {
    if (line.includes(ignoreMarker) && !validIgnore.test(line)) {
      report(file, index + 1, "i18n-ignore must include a non-empty reason", line);
      invalidIgnoreCount += 1;
    }
  }

  const candidates = new RegExp(candidateSource.replaceAll(/\s+/g, ""), "gms");
  for (const match of source.matchAll(candidates)) {
    const lineIndex = lineIndexAt(source, match.index ?? 0);
    const current = lines[lineIndex] ?? "";
    const previous = lineIndex > 0 ? lines[lineIndex - 1] : "";
    if (validIgnore.test(current) || validIgnore.test(previous)) {
      continue;
    }

    report(
      file,
      lineIndex + 1,
      "user-facing string literal must use a generated localization symbol",
      current,
    );
    hardcodedCount += 1;
  }
}

if (invalidIgnoreCount > 0 || hardcodedCount > 0) {
  process.stderr.write(
    `\nLocalization check failed: ${hardcodedCount} hard-coded UI string(s), `
      + `${invalidIgnoreCount} invalid ignore(s).\n`,
  );
  process.stderr.write(
    "Use Localizable.xcstrings generated symbols, or add "
      + "// i18n-ignore: <reason> for intentionally invariant UI.\n",
  );
  process.exit(1);
}

process.stdout.write("Localization check passed: no unannotated user-facing string literals found.\n");

function swiftFiles(root) {
  const status = statSync(root);
  if (status.isFile()) {
    return extname(root) === ".swift" ? [root] : [];
  }
  if (!status.isDirectory()) {
    return [];
  }

  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isSymbolicLink()) {
      return [];
    }
    const path = join(root, entry.name);
    if (entry.isDirectory()) {
      return swiftFiles(path);
    }
    return entry.isFile() && extname(entry.name) === ".swift" ? [path] : [];
  });
}

function lineIndexAt(source, offset) {
  let line = 0;
  for (let index = 0; index < offset; index += 1) {
    if (source.charCodeAt(index) === 10) {
      line += 1;
    }
  }
  return line;
}

function report(file, line, message, sourceLine) {
  process.stderr.write(`${file}:${line}: ${message}\n`);
  process.stderr.write(`  ${sourceLine.trimStart()}\n`);
}
