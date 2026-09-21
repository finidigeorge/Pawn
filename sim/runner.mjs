/**
 * Drives the wowsims-turtle web simulator with a Pawn character export.
 *
 * Usage:
 *   node runner.mjs --input import.json [--output weights.json]
 *                   [--iterations 1000] [--url <sim url>]
 *                   [--expect "Item Name"] [--headed]
 *
 * The script:
 *   1. opens the sim (spec page chosen by --url),
 *   2. un-disables the "Simulate" / "Stat Weights" buttons (the spec is
 *      marked "not supported" upstream, but the sim itself runs),
 *   3. imports the JSON character,
 *   4. runs the Stat Weights calculation,
 *   5. writes { meta, weights } JSON.
 */
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        out[key] = true;
      } else {
        out[key] = next;
        i++;
      }
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
if (!args.input) {
  console.error('usage: runner.mjs --input import.json [--output weights.json] [--iterations N] [--url URL] [--headed]');
  process.exit(2);
}

const inputPath = args.input;
const outputPath = args.output || path.join(path.dirname(inputPath), 'weights.json');
const iterations = Number(args.iterations || 1000);
const url = args.url || 'https://isfir.github.io/wowsims-turtle/enhancement_shaman/';
const headed = !!args.headed;
const importJson = fs.readFileSync(inputPath, 'utf8');

// Clicks the first button/link whose text matches (optionally inside a root element).
async function clickText(page, rootSel, text, opts = {}) {
  return page.evaluate(([rootSel, text, exact]) => {
    const root = rootSel ? document.querySelector(rootSel) : document;
    if (!root) return false;
    const candidates = [...root.querySelectorAll('button, a, [role="button"]')];
    const el = candidates.find((e) => {
      const t = (e.textContent || '').trim();
      return exact ? t === text : t.startsWith(text);
    });
    if (!el) return false;
    el.click();
    return true;
  }, [rootSel, text, !!opts.exact]);
}

// The upstream site disables Simulate/Stat Weights for specs that are not
// "launched". Re-enable them and keep them enabled against re-renders.
async function unlockButtons(page) {
  await page.evaluate(() => {
    const labels = ['Simulate', 'Stat Weights'];
    const fix = () => {
      for (const label of labels) {
        const b = [...document.querySelectorAll('button')].find((x) => (x.textContent || '').trim() === label);
        if (b && b.disabled) b.disabled = false;
      }
    };
    fix();
    if (!window.__pawnUnlockObserver) {
      window.__pawnUnlockObserver = new MutationObserver(fix);
      window.__pawnUnlockObserver.observe(document.body, { childList: true, subtree: true, attributes: true });
    }
  });
}

function launchCandidates() {
  const list = [];
  if (args.executable) list.push({ executablePath: String(args.executable) });
  if (process.env.PW_CHANNEL) list.push({ channel: process.env.PW_CHANNEL });
  const common = [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  ];
  for (const exe of common) {
    if (fs.existsSync(exe)) list.push({ executablePath: exe });
  }
  list.push({ channel: 'chrome' }, { channel: 'msedge' }, {});
  return list;
}

let browser = null;
let launchError = null;
for (const opts of launchCandidates()) {
  try {
    browser = await chromium.launch({ headless: !headed, ...opts });
    console.error('[runner] launched browser with', JSON.stringify(opts));
    break;
  } catch (err) {
    launchError = err;
  }
}
if (!browser) throw launchError || new Error('could not launch a browser');
const context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
const page = await context.newPage();
page.on('console', (m) => {
  const t = m.text();
  if (/error|failed|exception/i.test(t)) console.error('[sim console]', t.slice(0, 300));
});

