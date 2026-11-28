#!/usr/bin/env node
"use strict";

// Dr. Unslopovich's static detector. Reads mobile source (SwiftUI, UIKit,
// Jetpack Compose, Android XML, React Native, Expo, Flutter, Ionic) and flags
// patterns that make an app look generated or behave like a website.
// No dependencies, no network, no model. It reads code; it never runs the app.

const fs = require("fs");
const path = require("path");

const VERSION = 1;

const STACK_BY_EXT = {
  ".swift": "swift",
  ".kt": "kotlin",
  ".kts": "kotlin",
  ".dart": "dart",
  ".tsx": "js",
  ".jsx": "js",
  ".ts": "js",
  ".js": "js",
  ".mjs": "js",
  ".vue": "web",
  ".svelte": "web",
  ".astro": "web",
  ".html": "web",
  ".xml": "xml",
  ".css": "css",
  ".scss": "css",
  ".less": "css",
};

const SKIP_DIRS = new Set([
  "node_modules", ".git", "Pods", "build", "dist", ".expo", ".dart_tool",
  "DerivedData", ".gradle", ".idea", ".vscode", "coverage", "vendor", ".next",
  "www", ".unslop-anything", ".unslopovich", "Carthage", ".build", "generated", "__generated__",
]);

const TEST_FILE = /(^|[./_-])(test|tests|spec|stories|story|preview|previews|fixture|fixtures|mock|mocks)\.[a-z]+$|Tests?\.(swift|kt)$|_test\.dart$|PreviewParameterProvider\.kt$|Previews?\.(swift|kt)$/i;
const TEST_DIR = /^(?:__tests__|__mocks__|__fixtures__|test|tests|testing|fixtures|mocks|androidTest|testDebug|UITests|e2e)$/;

const SEVERITY_RANK = { critical: 0, noticeable: 1, minor: 2 };

// ---------- helpers ----------

function hexToHsl(hex) {
  const n = parseInt(hex, 16);
  const r = ((n >> 16) & 255) / 255;
  const g = ((n >> 8) & 255) / 255;
  const b = (n & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) * 60;
  else if (max === g) h = ((b - r) / d + 2) * 60;
  else h = ((r - g) / d + 4) * 60;
  return { h, s, l };
}

// Six-digit hex colors in a snippet: #RRGGBB, 0xFFRRGGBB, Color(0xRRGGBB),
// and #AARRGGBB in Android XML. #RRGGBBAA drops its alpha, and the short
// forms expand (#RGB -> #RRGGBB, #RGBA -> #RRGGBB) so alpha and short
// colors are read the same way as #RRGGBB. 0xRRGGBB is read too, after the
// 0xFF form, so an eight-digit 0xFFRRGGBB is never misread as 0xFFRRGG.
function hexColors(snippet, stack) {
  const out = [];
  const re = stack === "xml"
    ? /#(?:[0-9a-fA-F]{2})?([0-9a-fA-F]{6})\b|0x[fF]{2}([0-9a-fA-F]{6})\b|0x([0-9a-fA-F]{6})\b/g
    : /#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})\b|0x[fF]{2}([0-9a-fA-F]{6})\b|0x([0-9a-fA-F]{6})\b/g;
  let m;
  while ((m = re.exec(snippet))) {
    let hex = m[1] || m[2] || m[3];
    if (hex.length === 8) hex = hex.slice(0, 6);
    else if (hex.length === 4) hex = hex.slice(0, 3).split("").map((c) => c + c).join("");
    else if (hex.length === 3) hex = hex.split("").map((c) => c + c).join("");
    out.push(hex.toUpperCase());
  }
  return out;
}