try {
  console.error('[runner] opening', url);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForSelector('text=Simulate', { timeout: 60000 });
  await unlockButtons(page);

  // Iterations
  await page.evaluate((n) => {
    const inp = [...document.querySelectorAll('input')].find((i) => (i.getAttribute('aria-label') || '') === 'Iterations');
    if (inp) {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      setter.call(inp, String(n));
      inp.dispatchEvent(new Event('input', { bubbles: true }));
      inp.blur();
    }
  }, iterations);

  // Import -> JSON
  if (!(await clickText(page, null, 'Import'))) throw new Error('Import button not found');
  await page.waitForSelector('.dropdown-menu.show', { timeout: 10000 });
  if (!(await clickText(page, '.dropdown-menu.show', 'JSON', { exact: true }))) throw new Error('Import -> JSON menu item not found');
  await page.waitForSelector('.modal.show textarea', { timeout: 10000 });
  await page.evaluate((val) => {
    const ta = document.querySelector('.modal.show textarea');
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
    setter.call(ta, val);
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  }, importJson);

  const confirmLabel = await page.evaluate(() => {
    const modal = document.querySelector('.modal.show');
    if (!modal) return null;
    const buttons = [...modal.querySelectorAll('button')].filter((b) => !b.disabled);
    for (const wanted of ['import', 'load', 'apply', 'ok', 'confirm', 'save']) {
      const b = buttons.find((x) => (x.textContent || '').trim().toLowerCase() === wanted);
      if (b) {
        b.click();
        return (b.textContent || '').trim();
      }
    }
    const footer = modal.querySelector('.modal-footer button');
    if (footer) {
      footer.click();
      return '(footer) ' + (footer.textContent || '').trim();
    }
    return null;
  });
  console.error('[runner] import confirm:', confirmLabel);
  await page.waitForFunction(() => !document.querySelector('.modal.show'), null, { timeout: 15000 }).catch(() => {});

  if (args.expect) {
    const found = await page.evaluate((name) => document.body.innerText.includes(name), String(args.expect));
    if (!found) throw new Error(`import verification failed: "${args.expect}" not found on the page after import`);
    console.error('[runner] verified imported item:', args.expect);
  }

  // Close any leftover modal from the import flow (the site stacks modals).
  for (let i = 0; i < 3; i++) {
    const open = await page.evaluate(() => !!document.querySelector('.modal.show'));
    if (!open) break;
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => !document.querySelector('.modal.show'), null, { timeout: 5000 }).catch(() => {});
  }

  // Stat Weights -> Calculate (always operate on the stat weights modal itself).
  await unlockButtons(page);
  if (!(await clickText(page, null, 'Stat Weights'))) throw new Error('Stat Weights button not found');
  await page.waitForFunction(() => {
    const modals = [...document.querySelectorAll('.modal.show')];
    return modals.some((m) => m.innerText.includes('Calculate Stat Weights'));
  }, null, { timeout: 20000 });

  // Prefer the "EP" mode (relative to the reference stat, usually AP).
  await page.evaluate(() => {
    const modals = [...document.querySelectorAll('.modal.show')];
    const modal = modals.find((m) => m.innerText.includes('Calculate Stat Weights'));
    if (!modal) return;
    const select = modal.querySelector('select');
    if (!select) return;
    const option = [...select.options].find((o) => o.value === 'EP' || (o.textContent || '').trim() === 'EP');
    if (!option) return;
    const setter = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set;
    setter.call(select, option.value);
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });

  const calculateClicked = await page.evaluate(() => {
    const modals = [...document.querySelectorAll('.modal.show')];
    const modal = modals.find((m) => m.innerText.includes('Calculate Stat Weights')) || modals[modals.length - 1];
    if (!modal) return false;
    const b = [...modal.querySelectorAll('button, a, [role="button"]')].find((x) => (x.textContent || '').trim() === 'Calculate');
    if (!b) return false;
    b.click();
    return true;
  });
  if (!calculateClicked) throw new Error('Calculate button not found');

  const timeoutMs = Number(args.timeout || 600000);
  console.error('[runner] calculating stat weights (this can take a few minutes)...');
  await page.waitForFunction(() => {
    const modals = [...document.querySelectorAll('.modal.show')];
    const modal = modals.find((m) => m.innerText.includes('Calculate Stat Weights'));
    if (!modal || /\bN\/A\b/.test(modal.innerText)) return false;
    let rows = 0;
    for (const tr of modal.querySelectorAll('tr')) {
      const cells = [...tr.querySelectorAll('td')];
      if (cells.length < 2) continue;
      if (!/^[A-Za-z]/.test(cells[0].innerText.trim())) continue;
      if (!Number.isNaN(parseFloat(cells[1].innerText.replace(/[^0-9.+-]/g, '')))) rows++;
    }
    return rows >= 5;
  }, null, { timeout: timeoutMs });

  const weights = await page.evaluate(() => {
    const modals = [...document.querySelectorAll('.modal.show')];
    const modal = modals.find((m) => m.innerText.includes('Calculate Stat Weights')) || modals[modals.length - 1];
    const out = {};
    if (!modal) return out;
    for (const tr of modal.querySelectorAll('tr')) {
      const cells = [...tr.querySelectorAll('td')].map((td) => td.innerText.trim());
      if (cells.length < 2) continue;
      if (!/^[A-Za-z]/.test(cells[0])) continue;
      const value = parseFloat(cells[1].replace(/[^0-9.+-]/g, ''));
      if (!Number.isNaN(value)) out[cells[0]] = value;
    }
    return out;
  });

  if (Object.keys(weights).length === 0) throw new Error('no weights parsed from the Stat Weights table');

  // Normalize to EP relative to a reference stat (= 1.0), regardless of the
  // mode the modal happened to be in. Physical specs anchor on Attack Power,
  // casters on Spell Power; fall back to the first positive weight.
  const anchorNames = ['Attack Power', 'Spell Power', 'Main Hand DPS'];
  let anchorName = anchorNames.find((n) => typeof weights[n] === 'number' && weights[n] > 0);
  if (!anchorName) anchorName = Object.keys(weights).find((k) => typeof weights[k] === 'number' && weights[k] > 0);
  const anchor = anchorName ? weights[anchorName] : null;
  if (anchor && anchor > 0) {
    for (const key of Object.keys(weights)) weights[key] = weights[key] / anchor;
    console.error('[runner] normalized to ' + anchorName + ' = 1.0 EP (raw weight ' + anchor + ')');
  } else {
    console.error('[runner] WARNING: could not normalize weights (no positive anchor)');
  }

  fs.writeFileSync(outputPath, JSON.stringify({
    meta: {
      url,
      iterations,
      at: new Date().toISOString(),
      importConfirm: confirmLabel,
    },
    weights,
  }, null, 2));
  console.error('[runner] wrote', outputPath);
} finally {
  await browser.close();
}