// rgb()/rgba() and hsl()/hsla() colors in a snippet, as uppercase hex, so they can
// go through the same checks as hex stops. Commas or spaces both work
// (`rgb(124, 58, 237)`, `rgb(124 58 237 / 50%)`, `hsl(262 83% 58%)`, or Tailwind
// `rgb(124_58_237)`); alpha is ignored.
function cssFunctionColors(snippet) {
  const out = [];
  const num = "([+-]?(?:\\d+\\.?\\d*|\\.\\d+))";
  const re = new RegExp(`\\b(rgba?|hsla?)\\(\\s*${num}(%|deg|grad|rad|turn)?\\s*[,\\s_]\\s*${num}(%)?\\s*[,\\s_]\\s*${num}(%)?`, "gi");
  const hex2 = (v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0");
  let m;
  while ((m = re.exec(snippet))) {
    const [, fn, a, aUnit, b, bPct, c, cPct] = m;
    let r, g, bl;
    if (fn[0].toLowerCase() === "r") {
      const channel = (v, pct) => (pct ? (parseFloat(v) * 255) / 100 : parseFloat(v));
      [r, g, bl] = [channel(a, aUnit === "%"), channel(b, bPct), channel(c, cPct)];
    } else {
      const toDeg = { turn: 360, rad: 180 / Math.PI, grad: 0.9 }[(aUnit || "").toLowerCase()] || 1;
      const h = ((((parseFloat(a) * toDeg) % 360) + 360) % 360) / 360;
      const sat = Math.min(1, Math.max(0, parseFloat(b) / 100));
      const lig = Math.min(1, Math.max(0, parseFloat(c) / 100));
      const q = lig < 0.5 ? lig * (1 + sat) : lig + sat - lig * sat;
      const p = 2 * lig - q;
      const hue = (t) => {
        t = (t + 1) % 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
      };
      [r, g, bl] = [hue(h + 1 / 3) * 255, hue(h) * 255, hue(h - 1 / 3) * 255];
    }
    out.push((hex2(r) + hex2(g) + hex2(bl)).toUpperCase());
  }
  return out;
}

// Flutter's Color.fromARGB(a, r, g, b) and Color.fromRGBO(r, g, b, opacity) in a
// snippet, as uppercase hex, so they go through the same checks as
// Color(0xFFRRGGBB). Alpha and opacity are dropped, as they are for hex, and
// may be any expression. A channel that is not a literal (a variable, an
// expression) skips the color. Flutter keeps the low eight bits of a channel.
function flutterColors(snippet) {
  const out = [];
  const re = /\bColor\.from(ARGB|RGBO)\(/g;
  let m;
  while ((m = re.exec(snippet))) {
    const open = m.index + m[0].length - 1;
    const close = closeOf(snippet, open) - 1;
    // Split on top-level commas only: the opacity may be a call of its own.
    const args = [];
    let depth = 0;
    let start = open + 1;
    for (let i = start; i <= close; i++) {
      const c = snippet[i];
      if ("([{".includes(c)) depth++;
      else if (i === close || (c === "," && depth === 0)) {
        args.push(snippet.slice(start, i).trim());
        start = i + 1;
      } else if (")]}".includes(c)) depth--;
    }
    const rgb = m[1] === "ARGB" ? args.slice(1, 4) : args.slice(0, 3);
    if (args.length < 4 || !rgb.every((c) => /^(?:0x[0-9a-fA-F]+|\d+)$/.test(c))) continue;
    out.push(rgb.map((c) => (Number(c) & 0xff).toString(16).padStart(2, "0")).join("").toUpperCase());
  }
  return out;
}

// SwiftUI's Color(red:green:blue:) in a snippet, as uppercase hex, so it goes
// through the same checks as Color(hex: 0x7C3AED). Components run from 0 to 1
// and are often written as a fraction (124 / 255). A leading color space
// (.sRGB) and a trailing opacity are skipped; a component that is not a
// number skips the color.
function swiftRgbColors(snippet) {
  const out = [];
  const number = "\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?";
  const component = `(${number})(?:\\s*\\/\\s*(${number}))?`;
  const re = new RegExp(`\\bColor\\(\\s*(?:\\.\\w+\\s*,\\s*)?red\\s*:\\s*${component}\\s*,\\s*green\\s*:\\s*${component}\\s*,\\s*blue\\s*:\\s*${component}\\s*[,)]`, "g");
  const hex2 = (value, divisor) => {
    const unit = divisor === undefined ? Number(value) : Number(value) / Number(divisor);
    return Math.round(Math.min(1, Math.max(0, unit)) * 255).toString(16).padStart(2, "0");
  };
  let m;
  while ((m = re.exec(snippet))) {
    if ([m[2], m[4], m[6]].some((divisor) => Number(divisor) === 0)) continue;
    out.push((hex2(m[1], m[2]) + hex2(m[3], m[4]) + hex2(m[5], m[6])).toUpperCase());
  }
  return out;
}

// Jetpack Compose's Color(red = ..., green = ..., blue = ...) in a snippet,
// as uppercase hex, so it goes through the same checks as Color(0xFF7C3AED).
// Components may be ints (0 to 255) or floats (0 to 1, typically ending in f).
// A trailing alpha is skipped; a component that is not a number skips the color.
function composeColors(snippet) {
  const out = [];
  const number = "(?:\\d+(?:\\.\\d+)?|\\.\\d+)(?:[eE][+-]?\\d+)?[fF]?";
  const re = new RegExp(`\\bColor\\(\\s*red\\s*=\\s*(${number})\\s*,\\s*green\\s*=\\s*(${number})\\s*,\\s*blue\\s*=\\s*(${number})\\s*[,)]`, "g");
  let m;
  while ((m = re.exec(snippet))) {
    const raw = [m[1], m[2], m[3]];
    const isFloat = raw.some((c) => /[.fF]/.test(c));
    const hex = raw.map((c) => {
      const num = parseFloat(c);
      if (Number.isNaN(num)) return null;
      if (isFloat) {
        return Math.round(Math.min(1, Math.max(0, num)) * 255).toString(16).padStart(2, "0");
      }
      return Math.round(Math.min(255, Math.max(0, num))).toString(16).padStart(2, "0");
    });
    if (hex.every(Boolean)) out.push(hex.join("").toUpperCase());
  }
  return out;
}

// The purple, indigo, violet and hot-pink band that default AI palettes live in.
function isSlopHue(hex) {
  const { h, s, l } = hexToHsl(hex);
  return s >= 0.4 && l >= 0.2 && l <= 0.85 && h >= 235 && h <= 340;
}

function isSaturated(hex) {
  const { s, l } = hexToHsl(hex);
  return s >= 0.35 && l >= 0.15 && l <= 0.9;
}

// Also the CSS named colors in that band (rebeccapurple, hotpink, ...), which a
// plain \bpurple\b or \bpink\b does not reach, UIKit system colors (.systemPurple, ...)
// and Flutter accent swatches (Colors.purpleAccent, ...).
const SLOP_COLOR_NAME = /(?:\.|Colors\.|Color\.|\b)(?:system)?(purple|deepPurple|indigo|violet|pink|magenta|fuchsia|rebeccapurple|mediumpurple|blueviolet|darkviolet|darkorchid|mediumorchid|hotpink|deeppink|mediumvioletred)(?:Accent)?\b/i;

// Replace comments with spaces, keeping offsets and newlines, so rules never
// match commented-out code. Strings are kept.
function blankComments(text, stack) {
  const out = text.split("");
  const blank = (from, to) => {
    for (let i = from; i < to; i++) if (out[i] !== "\n") out[i] = " ";
  };
  if (stack === "xml" || stack === "web") {
    const re = /<!--[\s\S]*?-->/g;
    let m;
    while ((m = re.exec(text))) blank(m.index, m.index + m[0].length);
    if (stack === "xml") return out.join("");
  }
  let i = 0;
  let quote = null;
  while (i < text.length) {
    const c = text[i];
    const next = text[i + 1];
    if (quote) {
      if (c === "\\") { i += 2; continue; }
      if (c === quote || (c === "\n" && quote !== "`")) quote = null;
      i++;
      continue;
    }
    if (c === "/" && next === "/") {
      // Skip URLs such as https:// outside quotes.
      if (text[i - 1] === ":") { i++; continue; }
      const end = text.indexOf("\n", i);
      const stop = end === -1 ? text.length : end;
      blank(i, stop);
      i = stop;
      continue;
    }
    if (c === "/" && next === "*") {
      const end = text.indexOf("*/", i + 2);
      const stop = end === -1 ? text.length : end + 2;
      blank(i, stop);
      i = stop;
      continue;
    }
    if (c === "/" && stack === "js" && isRegexStart(text, i)) {
      i = skipRegex(text, i);
      continue;
    }
    if (stack === "swift" && c === '"') {
      // Swift raw strings use #"..."# (or more hashes). Quotes and // inside
      // them are literal text, not delimiters or comments.
      let hashes = 0;
      while (text[i - 1 - hashes] === "#") hashes++;
      if (hashes > 0) {
        const closing = '"' + "#".repeat(hashes);
        const end = text.indexOf(closing, i + 1);
        i = end === -1 ? text.length : end + closing.length;
        continue;
      }
    }
    if (c === '"' || c === "`" || (c === "'" && stack !== "swift")) {
      // An apostrophe between letters is prose (JSX text such as Don't), not a string.
      if (c === "'" && /[A-Za-z]/.test(text[i - 1] || "") && /[A-Za-z]/.test(next || "")) { i++; continue; }
      quote = c;
    }
    i++;
  }
  return out.join("");
}

// Collect string literal contents with their starting offsets. This is used by
// rules that care about a whole literal rather than text inside it. It keeps
// JSX prose apostrophes, Swift interpolation and Swift raw strings from being
// mistaken for ordinary quote delimiters.
function stringLiterals(code, stack) {
  const literals = [];
  const proseApostrophe = (i) =>
    code[i] === "'" && /[A-Za-z]/.test(code[i - 1] || "") && /[A-Za-z]/.test(code[i + 1] || "");
  const quoteStart = (i) =>
    !proseApostrophe(i) && (code[i] === '"' || code[i] === "'" || code[i] === "`");

  const rawHashes = (i) => {
    if (stack !== "swift" || code[i] !== '"') return 0;
    let count = 0;
    while (code[i - 1 - count] === "#") count++;
    return count;
  };

  // `i` points at the backslash in a Swift \(...) interpolation. Nested
  // literals are collected here so the outer literal can resume after the
  // matching parenthesis instead of closing at the nested quote.
  const scanInterpolation = (i) => {
    let depth = 0;
    let j = i + 2;
    while (j < code.length) {
      if (code[j] === "\\" && code[j + 1] === "(") {
        j = scanInterpolation(j);
        continue;
      }
      if (quoteStart(j)) {
        j = readLiteral(j);
        continue;
      }
      if (code[j] === "(") depth++;
      else if (code[j] === ")") {
        if (depth === 0) return j + 1;
        depth--;
      }
      j++;
    }
    return j;
  };

  function readLiteral(start) {
    const quote = code[start];
    const hashes = rawHashes(start);
    const from = start + 1;
    let j = from;
    while (j < code.length) {
      const c = code[j];
      if (hashes > 0) {
        // In a raw string, quotes are literal and backslashes do not escape.
        // Only the closing quote followed by the same number of # ends it.
        if (c === '"' && code.slice(j + 1, j + 1 + hashes) === "#".repeat(hashes)) {
          literals.push({ start, contents: code.slice(from, j) });
          return j + 1 + hashes;
        }
        j++;
        continue;
      }
      if (c === "\\") {
        if (quote === '"' && code[j + 1] === "(") {
          j = scanInterpolation(j);
        } else {
          j += 2;
        }
        continue;
      }
      if (c === quote) {
        literals.push({ start, contents: code.slice(from, j) });
        return j + 1;
      }
      j++;
    }
    literals.push({ start, contents: code.slice(from, j) });
    return j;
  }

  for (let i = 0; i < code.length; ) {
    if (quoteStart(i)) {
      i = readLiteral(i);
    } else {
      i++;
    }
  }
  return literals;
}

// A slash starts a regex literal when it follows an operator, an opening
// bracket, a keyword such as return, or the start of the text.
function isRegexStart(text, i) {
  let j = i - 1;
  while (j >= 0 && (text[j] === " " || text[j] === "\t")) j--;
  if (j < 0 || text[j] === "\n") return true;
  // Not after <, > or }: those are JSX closing tags and text such as {a}/{b}.
  if ("(,=:[!&|?{;+-*%~^".includes(text[j])) return true;
  return /\b(?:return|typeof|case|do|else|in|of|void|yield|await)$/.test(text.slice(Math.max(0, j - 6), j + 1));
}

// Index just past a regex literal starting at i (flags included). Stops at
// the end of the line if the literal is not closed.
function skipRegex(text, i) {
  let inClass = false;
  for (let k = i + 1; k < text.length; k++) {
    const c = text[k];
    if (c === "\n") return k;
    if (c === "\\") { k++; continue; }
    if (c === "[") inClass = true;
    else if (c === "]") inClass = false;
    else if (c === "/" && !inClass) {
      k++;
      while (k < text.length && /[a-z]/i.test(text[k])) k++;
      return k;
    }
  }
  return text.length;
}

function lineStarts(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") starts.push(i + 1);
  return starts;
}

function lineAt(starts, index) {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= index) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}

// Index of the ">" that closes the tag, skipping any "{...}" attribute expression so an arrow
// function (=>) or a comparison inside it does not end the tag early. -1 when nothing closes it.
function tagEnd(text, from) {
  const end = walkTag(text, from);
  return end === -1 ? text.indexOf(">", from) : end;
}

// Walks an opening tag from `from` and returns the index of its closing ">", or -1. A > inside a
// quoted attribute value (title="a > b") does not end the tag, and a brace inside a string or a
// regex literal in an expression (onLoad={() => f("}")}) does not close it. `own(i)` is called
// for each character outside {...} expressions: the element's own attributes.
function walkTag(text, from, own) {
  let depth = 0;
  let quote = null;
  for (let i = from; i < text.length; i++) {
    const c = text[i];
    if (own && depth === 0) own(i);
    if (quote) {
      if (c === "\\" && depth > 0) i++;
      else if (c === quote) quote = null;
    } else if (c === '"' || c === "'" || (depth > 0 && c === "`")) quote = c;
    else if (c === "/" && depth > 0 && regexInExpression(text, i)) i = skipRegex(text, i) - 1;
    else if (c === "{") depth++;
    else if (c === "}" && depth > 0) depth--;
    else if (c === ">" && depth === 0) return i;
  }
  return -1;
}

// isRegexStart, plus the slash right after an arrow (() => /x/.test(v)).
function regexInExpression(text, i) {
  let j = i - 1;
  while (j >= 0 && (text[j] === " " || text[j] === "\t")) j--;
  return (text[j] === ">" && text[j - 1] === "=") || isRegexStart(text, i);
}

function* matches(re, text) {
  const g = new RegExp(re.source, re.flags.includes("g") ? re.flags : re.flags + "g");
  let m;
  while ((m = g.exec(text))) {
    yield m;
    if (m[0] === "") g.lastIndex++;
  }
}

// True when the `brush =` at `index` sits inside a TextStyle(...) or
// SpanStyle(...) call: walk backwards matching parens until the innermost
// still-open `(` is found and check the callee name in front of it.
function isTextBrush(code, index) {
  let depth = 0;
  for (let i = index - 1; i >= 0; i--) {
    const c = code[i];
    if (c === ")") depth++;
    else if (c === "(") {
      if (depth > 0) depth--;
      else {
        const name = /(?:(?:^|[^\w.])(?:TextStyle|SpanStyle)|\.copy)\s*$/.exec(code.slice(0, i));
        return Boolean(name);
      }
    }
  }
  return false;
}

// True when the match at `index` sits inside a log call (console.*,
// logger.*, Log.*, print, debugPrint, NSLog) or a `throw new ...(...)`
// that is still open on the same line. Log calls and thrown errors never
// reach the user, so their messages stay quiet — but a call that already
// closed on the line does not hide visible copy after it:
// `console.error(err); return <p>Oops!</p>;` still flags. Parens inside
// string literals do not close the call, so a message such as
// `console.error("a)b", "Oops")` stays quiet.
function insideLogCall(code, index) {
  const lineStart = code.lastIndexOf("\n", index) + 1;
  const before = code.slice(lineStart, index);
  const calls = /\b(?:console|logger|log|Log)\.\w+\s*\(|\b(?:print|debugPrint|NSLog)\s*\(|throw\s+new\s+\w+\s*\(/g;
  let m;
  while ((m = calls.exec(before))) {
    const open = m.index + m[0].lastIndexOf("(");
    if (callStillOpen(before, open)) return true;
  }
  return false;
}

// True when the `(` at `open` has no matching `)` before the end of `text`:
// scan forward tracking paren depth, skipping string literals so a paren
// inside a message neither closes nor opens the call.
function callStillOpen(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (c === "\"" || c === "'" || c === "`") {
      const quote = c;
      i++;
      while (i < text.length && text[i] !== quote) {
        if (text[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) return false;
    }
  }
  return depth > 0;
}

// Index just past the bracket that closes the one at `open`.
function closeOf(text, open) {
  const pairs = { "(": ")", "{": "}", "[": "]" };
  const opener = text[open];
  const closer = pairs[opener];
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === opener) depth++;
    else if (text[i] === closer) {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return text.length;
}

// Like closeOf() for "(", but a parenthesis inside a quoted string does not count, so
// cn("before:content-['(']", ...) still ends at its own closing parenthesis.
function callEnd(text, open) {
  let depth = 0;
  let quote = null;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = null;
    } else if (c === '"' || c === "'" || c === "`") quote = c;
    else if (c === "(") depth++;
    else if (c === ")" && --depth === 0) return i + 1;
  }
  return text.length;
}

// The part of `rest` (the text after a gradient's constructor) during which
// `variable` still holds that gradient: up to the end of the enclosing block,
// or up to the variable's next assignment. A declaration of the same name in a
// nested block (a helper's own `const g`) shadows it and does not end it.
function bindingRegion(rest, variable) {
  let depth = 0;
  let blockEnd = rest.length;
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === "{") depth++;
    else if (rest[i] === "}" && --depth < 0) { blockEnd = i; break; }
  }
  const region = rest.slice(0, blockEnd);
  const write = new RegExp(`(?<![\\w$.])(?:(?:const|let|var|val)\\s+)?${variable}\\s*=(?!=)`);
  for (const m of matches(write, region)) {
    const declaredInNestedBlock =
      /^(?:const|let|var|val)\s/.test(m[0]) && blockDepth(region, m.index) > 0;
    if (!declaredInNestedBlock) return region.slice(0, m.index);
  }
  return region;
}

function blockDepth(text, index) {
  let depth = 0;
  for (let i = 0; i < index; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}") depth--;
  }
  return depth;
}

const COLOR_SIGN =/#[0-9a-fA-F]{3,8}\b|0x[0-9a-fA-F]{6,8}\b|\b(?:rgba?|hsla?|oklch|oklab)\(|\bColors?\.\w|\.(?:purple|indigo|pink|blue|red|green|orange|yellow|white|black|gray|grey)\b/;

// The text that holds the colors of the gradient named at `start`, so a color
// after it (the next CSS rule, a child element's style, the next statement)
// is never read as one of its stops (issue #67). Empty when the name is not a
// gradient definition, e.g. a type like GradientDrawable.Orientation.
function gradientScope(text, start, name) {
  // An element: <LinearGradient colors={...}>, <gradient android:startColor=.../>,
  // or an SVG <linearGradient> whose colors sit on its <stop> children. Other
  // children (an expo-linear-gradient's <Text>) are content, not stops.
  if (name.startsWith("<") || text[start - 1] === "<") {
    const end = tagEnd(text, start);
    if (end === -1) return text.slice(start, text.indexOf("\n", start) >>> 0);
    let scope = text.slice(start, end + 1);
    if (text[end - 1] !== "/") {
      const close = text.indexOf(`</${name.replace(/^</, "")}`, end);
      const body = text.slice(end + 1, close === -1 ? text.length : close);
      // tagEnd() skips "{...}", so a ">" in a JSX expression (offset={i > 0 ...})
      // does not cut the tag before its stopColor.
      for (const stop of matches(/<stop\b/i, body)) {
        const stopEnd = tagEnd(body, stop.index);
        scope += body.slice(stop.index, stopEnd === -1 ? body.length : stopEnd + 1);
      }
    }
    return scope;
  }
  // A call: linear-gradient(...), LinearGradient(colors: ...), Brush.linearGradient(...).
  const paren = start + name.length + (text.slice(start + name.length).match(/^\s*/)?.[0].length ?? 0);
  if (text[paren] !== "(") return "";
  const end = closeOf(text, paren);
  let scope = text.slice(start, end);
  if (COLOR_SIGN.test(scope.slice(name.length))) return scope;
  // A constructor that takes no colors (canvas createLinearGradient, Android
  // GradientDrawable()): they come in a Kotlin .apply { } block right after,
  // or in calls on the variable it is assigned to, for as long as that
  // variable holds it (until it is assigned again).
  const apply = /^\s*\.apply\s*\{/.exec(text.slice(end));
  if (apply) scope += text.slice(end, closeOf(text, end + apply[0].length - 1));
  // The assignment may sit on the line above: "const g =\n  ctx.create...".
  const assigned = /([A-Za-z_$][\w$]*)\s*=\s*(?:new\s+)?[\w$.]*$/.exec(text.slice(Math.max(0, start - 200), start));
  if (assigned) {
    // Identifier characters only, so "$" is the one character to escape. The
    // lookbehind is the identifier boundary: \b fails before "$g", and a
    // preceding "." would make it another object's member (other.g).
    const variable = assigned[1].replace(/\$/g, "\\$");
    const region = bindingRegion(text.slice(end), variable);
    for (const call of matches(new RegExp(`(?<![\\w$.])${variable}\\.(?:addColorStop|setColors)\\s*\\(|(?<![\\w$.])${variable}\\.colors\\s*=(?!=)`), region)) {
      const after = call.index + call[0].length;
      let tail;
      if (call[0].endsWith("(")) {
        tail = closeOf(region, after - 1);
      } else {
        // `.colors = intArrayOf(...)` may span lines: read the value through
        // its closing bracket, or to the end of the line for a plain value.
        const at = after + /^\s*(?:new\s+)?[\w$.]*\s*/.exec(region.slice(after))[0].length;
        tail = "([{".includes(region[at]) ? closeOf(region, at) : region.indexOf("\n", call.index) >>> 0;
      }
      scope += region.slice(call.index, tail);
    }
  }
  return scope;
}

// ---------- rules ----------
// Each rule gets ctx { code, stack, file } and returns indexes into code.

// A Swift file that imports AppKit or Cocoa outside any #if, and never imports
// UIKit, builds for macOS only: AppKit does not exist on iOS. macOS does not
// support Dynamic Type for third-party apps, so a fixed size there is not a
// tell. An import inside #if os(macOS) says nothing, since the rest of the
// file may build for iOS.
function macOnlySwift(code) {
  const imports = /^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|package|internal|fileprivate|private)[ \t]+)?import[ \t]+(?:(?:class|struct|enum|protocol|typealias|func|var|let)[ \t]+)?(\w+)/;
  let depth = 0;
  let appKit = false;
  for (const line of code.split("\n")) {
    if (/^[ \t]*#if\b/.test(line)) depth++;
    else if (/^[ \t]*#endif\b/.test(line)) depth = Math.max(0, depth - 1);
    const m = imports.exec(line);
    if (!m) continue;
    if (m[1] === "UIKit") return false;
    if (depth === 0 && (m[1] === "AppKit" || m[1] === "Cocoa")) appKit = true;
  }
  return appKit;
}

function matchOpenBackward(code, closeIdx, openCh, closeCh) {
  let depth = 0;
  for (let i = closeIdx; i >= 0; i--) {
    const c = code[i];
    if (c === '"') {
      i--;
      while (i >= 0) {
        if (code[i] === '"') {
          let slashes = 0;
          while (i - 1 - slashes >= 0 && code[i - 1 - slashes] === "\\") slashes++;
          if (slashes % 2 === 0) break;
        }
        i--;
      }
      continue;
    }
    if (c === closeCh) depth++;
    else if (c === openCh && --depth === 0) return i;
  }
  return -1;
}

// True when the `.ignoresSafeArea` / `.edgesIgnoringSafeArea` at `index` sits
// on a background/decorative view (even across a multi-line call or modifier
// chain) or directly inside a `.background(...)` / `.background { ... }`.
function isBackgroundSafeArea(code, index) {
  const BG_CONSTRUCTOR = /^(?:Color|\w*Image|Rectangle|Divider|\w*Gradient)$/;
  // 1) Directly inside a still-open `.background(` or `.background {`.
  const limit = Math.max(0, index - 4000);
  let pDepth = 0;
  let bDepth = 0;
  for (let i = index - 1; i >= limit; i--) {
    const c = code[i];
    if (c === '"') {
      i--;
      while (i >= limit) {
        if (code[i] === '"') {
          let slashes = 0;
          while (i - 1 - slashes >= 0 && code[i - 1 - slashes] === "\\") slashes++;
          if (slashes % 2 === 0) break;
        }
        i--;
      }
      continue;
    }
    if (c === ")") pDepth++;
    else if (c === "(") {
      if (pDepth > 0) pDepth--;
      else {
        if (/\.background\s*$/.test(code.slice(Math.max(0, i - 32), i))) return true;
        break;
      }
    } else if (c === "}") bDepth++;
    else if (c === "{") {
      if (bDepth > 0) bDepth--;
      else {
        let head = i - 1;
        while (head >= 0 && /\s/.test(code[head])) head--;
        if (head >= 0 && code[head] === ")") {
          const open = matchOpenBackward(code, head, "(", ")");
          if (open !== -1) head = open - 1;
        }
        if (/\.background\s*$/.test(code.slice(Math.max(0, head - 31), head + 1))) return true;
        break;
      }
    }
  }
  // 2) Walk backwards through the receiver's modifier chain to its root view.
  let i = index - 1;
  while (i >= 0) {
    while (i >= 0 && /[\s?!]/.test(code[i])) i--;
    if (i < 0) return false;
    if (code[i] === ")") {
      const open = matchOpenBackward(code, i, "(", ")");
      if (open === -1) return false;
      let end = open - 1;
      while (end >= 0 && /\s/.test(code[end])) end--;
      let start = end;
      while (start >= 0 && /\w/.test(code[start])) start--;
      const name = code.slice(start + 1, end + 1);
      if (BG_CONSTRUCTOR.test(name)) return true;
      let dot = start;
      while (dot >= 0 && /\s/.test(code[dot])) dot--;
      if (dot >= 0 && code[dot] === ".") {
        i = dot - 1;
        continue;
      }
      return /background|Gradient/.test(name);
    }
    if (code[i] === "}") {
      const open = matchOpenBackward(code, i, "{", "}");
      if (open === -1) return false;
      let head = open - 1;
      while (head >= 0 && /\s/.test(code[head])) head--;
      if (head >= 0 && code[head] === ")") {
        const pOpen = matchOpenBackward(code, head, "(", ")");
        if (pOpen === -1) return false;
        head = pOpen - 1;
        while (head >= 0 && /\s/.test(code[head])) head--;
      }
      let start = head;
      while (start >= 0 && /\w/.test(code[start])) start--;
      let dot = start;
      while (dot >= 0 && /\s/.test(code[dot])) dot--;
      if (dot >= 0 && code[dot] === ".") {
        i = dot - 1;
        continue;
      }
      return false;
    }
    if (/\w/.test(code[i])) {
      let cur = i;
      while (cur >= 0 && /\w/.test(code[cur])) {
        let start = cur;
        while (start >= 0 && /\w/.test(code[start])) start--;
        const name = code.slice(start + 1, cur + 1);
        if (BG_CONSTRUCTOR.test(name) || /background|Gradient/.test(name)) return true;
        let dot = start;
        while (dot >= 0 && /\s/.test(code[dot])) dot--;
        if (dot < 0 || code[dot] !== ".") break;
        cur = dot - 1;
        while (cur >= 0 && /[\s?!]/.test(code[cur])) cur--;
      }
      return false;
    }
    return false;
  }
  return false;
}

function glowLayers(list) {
  const layers = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i <= list.length; i++) {
    const c = list[i];
    if (c === "(") depth++;
    else if (c === ")") depth--;
    else if ((c === "," && depth === 0) || i === list.length) {
      layers.push(list.slice(start, i));
      start = i + 1;
    }
  }
  return layers.filter((layer) => {
    if (!/\binset\b/.test(layer)) return true;
    const lengths = layer.replace(/[a-z]+\([^)]*\)|#[0-9a-f]+/gi, " ").match(/-?\d*\.?\d+(?:px|rem|em)?\b/g) || [];
    return lengths.length >= 3 && parseFloat(lengths[2]) > 0;
  });
}

function isGlowValue(value, stack) {
  if (!value) return false;
  if (/black|gray|grey|shadow|\.primary\b|label|0x[0-9a-f]{2}000000|#000(?:000)?(?:[0-9a-f]{2})?\b|#000[0-9a-f]\b|rgba?\([\s_]*0(?:[\s_]*,[\s_]*|[\s_]+)0(?:[\s_]*,[\s_]*|[\s_]+)0/i.test(value)) return false;
  const named = /(?:\.|Colors\.|Color\.|\b)(purple|deepPurple|indigo|violet|pink|magenta|fuchsia|blue|cyan|teal|mint|sky|accentColor|accent)\b/i.test(value);
  const hex = hexColors(value, stack).some(isSaturated);
  const rgbRe = /rgba?\([\s_]*(\d+)(?:[\s_]*,[\s_]*|[\s_]+)(\d+)(?:[\s_]*,[\s_]*|[\s_]+)(\d+)/g;
  let rgbSat = false;
  let rgb;
  while ((rgb = rgbRe.exec(value))) {
    if (Math.max(+rgb[1], +rgb[2], +rgb[3]) - Math.min(+rgb[1], +rgb[2], +rgb[3]) > 60) { rgbSat = true; break; }
  }
  return named || hex || rgbSat;
}

const rules = [
  {
    id: "slop-gradient",
    family: "looks-generated",
    severity: "noticeable",
    stacks: null,
    message: "Purple, indigo, or pink gradient: the default AI palette.",
    fix: "Use a flat surface from the theme. Keep a gradient only if it comes from the brand (logo, icon) and record that in .unslop-anything/decisions.md.",
    find({ code, stack, file }) {
      if (/icon|logo|brand/i.test(path.basename(file))) return [];
      const hits = [];
      for (const m of matches(/(?<!<\/)(?:LinearGradient|linearGradient|RadialGradient|radialGradient|AngularGradient|Brush\.(?:linear|radial|horizontal|vertical|sweep)Gradient|linear-gradient|radial-gradient|GradientDrawable|<gradient\b)/, code)) {
        const lineStart = code.lastIndexOf("\n", m.index) + 1;
        if (/^\s*(?:import|export\s+\{|from)\b/.test(code.slice(lineStart, m.index))) continue;
        // Only the gradient's own stops count, not whatever follows it.
        const stops = gradientScope(code, m.index, m[0]);
        if ([...hexColors(stops, stack), ...cssFunctionColors(stops), ...flutterColors(stops), ...swiftRgbColors(stops), ...composeColors(stops)].some(isSlopHue) || SLOP_COLOR_NAME.test(stops)) hits.push(m.index);
      }
      // Tailwind: bg-gradient-to-r from-violet-600 to-fuchsia-500
      for (const m of matches(/["'`][^"'`\n]*\bbg-(?:gradient|linear|radial|conic)-[^"'`\n]*["'`]/, code)) {
        // The stops may sit in another string of the same cn(...) / clsx(...) call.
        let scope = m[0];
        const from = Math.max(0, m.index - 400);
        for (const c of matches(/\b(?:cn|cx|clsx|classnames|classNames|twMerge|twJoin)\s*\(/, code.slice(from, m.index))) {
          const open = from + c.index + c[0].length - 1;
          const close = callEnd(code, open);
          // The outermost call that holds the string: a nested clsx(...) keeps the outer stops.
          if (close > m.index) {
            scope = code.slice(open, close);
            break;
          }
        }
        // Arbitrary stops carry the color itself: from-[#7c3aed], from-[rgb(...)], from-[hsl(...)].
        const arbitrary = [...scope.matchAll(/\b(?:from|via|to)-\[([^\]]+)\]/g)].map((s) => s[1].replace(/_/g, " ")).join(" ");
        if (/\b(?:from|via|to)-(?:purple|violet|indigo|fuchsia|pink)-\d{2,3}\b/.test(scope) || [...hexColors(arbitrary, stack), ...cssFunctionColors(arbitrary)].some(isSlopHue)) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "gradient-text",
    family: "looks-generated",
    severity: "noticeable",
    stacks: null,
    message: "Gradient-filled text.",
    fix: "Emphasize with weight or size from the type scale, in a solid theme color.",
    find({ code }) {
      const hits = [];
      const re = /<MaskedView|\bShaderMask\s*\(|\.foregroundStyle\(\s*(?:LinearGradient|\.linearGradient)|\.foregroundStyle\([^)]*Gradient|background-clip:\s*text|-webkit-background-clip:\s*text|\bbg-clip-text\b|\bforeground\s*:\s*\(?\s*Paint\(\s*\)(?:\s*\.\.(?!shader\b)\w+\s*=(?:[ \t]*\r?\n\s*(?=\S))?(?:[^;\n(),.\s]|[ \t]+(?!\s|\.\.)|\.(?!\.))*?(?:\((?:[^()]|\([^()]*\))*\)(?:[^;\n(),.\s]|[ \t]+(?!\s|\.\.)|\.(?!\.))*?)*?)*?\s*\.\.shader\s*=\s*\(?\s*(?:const\s+)?(?:\w+\.)?(?:(?:Linear|Radial|Sweep)Gradient\b|Gradient\.(?:linear|radial|sweep)\b)/;
      for (const m of matches(re, code)) hits.push(m.index);
      // Compose: only a brush passed to TextStyle/SpanStyle is gradient text.
      // Modifier.background(brush = ...) and Modifier.border(..., brush = ...)
      // are plain gradient surfaces, not text, so they stay with slop-gradient.
      for (const m of matches(/brush\s*=\s*Brush\.\w+Gradient/, code)) {
        if (isTextBrush(code, m.index)) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "template-theme",
    family: "looks-generated",
    severity: "noticeable",
    stacks: null,
    message: "The project template's default color is still the theme.",
    fix: "Pick the brand's own accent and define semantic roles (background, surface, text, accent, destructive). Ask first if that purple has become the brand.",
    find({ code, stack }) {
      const re = stack === "xml"
        ? /#(?:[fF]{2})?(?:6200[eE][eE]|3700[bB]3|[bB][bB]86[fF][cC])\b/
        : /seedColor:\s*Colors\.deepPurple|0x[fF]{2}(?:6650[aA]4|[dD]0[bB][cC][fF][fF]|6200[eE][eE]|3700[bB]3|[bB][bB]86[fF][cC])\b|#(?:6200[eE][eE]|3700[bB]3|[bB][bB]86[fF][cC]|0[aA]7[eE][aA]4|646[cC][fF]{2}|535[bB][fF]2)\b|<HelloWave\b|<ParallaxScrollView\b/;
      // #646cff / #535bf2 are create-vite's starter link and hover colors.
      // One finding per file, like drawer-nav: the default tint and the
      // starter-screen components are the same leftover.
      const first = matches(re, code).next();
      return first.done ? [] : [first.value.index];
    },
  },
  {
    id: "glow-shadow",
    family: "looks-generated",
    severity: "minor",
    stacks: null,
    message: "Colored glow shadow.",
    fix: "Shadows carry depth, not color: use the platform elevation or a soft neutral shadow, or remove it.",
    find({ code, stack }) {
      const hits = [];
      // text-shadow is layered like box-shadow (#200); textShadowColor is React
      // Native's text glow (#201); a filter drop-shadow() is one shadow (#199).
      for (const m of matches(/\.shadow\(\s*color:\s*([^,)]+)|(?:shadowColor|textShadowColor)\s*[:=]\s*["']?([^"',;\n}]+)|(?:ambientColor|spotColor)\s*=\s*([^,)\n]+)|\b(?:BoxShadow|Shadow)\(\s*color:\s*([^,)\n]+)|(?:box|text)-shadow:\s*([^;\n]+)|\bshadow-((?:purple|violet|indigo|pink|fuchsia|blue|cyan|teal|sky)-\d{2,3})\b|\bshadow-\[([^\]\n]+)\]|\bdrop-shadow\(((?:[^()\n]|\([^()\n]*\))*)\)|\b(?:box|text)Shadow\s*:\s*(?:"([^"\n]*)"|'([^'\n]*)'|`([^`]*)`)/, code)) {
        const raw = m.slice(1).find(Boolean) || "";
        const layers = m[5] || m[7] || m[9] || m[10] || m[11] ? glowLayers(raw.replace(/_/g, " ")) : raw ? [raw] : [];
        if (layers.some((value) => isGlowValue(value, stack))) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "status-dot",
    family: "looks-generated",
    severity: "minor",
    stacks: null,
    message: "Small colored dot. Decorative dots next to labels are a common generated tell.",
    fix: "Keep it only if it shows a real status the user acts on, with a text label or shape, never color alone. Otherwise delete it.",
    find({ code, stack }) {
      const hits = [];
      const small = (n) => n >= 3 && n <= 12;
      if (stack === "js" || stack === "web") {
        for (const m of matches(/\bwidth:\s*(\d{1,2})\b/, code)) {
          const n = +m[1];
          if (!small(n)) continue;
          const around = code.slice(Math.max(0, m.index - 120), m.index + 160);
          const radius = /borderRadius:\s*(\d+)/.exec(around);
          if (new RegExp(`height:\\s*${n}\\b`).test(around) && radius && +radius[1] >= n / 2) hits.push(m.index);
        }
        for (const m of matches(/["'`][^"'`\n]*\b(?:[wh]|size)-(?:1|1\.5|2|2\.5|3)\b[^"'`\n]*["'`]/, code)) {
          const dim = "(?:1|1\\.5|2|2\\.5|3)\\b";
          const both = new RegExp(`\\bw-${dim}`).test(m[0]) && new RegExp(`\\bh-${dim}`).test(m[0]);
          if (/\brounded-full\b/.test(m[0]) && (both || new RegExp(`\\bsize-${dim}`).test(m[0]))) hits.push(m.index);
        }
      }
      if (stack === "swift") {
        for (const m of matches(/\bCircle\(\)/, code)) {
          const f = /^[\s\S]{0,200}?\.frame\(\s*width:\s*(\d+(?:\.\d+)?)\s*,\s*height:\s*(\d+(?:\.\d+)?)/.exec(code.slice(m.index, m.index + 260));
          if (f && small(+f[1]) && +f[1] === +f[2]) hits.push(m.index);
        }
      }
      if (stack === "kotlin") {
        for (const m of matches(/\.size\(\s*(\d+)\.dp\s*\)/, code)) {
          const around = code.slice(Math.max(0, m.index - 160), m.index + 160);
          if (small(+m[1]) && /CircleShape/.test(around)) hits.push(m.index);
        }
      }
      if (stack === "dart") {
        for (const m of matches(/BoxShape\.circle/, code)) {
          const around = code.slice(Math.max(0, m.index - 220), m.index + 120);
          const w = /width:\s*(\d+(?:\.\d+)?)/.exec(around);
          if (w && small(+w[1])) hits.push(m.index);
        }
      }
      return hits;
    },
  },
  {
    id: "nested-cards",
    family: "looks-generated",
    severity: "noticeable",
    stacks: ["js", "kotlin", "dart", "web"],
    message: "A card inside a card.",
    fix: "Keep one container level. Group inner content with spacing, a divider, or a list section instead.",
    find({ code, stack }) {
      const hits = [];
      if (stack === "js" || stack === "web") {
        // Vuetify's v-card, Angular Material's mat-card, Quasar's q-card and Element Plus's el-card nest like ion-card (#202, #228).
        // Naive UI's n-card and Ant Design Vue's a-card nest like ion-card too (#266).
        // So does PrimeNG's p-card (#280).
        for (const m of matches(/<(Card|IonCard|ion-card|VCard|v-card|mat-card|QCard|q-card|ElCard|el-card|NCard|n-card|ACard|a-card|p-card)(?=[\s/>])/, code)) {
          const end = tagEnd(code, m.index + m[0].length);
          if (end === -1) continue;
          if (/\/\s*$/.test(code.slice(m.index + m[0].length, end))) continue;
          const tag = m[1];
          const close = code.indexOf(`</${tag}>`, end + 1);
          if (close === -1) continue;
          const inner = code.slice(end + 1, close);
          if (new RegExp(`<${tag}(?=[\\s/>])`).test(inner)) hits.push(m.index);
        }
      } else {
        const card = /\b(?:Elevated|Outlined|Filled)?Card\s*[({]/;
        for (const m of matches(card, code)) {
          const open = m.index + m[0].length - 1;
          let end = closeOf(code, open);
          const lambda = /^\s*\{/.exec(code.slice(end));
          if (code[open] === "(" && lambda) end = closeOf(code, end + lambda[0].length - 1);
          if (card.test(code.slice(open + 1, end - 1))) hits.push(m.index);
        }
      }
      return hits;
    },
  },
  {
    id: "glass-everywhere",
    family: "looks-generated",
    severity: "minor",
    stacks: null,
    message: "Blur and glass used on several surfaces in one file.",
    fix: "Keep system materials behind bars and sheets. Make content surfaces opaque.",
    find({ code }) {
      // Tailwind: backdrop-blur, backdrop-blur-<size> and backdrop-blur-[...]
      // count as blur surfaces. backdrop-blur-none removes the blur, so it
      // does not count. backdropFilter in a JS style object counts the same
      // way, except backdropFilter: "none".
      const all = [...matches(/\.(?:ultraThin|thin|regular|thick|ultraThick)Material\b|<BlurView\b|backdrop-filter|BackdropFilter\(|ImageFilter\.blur|\.glassEffect\(|\bbackdrop-blur(?!-none\b)|\bbackdropFilter\b(?!\s*:\s*["'`]none["'`])/, code)];
      return all.length >= 3 ? [all[0].index] : [];
    },
  },
  {
    id: "sparkle-icon",
    family: "looks-generated",
    severity: "minor",
    stacks: null,
    message: "Sparkle icon. It usually marks an AI feature or stands in for meaning.",
    fix: "Use an icon that names the action, or a text label. If it marks an AI feature, make sure that feature is not in the way of the core task.",
    find({ code, stack }) {
      // SF Symbols are often derived from "sparkle"/"sparkles" or
      // "wand.and.stars"/"wand.and.sparkles", for example
      // "sparkles.rectangle.stack" and "wand.and.stars.inverse". Iconify
      // names take the form "<set>:sparkles?" or the Nuxt "i-<set>-sparkles?".
      // Check the complete string literal so a quoted symbol is only flagged
      // when the literal is exactly that symbol; substrings and apostrophes
      // inside longer text stay quiet.
      const symbol = /^(?:sparkles?(?:\.[a-z0-9._-]+)?|wand\.and\.(?:stars|sparkles)(?:\.[a-z0-9._-]+)?|[a-z0-9-]+:sparkles?|i-[a-z0-9-]+-sparkles?|wand-magic-sparkles)$/;
      const re = /\bauto_awesome\b|\bAutoAwesome(?:Outlined|Rounded|Sharp|TwoTone)?(?:Icon)?\b|\bSparkles\b|\bSparklesIcon\b|\bSparkle\b|\bSparkleIcon\b|\bIconSparkles\b|\bWandSparkles\b|\bWandSparklesIcon\b|✨|\b(?:Hi(?:Outline|Mini)?|Lu|Tb|Pi|Bs|Io|Ri)Sparkles?(?:Fill|Line|Outline|Sharp|Bold|Duotone|Light|Thin)?\b|\bRiSparkling(?:2)?(?:Fill|Line)?\b|\bMd(?:Outline|Round|Sharp|TwoTone)?AutoAwesome\b|\bfa(?:WandMagic)?Sparkles\b|(?<![\w-])fa-(?:wand-magic-)?sparkles(?![\w-])|(?<![\w-])ri-sparkling(?:-2)?-(?:line|fill)(?![\w-])|\bBsStars\b|(?<![\w-])bi-stars(?![\w-])/;
      const hits = [...matches(re, code)].map((m) => m.index);

      for (const literal of stringLiterals(code, stack)) {
        if (symbol.test(literal.contents)) hits.push(literal.start);
      }

      return hits.sort((a, b) => a - b);
    },
  },
  {
    id: "emoji-icon",
    family: "looks-generated",
    severity: "minor",
    stacks: ["swift", "kotlin", "dart", "js", "web", "xml"],
    message: "Emoji in interface text, often standing in for an icon.",
    fix: "Use the platform icon set (SF Symbols, Material Symbols) with an accessibility label, or drop it.",
    find({ code }) {
      // Only emoji sitting beside a word, as in "🚀 Fast" or "Video 📺". Emoji
      // pickers, reactions and user content are left alone.
      const re = /(?<!\p{L})(\p{Emoji_Presentation}|\p{Extended_Pictographic}️)[  ]?\p{L}{2,}|\p{L}{2,}[  ]?(\p{Emoji_Presentation}|\p{Extended_Pictographic}️)/u;
      const hits = [];
      for (const m of matches(re, code)) {
        if ((m[1] || m[2]) === "✨") continue; // reported by sparkle-icon
        const lineStart = code.lastIndexOf("\n", m.index) + 1;
        if (/\b(?:console|logger|log)\.\w+\(|new Response\(|throw new/.test(code.slice(lineStart, m.index))) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "unvirtualized-list",
    family: "performance",
    severity: "noticeable",
    stacks: ["js", "swift", "kotlin", "dart"],
    message: "A list built by mapping items inside a plain scroll container. Every row renders up front.",
    fix: "Use the virtualized list: FlatList or FlashList, List or LazyVStack, LazyColumn, ListView.builder. Then profile scrolling on a real device.",
    find({ code, stack }) {
      const hits = [];
      if (stack === "js") {
        for (const m of matches(/(?<![\w.])<(?:Animated\.)?ScrollView\b/, code)) {
          const openEnd = tagEnd(code, m.index + m[0].length);
          if (openEnd === -1) continue;
          if (/\/\s*$/.test(code.slice(m.index + m[0].length, openEnd))) continue;
          const rest = code.slice(openEnd + 1);
          const closeRel = rest.search(/<\/(?:Animated\.)?ScrollView>/);
          if (closeRel === -1) continue;
          // Horizontal scrollers are usually short chip rows and carousels.
          const props = code.slice(m.index, openEnd + 1);
          if (/\bhorizontal\b(?!\s*=\s*\{\s*false\s*\})/.test(props)) continue;
          const body = rest.slice(0, closeRel);
          if (/\.map\(/.test(body)) hits.push(m.index);
        }
      }
      if (stack === "swift") {
        for (const m of matches(/\bScrollView\b[^{\n]*\{\s*VStack\b/, code)) {
          const open = code.indexOf("{", m.index);
          if (/\bForEach\b/.test(code.slice(open, closeOf(code, open)))) hits.push(m.index);
        }
      }
      if (stack === "kotlin") {
        for (const m of matches(/\bColumn\s*\(/, code)) {
          const head = code.slice(m.index, closeOf(code, m.index + m[0].length - 1));
          if (!/verticalScroll/.test(head)) continue;
          const bodyOpen = code.indexOf("{", m.index + head.length);
          if (bodyOpen === -1 || bodyOpen - (m.index + head.length) > 5) continue;
          if (/\.forEach\b|\bfor\s*\(/.test(code.slice(bodyOpen, closeOf(code, bodyOpen)))) hits.push(m.index);
        }
      }
      if (stack === "dart") {
        for (const m of matches(/\bSingleChildScrollView\s*\(|\bListView\s*\(/, code)) {
          const open = m.index + m[0].length - 1;
          const body = code.slice(open, closeOf(code, open));
          if (/children:/.test(body) && /\.map\(|\bfor\s*\(/.test(body)) hits.push(m.index);
        }
      }
      return hits;
    },
  },
  {
    id: "fixed-text-size",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["swift", "js", "dart", "xml"],
    message: "Text that ignores the user's text size setting.",
    fix: "Use platform text styles (.body, MaterialTheme.typography, textTheme) or scale custom sizes (relativeTo:, UIFontMetrics, sp). Then check the screen at the largest size.",
    find({ code, stack }) {
      if (stack === "swift") {
        if (macOnlySwift(code)) return [];
        const hits = [...matches(/\.system\(\s*size:|\.custom\(\s*"[^"]*"\s*,\s*size:\s*[\d.]+\s*\)/, code)].map((m) => m.index);
        if (!/UIFontMetrics|adjustsFontForContentSizeCategory/.test(code)) {
          for (const m of matches(/UIFont\.(?:systemFont|boldSystemFont)\(\s*ofSize:|UIFont\(\s*name:/, code)) hits.push(m.index);
        }
        return hits;
      }
      const re = {
        js: /allowFontScaling\s*[=:]\s*\{?\s*false|maxFontSizeMultiplier\s*[=:]\s*\{?\s*1(?:\.0+)?(?![\d.])/,
        dart: /textScaleFactor:\s*1(?:\.0+)?(?![\d.])|TextScaler\.noScaling|textScaler:\s*(?:const\s+)?TextScaler\.linear\(\s*1(?:\.0)?\s*\)/,
        xml: /android:textSize="\d+(?:\.\d+)?(?:dp|px|dip)"/,
      }[stack];
      return [...matches(re, code)].map((m) => m.index);
    },
  },
  {
    id: "back-gesture",
    family: "native-fit",
    severity: "noticeable",
    stacks: ["swift", "js", "kotlin", "dart", "xml"],
    message: "System back gesture disabled, hidden, or handled the deprecated way.",
    fix: "Keep edge-swipe back on iOS and predictive back on Android. Guard only real data loss (PopScope, OnBackPressedCallback, usePreventRemove) and say why.",
    find({ code, stack }) {
      const re = {
        swift: /interactivePopGestureRecognizer\??\.isEnabled\s*=\s*false|\.navigationBarBackButtonHidden\(\s*(?:true)?\s*\)/,
        js: /gestureEnabled\s*[:=]\s*\{?\s*false|fullScreenGestureEnabled\s*[:=]\s*\{?\s*false/,
        kotlin: /override\s+fun\s+onBackPressed\s*\(/,
        dart: /\bWillPopScope\s*\(/,
        xml: /android:enableOnBackInvokedCallback="false"/,
      }[stack];
      return [...matches(re, code)].map((m) => m.index);
    },
  },
  {
    id: "drawer-nav",
    family: "native-fit",
    severity: "noticeable",
    stacks: null,
    platforms: ["mobile", "universal"],
    message: "Hamburger menu or navigation drawer. It hides the top destinations behind a tap.",
    fix: "Ask first. Use tabs for three to five peer destinations; keep a drawer only for many destinations or a large-screen rail.",
    find({ code }) {
      const re = /["']line\.(?:3\.horizontal|horizontal\.3)["']|\bIcons\.(?:Default\.|Filled\.|Outlined\.|Rounded\.|Sharp\.)?Menu\b|\bIcons\.menu(?:_rounded|_outlined|_sharp)?\b|\b(?:name|icon)=["']menu(?:-outline|-sharp)?["']|\bcreateDrawerNavigator\b|from\s+["']expo-router\/drawer["']|\bModalNavigationDrawer\b|\bdrawer:\s*(?:const\s+)?\w*Drawer\b|<ion-menu\b|<IonMenu(?:Button|Toggle)?\b|<(?:q-drawer|QDrawer)(?![\w-])|\bBars3(?:BottomLeft|BottomRight|CenterLeft)?Icon\b|\bIconMenu2\b/;
      const first = matches(re, code).next();
      return first.done ? [] : [first.value.index];
    },
  },
  {
    id: "hover-only",
    family: "native-fit",
    severity: "minor",
    stacks: ["js", "web", "css"],
    platforms: ["mobile"],
    message: "Hover behavior in a touch app. Nobody hovers on a phone.",
    fix: "Make the information or control visible without hover, or guard it with @media (hover: hover) for pointer devices only.",
    find({ code }) {
      if (/hover:\s*hover/.test(code)) return [];
      return [...matches(/\bonHoverIn\b|\bonMouseEnter\b|\bonMouseOver\b|:hover\b/, code)].map((m) => m.index);
    },
  },
  {
    id: "keyboard-cover",
    family: "interaction",
    severity: "minor",
    stacks: ["js"],
    message: "Screen with a text input and no keyboard handling. The keyboard may cover the field.",
    fix: "Use KeyboardAvoidingView, automaticallyAdjustKeyboardInsets, or the project's keyboard library, and set keyboardShouldPersistTaps on the scroll view. Check it on a small phone.",
    find({ code, file }) {
      const input = /<TextInput\b/.exec(code);
      if (!input) return [];
      const where = file.replace(/\\/g, "/");
      const name = path.basename(where).replace(/\.[^.]+$/, "");
      const screenPath = /(?:^|\/)screens\//.test(where) || /Screen$/.test(name) || (/(?:^|\/)app\//.test(where) && !name.startsWith("_"));
      if (!screenPath && !/<(?:ScrollView|FlatList|FlashList|SafeAreaView|KeyboardAwareScrollView)\b/.test(code)) return [];
      if (/KeyboardAvoidingView|KeyboardAware|KeyboardProvider|KeyboardStickyView|KeyboardController|automaticallyAdjustKeyboardInsets|keyboardShouldPersistTaps/.test(code)) return [];
      // A screen can also move itself with the keyboard through a hook: Reanimated's
      // useAnimatedKeyboard, or useKeyboardHandler / useReanimatedKeyboardAnimation from
      // react-native-keyboard-controller (#286). The hook has to be called, not just imported.
      if (/\b(?:useAnimatedKeyboard|useKeyboardHandler|useReanimatedKeyboardAnimation)\s*\(/.test(code)) return [];
      return [input.index];
    },
  },
  {
    id: "safe-area-off",
    family: "native-fit",
    severity: "minor",
    stacks: ["swift"],
    message: "Safe area ignored. Content may sit under the notch or home indicator.",
    fix: "Ignore the safe area for backgrounds only, e.g. .background(Color.surface.ignoresSafeArea()).",
    find({ code }) {
      const hits = [];
      for (const m of matches(/\.ignoresSafeArea\(\s*(?:\.(?:all|container)\s*)?(?:,?\s*edges:\s*\.all\s*)?\)|\.edgesIgnoringSafeArea\(\s*\.all\s*\)/, code)) {
        if (isBackgroundSafeArea(code, m.index)) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "tracked-caps-label",
    family: "looks-generated",
    severity: "minor",
    stacks: ["js", "web", "css", "swift"],
    message: "Small label in tracked capitals, the eyebrow above every section.",
    fix: "Use sentence case in the body face, one step smaller, without letter spacing. Or delete the label and let the heading carry the section.",
    find({ code, stack }) {
      const hits = [];
      for (const m of matches(/["'`][^"'`\n]*\buppercase\b[^"'`\n]*["'`]/, code)) {
        if (/\btracking-(?:wide|wider|widest|\[(?:\d|\.\d))/.test(m[0])) hits.push(m.index);
      }
      if (stack === "js") {
        for (const m of matches(/textTransform:\s*["']uppercase["']/, code)) {
          const around = code.slice(Math.max(0, m.index - 160), m.index + 160);
          const ls = /letterSpacing:\s*(\d+(?:\.\d+)?)/.exec(around);
          if (ls && +ls[1] >= 0.8) hits.push(m.index);
        }
      }
      if (stack === "css" || stack === "web") {
        for (const m of matches(/text-transform:\s*uppercase/, code)) {
          const open = code.lastIndexOf("{", m.index);
          const close = code.indexOf("}", m.index);
          const block = code.slice(open, close === -1 ? undefined : close);
          if (/letter-spacing:\s*(?:(?:0?\.(?:0[5-9]|[1-9])\d*|[1-9][\d.]*)r?em|[1-9][\d.]*px)/.test(block)) hits.push(m.index);
        }
      }
      if (stack === "swift") {
        for (const m of matches(/\.textCase\(\s*\.uppercase\s*\)/, code)) {
          const around = code.slice(Math.max(0, m.index - 160), m.index + 160);
          if (/\.(?:tracking|kerning)\(\s*[1-9]/.test(around)) hits.push(m.index);
        }
      }
      return hits;
    },
  },
  {
    id: "icon-tile",
    family: "looks-generated",
    severity: "minor",
    stacks: ["js", "web"],
    message: "Icon in a tinted rounded square, the generated default for every row and feature card.",
    fix: "Put the icon inline in the text color, or drop it. Keep a tile only where the shape carries meaning, like an app icon.",
    find({ code }) {
      const hits = [];
      for (const m of matches(/["'`][^"'`\n]{0,300}["'`]/, code)) {
        const c = m[0];
        if (!/\brounded-(?:md|lg|xl|2xl|3xl|full)\b/.test(c)) continue;
        if (!/\bbg-(?:[a-z]+-(?:50|100)|[a-z]+(?:-\d{3})?\/(?:5|10|15|20)|primary\/\d+|accent)\b/.test(c)) continue;
        if (!/\b(?:size|h|w)-(?:8|9|10|11|12|14)\b/.test(c)) continue;
        if (!/\b(?:items-center|place-items-center|justify-center)\b/.test(c)) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "transition-all",
    family: "motion",
    severity: "minor",
    stacks: ["js", "web", "css"],
    message: "Transition on every property (first use in this file).",
    fix: "Name the properties: transition-colors, or transition-[transform,opacity]. Never animate width, height, top, or left.",
    find({ code }) {
      // Reported once per file: it is usually a habit, not a one-off.
      // `all` may sit anywhere in the list, not just first:
      // `transition: color .2s, all .3s` counts, but a property name that
      // merely starts with `all` (e.g. `all-in-one`) does not.
      // In a CSS-in-JS value the scan stops at the closing quote, so
      // `pointerEvents: "all"` later in the same style object is not read
      // as part of `transition: "opacity .2s"`.
      // A shorthand whose first layer names no property (`transition: .3s
      // ease`, `transition: ease-in 200ms`) defaults to `all` as well; the
      // whole layer must be timing values, so `.2s opacity` stays quiet.
      const first = matches(/\btransition-all\b|transition(?:-property|Property)?:\s*["'`]?[^;{}"'`]*?(?<![\w-])all(?![\w-])|(?<![\w-])transition:\s*["'`]?\s*(?:(?:ease(?:-in-out|-in|-out)?|linear(?:\([^)]*\))?|step-start|step-end|(?:cubic-bezier|steps)\([^)]*\)|allow-discrete|normal)\s+)*\d*\.?\d+m?s\b(?:\s+(?:(?:ease(?:-in-out|-in|-out)?|linear(?:\([^)]*\))?|step-start|step-end|(?:cubic-bezier|steps)\([^)]*\)|allow-discrete|normal)|\d*\.?\d+m?s\b))*\s*(?=[,;}"'`\n]|$)/, code).next();
      return first.done ? [] : [first.value.index];
    },
  },
  {
    id: "hover-scale",
    family: "motion",
    severity: "minor",
    stacks: ["js", "web", "css"],
    message: "Cards that grow on hover.",
    fix: "Show hover with a quick color or surface change. Keep scale for a small press-down on buttons.",
    find({ code }) {
      // `group-hover/card:` is a Tailwind named group (3.2 and later, #287).
      return [...matches(/\b(?:group-hover(?:\/[\w-]+)?|hover):(?:-translate-y-(?:\d|px|\[[^\]]+\])|translate-y-\[-[^\]]+\]|scale-1(?:0[2-9]|[1-9]\d)\b|scale-\[(?:1\.(?:0[2-9]\d*|[1-9]\d*)|[2-9]\d*(?:\.\d+)?)\])|(?:&?:hover\s*|["']&?:hover["']\s*:\s*)\{[^}]*transform:\s*[^;}]*?\b(?:scale(?:3d)?\(\s*(?:1\.(?:0[2-9]\d*|[1-9]\d*)|[2-9]\d*(?:\.\d+)?)\b|translateY\(\s*-\s*(?:\d*\.)?\d+|translate(?:3d)?\(\s*(?:[^,;()]|\([^()]*\))+,\s*-\s*(?:\d*\.)?\d+)|:hover\s*\{[^}]*?(?<![\w-])scale\s*:\s*(?:1\.0[2-9]\d*|1\.[1-9]\d*)\b|:hover\s*\{[^}]*?(?<![\w-])translate\s*:\s*(?:[^\s;}()]|\([^()]*\))+\s+-\s*(?:\d*\.)?\d+|\bwhileHover=\{\s*\{[^}]*?\b(?:scale\s*:\s*(?:1\.(?:0[2-9]\d*|[1-9]\d*)|[2-9]\d*(?:\.\d+)?)|y\s*:\s*-\s*(?:\d*\.)?\d+)\b/, code)].map((m) => m.index);
    },
  },
  {
    id: "decorative-pulse",
    family: "motion",
    severity: "minor",
    stacks: ["js", "web"],
    message: "Pulsing or pinging element that is not a loading skeleton.",
    fix: "Animate only what is live or loading. Remove looping motion from badges, dots, and buttons.",
    find({ code }) {
      const hits = [];
      for (const m of matches(/["'`][^"'`\n]*\banimate-(?:pulse|ping)\b[^"'`\n]*["'`]/, code)) {
        if (/\banimate-pulse\b/.test(m[0]) && /\bbg-(?:gray|slate|zinc|neutral|stone|muted)\b|skeleton/i.test(m[0])) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "reduced-motion",
    family: "motion",
    severity: "minor",
    stacks: ["js", "web", "css"],
    message: "Animation with no prefers-reduced-motion fallback (first use in this file).",
    fix: "Add a @media (prefers-reduced-motion: reduce) fallback, guard the class with a motion-reduce: variant, or check useReducedMotion() / AccessibilityInfo in JS.",
    find({ code }) {
      // Reported once per file, like transition-all: a missing fallback
      // is usually a habit, not a one-off. A fallback anywhere in the
      // file covers it, so the check is file-wide.
      if (/prefers-reduced-motion|\breduceMotionChanged\b/.test(code)) return [];
      const unquoted = code.replace(/"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`/g, '""');
      if (/\buseReducedMotion(?:Config)?\s*\(|\bAccessibilityInfo\.isReduceMotionEnabled\b|\bReduceMotion\./.test(unquoted)) return [];
      const hits = [];
      // Plain CSS: the first @keyframes block or animation: declaration.
      const css = matches(/@keyframes\b|\banimation\s*:\s*["'`]?(?!none\b)[^;"'`\n]*?\d*\.?\d+m?s\b/, code).next();
      if (!css.done) hits.push(css.value.index);
      // Tailwind: an animate-* class with no motion-safe: or
      // motion-reduce: variant in the same class string. animate-spin is
      // a spinner and animate-none turns motion off, so neither counts;
      // skeleton pulses are loading states, like decorative-pulse.
      for (const m of matches(/["'`][^"'`\n]*\banimate-(?:(?!spin\b)(?!none\b)[\w-]+|\[[^\s"'`\]]+\])[^"'`\n]*["'`]/, code)) {
        if (/\bmotion-(?:safe|reduce):/.test(m[0])) continue;
        if (/\banimate-pulse\b/.test(m[0]) && /\bbg-(?:gray|slate|zinc|neutral|stone|muted)\b|skeleton/i.test(m[0])) continue;
        hits.push(m.index);
        break;
      }
      return hits.length ? [Math.min(...hits)] : [];
    },
  },
  {
    id: "unverified-claim",
    family: "truthfulness",
    severity: "noticeable",
    stacks: null,
    message: "Social proof or speed claim that the page does not back up.",
    fix: "Use a real, sourced number with what it compares to, or remove it. Never ship invented customer counts, logo walls, or testimonials.",
    find({ code }) {
      const re = /\b(?:trusted|loved|used) by (?:over |more than )?[\d,.]+\s*[kKM]?\+?\s*(?:[A-Za-z]+\s+)?(?:teams|companies|developers|users|customers|people|businesses)|\bjoin (?:over |more than )?[\d,.]+\s*[kKM]?\+?\s+(?:[A-Za-z]+\s+)?(?:teams|companies|developers|users|customers|people|businesses|others|creators)|\b\d+x (?:faster|better|more productive|cheaper)\b/i;
      return [...matches(re, code)].map((m) => m.index);
    },
  },
  {
    id: "clickable-div",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["js", "web"],
    message: "Click handler on a non-interactive element such as a div, span or article. Keyboard and screen reader users cannot reach it.",
    fix: "Use a <button> for actions and an <a href> for navigation. They come with focus, Enter and Space, and the right role.",
    find({ code }) {
      const hits = [];
      // Each opening tag is read to its real end first, so an arrow function in an earlier
      // attribute (`onKeyDown={(e) => ...}`) does not hide the click handler after it.
      for (const m of matches(/<(?:div|span|li|td|tr|img|a|article|section|h[1-6]|p|header|footer|figure)(?=[\s/>])/, code)) {
        const end = tagEnd(code, m.index + m[0].length);
        const tag = code.slice(m.index, end === -1 ? undefined : end);
        // Only this element's own attributes: a nested element inside {...} is checked on its own.
        let top = m[0];
        walkTag(code, m.index + m[0].length, (i) => { top += code[i]; });
        // onClick/onclick (React, HTML), onClick$ (Qwik), @click/v-on:click (Vue, Alpine),
        // x-on:click (Alpine), on:click (Svelte) and (click) (Angular).
        if (!/\s(?:(?:on[cC]lick\$?|@click|v-on:click|x-on:click|on:click)(?:\.[\w-]+|\|\w+)*|\(click\))\s*=/.test(top)) continue;
        if (/^<a\b/.test(tag) && /(?:^|[\s{:[])href\]?\s*=/.test(tag)) continue;
        // A non-semantic clickable element (or href-less anchor) is only
        // keyboard- and screen-reader-accessible when it has both an
        // interactive ARIA role and a tabIndex.
        if (
          /\brole\s*=\s*["'{`]*\s*(?:button|link|checkbox|menuitem(?:checkbox|radio)?|option|radio|switch|tab|textbox|combobox|gridcell|searchbox|slider|spinbutton|treeitem)\b/.test(tag) &&
          /\btab[iI]ndex\s*=/.test(tag)
        ) {
          continue;
        }
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "focus-removed",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["js", "web", "css"],
    message: "Focus outline removed with nothing in its place.",
    fix: "Keep a visible :focus-visible style in the palette: a 2px outline or ring with an offset.",
    find({ code, stack }) {
      const hits = [];
      // Tailwind's `outline-0` sets `outline-width: 0px`, which hides the ring
      // like `outline-none` does (#283).
      for (const m of matches(/["'`][^"'`\n]*\b(?:focus:)?outline-(?:none|hidden|0)\b[^"'`\n]*["'`]/, code)) {
        // Focus styles often sit in another string of the same cn(...) call.
        const around = code.slice(Math.max(0, m.index - 400), m.index + m[0].length + 400);
        // The removal token itself, with any variants (`focus:outline-none`,
        // Tailwind v4's `focus-visible:outline-hidden`), must not count as the
        // replacement focus style it is missing.
        const withoutMatch = around.replace(/(?<![\w:-])(?:[\w-]+:)*outline-(?:none|hidden|0)\b/g, "");
        if (/\b(?:focus|focus-visible|focus-within|group-focus-visible|peer-focus-visible):|data-\[(?:highlighted|selected|focus|focused)|aria-selected:|data-\[state=/.test(withoutMatch)) continue;
        hits.push(m.index);
      }
      if (!/focus-visible/.test(code)) {
        for (const m of matches(/outline:\s*(?:["']?none["']?|0\b)/, code)) hits.push(m.index);
        // The longhand: `outline-style: none` in CSS and `outlineStyle: "none"`
        // in a JS style object (#250) remove the focus outline just the same.
        for (const m of matches(/outline-style\s*:\s*["']?none\b["']?|outlineStyle\s*:\s*["']?none\b["']?/, code)) hits.push(m.index);
        // Setting the width to zero (`outline-width: 0` in CSS, `outlineWidth: 0`
        // in a JS style object, #263) hides the focus ring just the same.
        for (const m of matches(/(?:outline-width|outlineWidth)\s*:\s*["']?0(?:px)?(?![.\d])\b["']?/, code)) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "img-no-alt",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["js", "web"],
    message: "Image without alt text.",
    fix: "Describe what the image shows, or use alt=\"\" for pure decoration.",
    find({ code, stack }) {
      const hits = [];
      // Nuxt Image renders <NuxtImg> / <NuxtPicture>, also written kebab-case (#203).
      // Vuetify renders <v-img> / <VImg> as an <img> too (#229).
      // Ionic renders <ion-img> / <IonImg> as an <img> too (#235).
      // Quasar renders <q-img> / <QImg> and Element Plus <el-image> / <ElImage> as <img> too (#249).
      // Astro renders <Picture> as an <img> too (#268).
      // So do Gatsby's <StaticImage> and <GatsbyImage> from gatsby-plugin-image (#285).
      // SvelteKit's <enhanced:img> from @sveltejs/enhanced-img renders an <img> too (#304).
      for (const m of matches(/<(?:img|enhanced:img|Image|Picture|NuxtImg|NuxtPicture|nuxt-img|nuxt-picture|v-img|VImg|ion-img|IonImg|q-img|QImg|el-image|ElImage|StaticImage|GatsbyImage)(?=[\s/>])/, code)) {
        const end = tagEnd(code, m.index);
        const tag = code.slice(m.index, end === -1 ? undefined : end);
        if ((tag.startsWith("<Image") || tag.startsWith("<Picture")) && !/\ssrc\s*=/.test(tag)) continue;
        const hasAlt = /[\s:\[.]alt\]?\s*=|\{\s*alt\s*\}|\{\s*\.\.\./.test(tag)
          || (stack === "web" && /\salt(?=[\s/>]|$)/.test(tag.replace(/=\s*(?:"[^"]*"|'[^']*')/g, '=""')));
        if (!hasAlt) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "placeholder-label",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["js", "web"],
    message: "Input uses a placeholder as its only label.",
    fix: "Give the field a real label: wrap it in <label>, point a <label htmlFor> at its id, or add aria-label. Placeholders disappear while typing and are not read as labels.",
    find({ code }) {
      // Ids a <label for/htmlFor> in this file points to (static strings only).
      const labelledBy = new Set();
      const attrValue = (v) => v.replace(/^[{"'\s]+|[}"'\s]+$/g, "");
      for (const m of matches(/<label\b[^<>]*?\s:?(?:htmlFor|for)\s*=\s*("[^"]+"|'[^']+'|\{[^{}]+\})/, code)) {
        labelledBy.add(attrValue(m[1]));
      }
      // Ranges wrapped in a <label>...</label> pair.
      const wrapped = [];
      for (const m of matches(/<label\b[^<>]*>/, code)) {
        const tag = m[0];
        if (/\/\s*>$/.test(tag)) continue;
        const close = code.indexOf("</label>", m.index + tag.length);
        if (close !== -1) wrapped.push([m.index, close]);
      }
      const hits = [];
      for (const m of matches(/<(?:input|textarea)(?=[\s/>])/, code)) {
        const end = tagEnd(code, m.index);
        const tag = code.slice(m.index, end === -1 ? undefined : end);
        if (!/[\s:]placeholder\s*=/.test(tag)) continue;
        if (/[\s:]aria-label\s*=|[\s:]aria-labelledby\s*=/.test(tag)) continue;
        const type = /[\s:]type\s*=\s*(?:"([^"]*)"|'([^']*)'|\{\s*"([^"]*)"\s*\}|\{\s*'([^']*)'\s*\})/.exec(tag);
        const typeVal = (type?.[1] ?? type?.[2] ?? type?.[3] ?? type?.[4] ?? "").toLowerCase();
        // Hidden and submit inputs need no label; a search input with
        // aria-label is already exempt above.
        if (typeVal === "hidden" || typeVal === "submit") continue;
        if (/\{\s*\.\.\./.test(tag)) continue;
        const id = /[\s:]id\s*=\s*("[^"]+"|'[^']+'|\{[^{}]+\})/.exec(tag);
        if (id && labelledBy.has(attrValue(id[1]))) continue;
        if (wrapped.some(([start, close]) => m.index > start && m.index < close)) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "zoom-disabled",
    family: "accessibility",
    severity: "noticeable",
    stacks: ["js", "web"],
    message: "Pinch zoom disabled in the viewport settings.",
    fix: "Remove maximum-scale and user-scalable from the viewport. If inputs zoom on focus in iOS, give them a 16px font size instead.",
    find({ code }) {
      return [...matches(/user-scalable\s*=\s*(?:no|0)|maximum-scale\s*=\s*1(?:\.0+)?(?![\d.])|userScalable:\s*false|maximumScale:\s*1(?:\.0+)?(?![\d.])/, code)].map((m) => m.index);
    },
  },
  {
    id: "oops-error",
    family: "copy",
    severity: "noticeable",
    stacks: null,
    message: "\"Oops\" or \"Something went wrong\": no cause, no next step.",
    fix: "Say what failed in the product's words and what the user can do: retry, check the connection, contact support.",
    find({ code }) {
      const hits = [];
      for (const m of matches(/\b(?:wh)?oops\b|something went wrong/i, code)) {
        // Log calls and thrown errors never reach the user, so skip a match
        // inside one: console.*, logger.*, Log.*, print, debugPrint, NSLog,
        // or `throw new Error(...)`. Only the call itself hides the match —
        // visible copy after the call closed on the same line still flags.
        if (insideLogCall(code, m.index)) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "buzzword-copy",
    family: "copy",
    severity: "minor",
    stacks: null,
    message: "Marketing filler in the interface.",
    fix: "Say what the screen does in plain words, or delete the line.",
    find({ code }) {
      const re = /unlock (?:your|the) (?:full )?potential|\bseamless(?:ly)?\b|\beffortless(?:ly)?\b|\bsupercharg\w*|all in one place|\bnext[- ]level\b|\belevate your\b|\bgame[- ]?changer\b|\brevolutioni[sz]\w*|\bunleash\b|\bempower(?:s|ing)? you/i;
      const hits = [];
      for (const m of matches(re, code)) {
        // The line up to the match, at most 300 characters back.
        const back = code.slice(Math.max(0, m.index - 300), m.index);
        const before = back.slice(back.lastIndexOf("\n") + 1);
        const after = code.slice(m.index + m[0].length, m.index + m[0].length + 3);
        // A package name in a module string (`from "@unleash/..."`, `require("unleash-client")`, also
        // with the string on the next line), a name on an import line, or a name inside a multi-line
        // `import { ... }` clause is not copy.
        if (/\b(?:import|export)\b[^;"'`]*\bfrom\s*["'`][^"'`\n]*$/.test(back)) continue;
        if (/\b(?:import|require)\s*\(\s*["'`][^"'`\n]*$/.test(back)) continue;
        // a side-effect import: `import "unleash-client";`
        if (/(?:^|[\n;])\s*import\s+["'`][^"'`\n]*$/.test(back)) continue;
        if (/^\s*import\b[^"'`;]*$/.test(before)) continue;
        if (/(?:^|[\n;])\s*(?:import|export)\s+(?:type\s+)?(?:\w+\s*,\s*)?\{[^};`]*$/.test(code.slice(Math.max(0, m.index - 2000), m.index))) continue;
        // Nor is unleash used as code: `const unleash = ...`, `new Unleash(...)`,
        // `unleash.isEnabled(...)`, `{ unleash }`, `{ unleash: cfg }`.
        if (/^unleash$/i.test(m[0]) && /\b(?:const|let|var|new)\s+$/.test(before)) continue;
        // An object key or destructured name needs a brace or a key colon, so `Dream, unleash, create.` is copy.
        if (m[0] === "unleash" && (/^\.[A-Za-z_$]/.test(after) || (/\{[^{}]*$/.test(before) && /[{,]\s*$/.test(before) && /^\s*[:,}]/.test(after)))) continue;
        hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "welcome-back",
    family: "copy",
    severity: "minor",
    stacks: null,
    message: "\"Welcome back\" spending prime screen space on a greeting.",
    fix: "Use that space for what a returning user came to do.",
    find({ code }) {
      // Flag the greeting with or without "!": "Welcome back", "Welcome back,
      // Sarah", "Welcome back, {name}", "Welcome back!". The comma branch only
      // accepts a name (one or two words, or a {expression} or ${expression}), so prose after
      // the comma ("Welcome back, we have updated the team page.") stays
      // quiet. The lookahead is the guard against prose: the greeting must end
      // at punctuation, a string/JSX boundary (including a closing
      // backtick), or the end of the line, so "Welcome back to the team page"
      // stays quiet.
      return [...matches(/welcome back\s*(?:,\s*(?:\$?\{[^}\n]*\}|[A-Za-z][A-Za-z'’\-]*(?:\s+[A-Za-z][A-Za-z'’\-]*)?))?(?=[!?.]|["'`}]|\s*<|$)/i, code)].map((m) => m.index);
    },
  },
  {
    id: "vague-button",
    family: "copy",
    severity: "minor",
    stacks: null,
    message: "Button label that does not say what happens.",
    fix: "Use a verb and an object: \"Save address\", \"Send invoice\", \"Book table\".",
    find({ code }) {
      const hits = [...matches(/(?:title|label|text)\s*[=:]\s*\{?\s*["'](?:Submit|Click here|Tap here)["']|>\s*(?:Submit|Click here|Tap here)\s*</i, code)].map((m) => m.index);
      // An <input type="submit|button"> carries its label in value=. The tag is read to
      // its real end, so `onClick={() => go()}` or `disabled={n > 0}` does not cut it, and
      // other attributes' quoted values (`title="type=submit"`) are left out.
      for (const m of matches(/<input\b/i, code)) {
        const end = tagEnd(code, m.index + m[0].length);
        const tag = code
          .slice(m.index, end === -1 ? undefined : end)
          .replace(/(?<![\w-])(?!type\b|value\b)[\w:@.-]+\s*=\s*(?:"[^"]*"|'[^']*')/gi, "");
        if (
          /(?<![\w-])type\s*=\s*\{?\s*(["']?)(?:submit|button)\1(?![\w-])/i.test(tag) &&
          /(?<![\w-])value\s*=\s*(?:\{\s*(["'`])(?:Submit|Click here|Tap here)\1\s*\}|(["'])(?:Submit|Click here|Tap here)\2|Submit(?=\s|\/?$))/i.test(tag)
        ) {
          hits.push(m.index);
        }
      }
      // Native buttons: the label only counts inside a button call, so a
      // bare Text("Submit") used as a heading or field label stays quiet.
      // Button("Submit") { save() } or Button { save() } label: { Text("Submit") } (Swift),
      // Button(onClick = {}) { Text("Submit") } (Compose trailing lambda), ElevatedButton(...,
      // child: Text("Submit")) (Flutter). Only the first argument or a
      // Text(...)/Label(...) label counts, so a vague string in the action code does not.
      const isVagueText = (s) => /^(?:submit|click here|tap here)$/i.test(s);
      const hasVagueLabel = (slice) => {
        const first = /^\(\s*["']([^"']+)["']/.exec(slice);
        if (first && isVagueText(first[1])) return true;
        for (const t of matches(/\b(?:Text|Label)\(\s*["']([^"']+)["']/, slice)) {
          if (isVagueText(t[1])) return true;
        }
        return false;
      };
      for (const m of matches(/\b(?:ElevatedButton|TextButton|OutlinedButton|FilledButton|Button)\s*\(/, code)) {
        const open = m.index + m[0].length - 1;
        let end = closeOf(code, open);
        const lambda = /^\s*\{/.exec(code.slice(end));
        if (lambda) end = closeOf(code, end + lambda[0].length - 1);
        const trailingLabel = /^\s*label\s*:\s*\{/.exec(code.slice(end));
        if (trailingLabel) {
          const labelOpen = end + trailingLabel[0].length - 1;
          const labelEnd = closeOf(code, labelOpen);
          if (hasVagueLabel(code.slice(labelOpen, labelEnd))) hits.push(m.index);
        } else if (hasVagueLabel(code.slice(open, end))) {
          hits.push(m.index);
        }
      }
      // SwiftUI multiple-trailing-closure form: Button { save() } label: { Text("Submit") }.
      for (const m of matches(/\bButton\s*\{/, code)) {
        const actionOpen = m.index + m[0].length - 1;
        const actionEnd = closeOf(code, actionOpen);
        const trailingLabel = /^\s*label\s*:\s*\{/.exec(code.slice(actionEnd));
        if (!trailingLabel) continue;
        const labelOpen = actionEnd + trailingLabel[0].length - 1;
        const labelEnd = closeOf(code, labelOpen);
        if (hasVagueLabel(code.slice(labelOpen, labelEnd))) hits.push(m.index);
      }
      return hits;
    },
  },
  {
    id: "invented-stat",
    family: "truthfulness",
    severity: "minor",
    stacks: ["swift", "kotlin", "dart", "js", "web"],
    message: "Hard-coded statistic in the interface.",
    fix: "Compute it from real data, or mark it as placeholder content. Stat tiles with invented numbers mislead users.",
    find({ code }) {
      // A number with %, k, M or + shown as text: JSX text, Text("..."), or a
      // value/stat field in a data literal. Widths and other style values are not text.
      const stat = String.raw`[+↑↓]?\d{1,3}(?:[.,]\d{1,3})*\s*(?:%|[kKM]\+?|\+)`;
      const re = new RegExp(
        String.raw`>\s*${stat}\s*<|\bText\(\s*(?:text\s*=\s*)?["']${stat}["']|\b(?:value|stat|metric|count|total|number|figure)\s*:\s*["']${stat}["']`,
        "g",
      );
      return [...matches(re, code)].map((m) => m.index);
    },
  },
];

// ---------- scanning ----------

function unknownRuleIds(ids) {
  const known = new Set(rules.map((r) => r.id));
  return ids.filter((id) => !known.has(id));
}

function loadConfig(root) {
  // The nearest project config above the scan target wins; the current
  // directory's config is the last fallback.
  const candidates = [];
  for (let dir = path.resolve(root); ; dir = path.dirname(dir)) {
    candidates.push(path.join(dir, ".unslop-anything", "config.json"), path.join(dir, ".unslopovich", "config.json"));
    if (path.dirname(dir) === dir) break;
  }
  candidates.push(path.join(process.cwd(), ".unslop-anything", "config.json"), path.join(process.cwd(), ".unslopovich", "config.json"));
  for (const file of candidates) {
    let source;
    try {
      source = fs.readFileSync(file, "utf8");
    } catch (err) {
      if (err.code === "ENOENT") continue;
      throw new Error(`Could not read config ${file}: ${err.message}`);
    }
    let raw;
    try {
      raw = JSON.parse(source);
    } catch (err) {
      throw new Error(`Could not parse config ${file}: ${err.message}`);
    }
    const ignoreRules = raw.ignoreRules || [];
    const unknown = unknownRuleIds(ignoreRules);
    if (unknown.length) {
      throw new Error(`Config ${file}: Unknown rule: ${unknown.join(", ")}. See --list-rules.`);
    }
    return { ignoreRules, ignorePaths: raw.ignorePaths || [] };
  }
  return { ignoreRules: [], ignorePaths: [] };
}

// What the nearest package.json says the code ships to: "mobile", "universal"
// (mobile and web), "web", or "unknown". Some rules only apply to one of them.
const kindCache = new Map();
function projectKind(dir) {
  if (kindCache.has(dir)) return kindCache.get(dir);
  let kind = "unknown";
  let pkg = null;
  try {
    pkg = fs.readFileSync(path.join(dir, "package.json"), "utf8");
  } catch {
    // No package.json here.
  }
  if (pkg !== null) {
    const deps = (() => {
      try {
        const j = JSON.parse(pkg);
        return Object.keys({ ...j.dependencies, ...j.devDependencies, ...j.peerDependencies });
      } catch {
        return [];
      }
    })();
    const has = (re) => deps.some((d) => re.test(d));
    const mobile = has(/^(?:react-native|expo|@capacitor\/|@ionic\/|nativescript|@nativescript\/)/);
    const universal = has(/^(?:react-native-web|@expo\/metro-runtime)$/);
    const web = has(/^(?:react-dom|next|vue|nuxt|svelte|@sveltejs\/kit|astro|@angular\/core|solid-js|@remix-run\/|vite|preact|gatsby)$/);
    kind = mobile ? (universal ? "universal" : "mobile") : web ? "web" : "unknown";
  }
  // A package.json that names no platform (a tooling or workspace package)
  // says nothing, so keep looking upward.
  if (kind === "unknown" && path.dirname(dir) !== dir) kind = projectKind(path.dirname(dir));
  kindCache.set(dir, kind);
  return kind;
}

function walk(target, opts, out = []) {
  let stat;
  try {
    stat = fs.statSync(target);
  } catch {
    throw new Error(`Cannot read ${target}`);
  }
  if (stat.isFile()) {
    if (STACK_BY_EXT[path.extname(target).toLowerCase()]) out.push(target);
    return out;
  }
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    const full = path.join(target, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name) || entry.name.startsWith(".")) continue;
      if (!opts.includeTests && TEST_DIR.test(entry.name)) continue;
      walk(full, opts, out);
    } else if (entry.isFile()) {
      if (!STACK_BY_EXT[path.extname(entry.name).toLowerCase()]) continue;
      if (!opts.includeTests && TEST_FILE.test(entry.name)) continue;
      if (/\.(?:min|d)\.(?:js|ts)$/.test(entry.name)) continue;
      out.push(full);
    }
  }
  return out;
}

// A trailing comment silences its own line; a comment on a line of its own
// silences the next line.
function ignoredByComment(lines, line, ruleId) {
  const previous = lines[line - 2];
  const own = previous && /^\s*(?:\/\/|\/\*|\{\s*\/\*|\*|<!--|#)/.test(previous) ? previous : null;
  for (const l of [lines[line - 1], own]) {
    if (!l) continue;
    const m = /(?:unslop-anything|unslopovich)-ignore(?:\s+([\w-]+(?:\s*,\s*[\w-]+)*))?/.exec(l);
    if (m && (!m[1] || m[1].split(/\s*,\s*/).includes(ruleId))) return true;
  }
  return false;
}

function scanSource(text, file, options = {}) {
  const stack = options.stack || STACK_BY_EXT[path.extname(file).toLowerCase()];
  if (!stack) return [];
  if (stack === "xml" && !/<(?:LinearLayout|ConstraintLayout|TextView|FrameLayout|RelativeLayout|manifest|application|shape|gradient|resources|androidx\.)/.test(text)) return [];
  const code = blankComments(text, stack);
  const starts = lineStarts(text);
  const lines = text.split("\n");
  const ignoreRules = new Set(options.ignoreRules || []);
  const kind = options.kind || "unknown";
  const findings = [];
  for (const rule of rules) {
    if (ignoreRules.has(rule.id)) continue;
    if (rule.stacks && !rule.stacks.includes(stack)) continue;
    if (rule.platforms && kind !== "unknown" && !rule.platforms.includes(kind)) continue;
    const seen = new Set();
    for (const index of rule.find({ code, stack, file })) {
      const line = lineAt(starts, index);
      if (seen.has(line) || ignoredByComment(lines, line, rule.id)) continue;
      seen.add(line);
      findings.push({
        rule: rule.id,
        family: rule.family,
        severity: rule.severity,
        file,
        line,
        snippet: lines[line - 1].trim().slice(0, 120),
        message: rule.message,
        fix: rule.fix,
      });
    }
  }
  return findings;
}

function scan(targets, opts = {}) {
  const findings = [];
  const unreadable = [];
  let filesScanned = 0;
  for (const target of targets) {
    const root = path.resolve(target);
    const config = loadConfig(fs.statSync(root).isDirectory() ? root : path.dirname(root));
    const ignoreRules = [...config.ignoreRules, ...(opts.ignoreRules || [])];
    for (const file of walk(root, opts)) {
      const rel = path.relative(process.cwd(), file) || file;
      if (config.ignorePaths.some((p) => rel.split(path.sep).join("/").includes(p))) continue;
      let text;
      try {
        text = fs.readFileSync(file, "utf8");
      } catch {
        unreadable.push(rel);
        continue;
      }
      if (text.length > 1_000_000) continue;
      filesScanned++;
      const kind = opts.platform || projectKind(path.dirname(file));
      findings.push(...scanSource(text, rel, { ignoreRules, kind }));
    }
  }
  findings.sort((a, b) => SEVERITY_RANK[a.severity] - SEVERITY_RANK[b.severity] || a.file.localeCompare(b.file) || a.line - b.line);
  // A scan that read zero files is not a clean scan: a typo'd folder, an
  // Objective-C/Java-only folder, or the wrong subdirectory would otherwise
  // print a clean result and exit 0, reading as a pass in CI when nothing
  // was checked. Flag it the same way unreadable files make a scan incomplete.
  const message = filesScanned === 0
    ? `No supported source files under ${targets.length ? targets.join(", ") : "."} (${Object.keys(STACK_BY_EXT).join(", ")}). The scan checked nothing.`
    : undefined;
  return { version: VERSION, filesScanned, unreadable, findings, ...(message ? { message } : {}) };
}

// ---------- output ----------

function formatText(result) {
  const { findings, filesScanned } = result;
  const out = [];
  if (findings.length === 0) {
    out.push(filesScanned === 0 && result.message
      ? result.message
      : `Dr. Unslopovich found nothing in ${filesScanned} files. Suspicious, but fine.`);
  } else {
    const count = (s) => findings.filter((f) => f.severity === s).length;
    const files = new Set(findings.map((f) => f.file)).size;
    const parts = ["critical", "noticeable", "minor"].filter((s) => count(s)).map((s) => `${count(s)} ${s}`);
    out.push(`${findings.length} findings in ${files} of ${filesScanned} files (${parts.join(", ")})`);
    let current = null;
    for (const f of findings.slice().sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line)) {
      if (f.file !== current) {
        current = f.file;
        out.push("", f.file);
      }
      out.push(`  ${String(f.line).padStart(4)}  ${f.severity.padEnd(10)}  ${f.rule.padEnd(18)}  ${f.message}`);
    }
    out.push("", "Fixes: npx unslop-anything detect --list-rules");
  }
  out.push("Static checks only. Nothing was run, profiled, or tapped. A clean scan is not a clean bill of health.");
  return out.join("\n");
}

function listRules() {
  // A rule with no stacks or platforms restriction applies everywhere;
  // --list-rules shows that as "all" instead of hiding the field.
  const show = (v) => (v ? v.join(", ") : "all");
  return rules
    .map((r) => `${r.id.padEnd(18)}  ${r.severity.padEnd(10)}  ${r.family.padEnd(15)}  ${r.message}\n${" ".repeat(20)}Fix: ${r.fix}\n${" ".repeat(20)}Stacks: ${show(r.stacks)} | Platforms: ${show(r.platforms)}`)
    .join("\n");
}

function listRulesJson() {
  return JSON.stringify(rules.map((r) => ({
    id: r.id,
    severity: r.severity,
    family: r.family,
    message: r.message,
    fix: r.fix,
    stacks: r.stacks ? [...r.stacks] : "all",
    platforms: r.platforms ? [...r.platforms] : "all",
  })), null, 2);
}

const USAGE = `Usage: unslop-anything detect [paths...] [--json] [--platform mobile|web|universal] [--fail-on critical|noticeable|minor] [--ignore rule,rule] [--include-tests] [--list-rules]

Scans mobile and web source for generated-looking UI, website-in-a-phone patterns,
and accessibility and motion defaults. The platform comes from the nearest
package.json; --platform overrides it.
Exit code: 0 clean, 2 findings at or above --fail-on (default minor), 1 error.
Silence one line with a comment: unslop-anything-ignore <rule-id>
Project config: .unslop-anything/config.json  { "ignoreRules": [], "ignorePaths": [] }`;

function main(argv) {
  const args = argv.slice();
  if (args.includes("--help") || args.includes("-h")) {
    console.log(USAGE);
    return 0;
  }
  if (args.includes("--list-rules")) {
    console.log(args.includes("--json") ? listRulesJson() : listRules());
    return 0;
  }
  const json = args.includes("--json");
  const includeTests = args.includes("--include-tests");
  let platform = null;
  let failOn = "minor";
  const ignoreRules = [];
  const targets = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--platform") {
      platform = args[++i];
      if (platform === undefined) {
        console.error("Missing value for --platform. Choose from mobile, web, universal.");
        return 1;
      }
      if (!["mobile", "web", "universal"].includes(platform)) {
        console.error(`Unknown platform: ${platform}. Choose from mobile, web, universal.`);
        return 1;
      }
    } else if (a === "--fail-on") {
      failOn = args[++i];
      if (failOn === undefined) {
        console.error("Missing value for --fail-on. Choose from critical, noticeable, minor.");
        return 1;
      }
      if (!Object.prototype.hasOwnProperty.call(SEVERITY_RANK, failOn)) {
        console.error(`Unknown severity: ${failOn}. Choose from critical, noticeable, minor.`);
        return 1;
      }
    } else if (a === "--ignore") {
      const value = args[i + 1];
      if (!value || value.startsWith("--")) {
        console.error(
          "Missing value for --ignore. Pass rule ids separated by commas; see --list-rules."
        );
        return 1;
      }
      i++;
      ignoreRules.push(...value.split(","));
    } else if (!a.startsWith("--")) targets.push(a);
    else if (!["--json", "--include-tests"].includes(a)) {
      console.error(`Unknown option ${a}\n\n${USAGE}`);
      return 1;
    }
  }
  const unknown = unknownRuleIds(ignoreRules);
  if (unknown.length) {
    console.error(`Unknown rule: ${unknown.join(", ")}. See --list-rules.`);
    return 1;
  }
  let result;
  try {
    result = scan(targets.length ? targets : ["."], { includeTests, ignoreRules, platform });
  } catch (err) {
    console.error(err.message);
    return 1;
  }
  if (result.filesScanned === 0 && !json && !result.unreadable.length) {
    console.error(result.message);
    return 1;
  }
  console.log(json ? JSON.stringify(result, null, 2) : formatText(result));
  if (result.unreadable.length) {
    console.error(`Could not read ${result.unreadable.length} file(s): ${result.unreadable.join(", ")}. The scan is incomplete.`);
    return 1;
  }
  if (result.filesScanned === 0) {
    console.error(result.message);
    return 1;
  }
  // Findings below --fail-on are still printed; only findings at or above
  // the threshold fail the scan. SEVERITY_RANK orders critical (0) above
  // noticeable (1) above minor (2), so a finding fails when its rank is
  // at most the threshold's rank. Default minor keeps today's behavior.
  const failing = result.findings.some((f) => SEVERITY_RANK[f.severity] <= SEVERITY_RANK[failOn]);
  return failing ? 2 : 0;
}

module.exports = { rules, scan, scanSource, blankComments, isSlopHue, main };

if (require.main === module) process.exitCode = main(process.argv.slice(2));
