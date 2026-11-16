#!/usr/bin/env node
/**
 * Demo exerciser: boots every machine on the Demos page (demos/README.md) in headless Chrome
 * and checks that each one starts BASIC-DOS, runs its demo programs, and answers a command on
 * every console (keyboard and serial ports).
 *
 * usage: tools/tests/demos.js [options] [filter ...]
 *
 *      filter          run only the demos whose path contains a filter (eg, dual mmu/vt100 /386/)
 *      --url=URL       site to test (default: http://localhost:4040, the local Jekyll server)
 *      --jobs=N        machines to run at once (default: 4)
 *      --timeout=N     seconds to wait for each machine's demo to appear (default: 180)
 *      --dump          print each machine's screen and serial port text, pass or fail
 *      --list          list the demos and exit
 *
 * The exit code is non-zero if any demo failed.
 *
 * This needs Node 22 or later (for WebSocket), Google Chrome (set CHROME to its path if it
 * isn't in the usual place), and a developer server, because it relies on the uncompiled
 * PCx86 scripts' globals (eg, Component).  The demo list comes from the table's links, so a
 * new row is run automatically; what a demo should display is in the DEMOS table below.
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const HELLO = /L O V E/, FIBO = /832040/, PRIMES = /TOTAL PRIMES < 1000: +168/;
const PIPES = /DIRECTORY OF A:/, PROMPT = /[A-C]:\\[^ ]*[>\]}]/;

/**
 * What each demo should do, by path (less any pc/, xt/, at/, or 386/); each value is a
 * function of that hardware name, returning:
 *
 *      screen      patterns that must appear in video memory (default: a prompt)
 *      com         serial ports with consoles, which must show a prompt and answer a command
 *      debug       serial port with the BASIC-DOS debugger, which must show its banner
 *      keys        false if the keyboard's console isn't at a prompt (or there's no keyboard console)
 *      cycle       true to press SHIFT-TAB while waiting (for consoles that share one video page)
 *      graphics    true if the demo goes from a prompt to a graphics mode
 *      pm          true if the demo runs in protected mode (and with paging, on the 386)
 */
const DEMOS = {
    'm64':          () => ({}),
    'term':         (hw) => ({ screen: [], keys: false, com: hw == 'at' ? [1, 2] : [1] }),
    's80':          () => ({ screen: [HELLO] }),
    'd40':          () => ({ screen: [HELLO, PIPES] }),
    'd80':          () => ({ screen: [/>[^>]*>/] }),
    'p80':          (hw) => ({ screen: [HELLO, FIBO, PRIMES], cycle: hw == 'pc' }),
    'dual':         (hw) => ({ screen: [PRIMES, hw == 'pc' ? PIPES : /Maintenance Utility/] }),
    'dual/multi':   () => ({ screen: [HELLO, FIBO, PRIMES, PIPES] }),
    'mouse':        () => ({ screen: [], keys: false, graphics: true }),
    'debug':        () => ({ debug: 2 }),
    'serial':       () => ({ screen: [HELLO], com: [1] }),
    'parallel':     () => ({}),
    'hd':           () => ({ screen: [HELLO] }),
    'vt100':        () => ({ screen: [HELLO], com: [1] }),
    'wolf3d':       () => ({ screen: [], keys: false, graphics: true }),
    'mmu/640k':     () => ({ screen: [HELLO, FIBO, PRIMES], pm: true }),
    'mmu':          () => ({ screen: [HELLO, FIBO, PRIMES], pm: true }),
    'mmu/vt100':    () => ({ screen: [HELLO, FIBO, PRIMES], pm: true, debug: 2 })
};

/**
 * The command typed on every console, and the answer it should display (the command has
 * no shifted characters, which are the ones most likely to be mistyped by key injection).
 */
const COMMAND = 'print 61000-4912\r', ANSWER = /56088/;

/**
 * Runs in each page: records what the PC sends to its serial ports, and provides the
 * functions used to read and drive the machine.
 */
const HOOKS = `(() => {
    const dx = window.__dx = { com: {}, prompted: false };
    const isText = (m) => m <= 3 || m == 7;
    const all = (t) => (typeof Component == 'undefined'? [] : Component.getComponents().filter((c) => c.type == t));
    setInterval(() => {
        for (const s of all('SerialPort')) {
            if (s.__dx) continue;
            s.__dx = true;
            const n = s.iAdapter, f = s.transmitByte;
            dx.com[n] = '';
            s.transmitByte = function(b) {
                dx.com[n] = (dx.com[n] + String.fromCharCode(b & 0x7f)).slice(-65536);
                return f.call(this, b);
            };
        }
        //
        // Note the first prompt in a text mode here, since a demo that then starts a
        // graphics program may not show it for long.
        //
        const cpu = all('CPU')[0];
        if (cpu && !dx.prompted && all('Video').every((v) => isText(v.nMode))) {
            dx.prompted = ${PROMPT}.test(text(cpu.bus, 0xB0000, 4000) + text(cpu.bus, 0xB8000, 4000));
        }
    }, 50);
    const text = (bus, addr, len) => {
        let s = '';
        for (let i = 0; i < len; i += 2) {
            let b = 0;
            try { b = bus.getByteDirect(addr + i); } catch (e) {}
            s += (b >= 32 && b < 127)? String.fromCharCode(b) : ' ';
        }
        return s;
    };
    dx.state = () => {
        const cpu = all('CPU')[0], kbd = all('Keyboard')[0];
        if (!cpu) return null;
        return {
            cycles: cpu.getCycles(), running: cpu.isRunning(), cr0: cpu.regCR0 >>> 0,
            graphics: dx.prompted && all('Video').some((v) => !isText(v.nMode)),
            typing: kbd? (kbd.sInjectBuffer || '').length : 0,
            screen: text(cpu.bus, 0xB0000, 4000) + text(cpu.bus, 0xB8000, 0x8000),
            com: dx.com
        };
    };
    dx.type = (s) => all('Keyboard')[0].injectKeys(s, 60);
    dx.send = (n, s) => all('SerialPort').filter((c) => c.iAdapter == n)[0].receiveData(s);
    dx.shiftTab = () => { for (const b of [0x2a, 0x0f, 0x8f, 0xaa]) all('Keyboard')[0].addScanCode(b); };
})();`;

const opts = { url: 'http://localhost:4040', jobs: 4, timeout: 180 }, filters = [];
for (const arg of process.argv.slice(2)) {
    const m = arg.match(/^--(\w+)(?:=(.*))?$/);
    if (!m) filters.push(arg);
    else opts[m[1]] = m[2] === undefined? true : (isNaN(m[2])? m[2] : +m[2]);
}
const chromePath = process.env.CHROME || [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'
].find(existsSync);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const children = new Set();

/**
 * getDemos()
 *
 * @returns {Array} the demo table's links, as { path, key, hw }
 */
function getDemos()
{
    const demos = [];
    for (const line of readFileSync(join(root, 'demos', 'README.md'), 'utf8').split('\n')) {
        if (line[0] != '|') continue;
        for (const m of line.matchAll(/\]\(([^)]+\/)\)/g)) {
            const parts = m[1].match(/^(.*?)\/?(pc|xt|at|386)?\/$/);
            demos.push({ path: m[1], key: parts[1], hw: parts[2] || '' });
        }
    }
    //
    // The VT100 Terminal demo's pages without the AVO aren't in the table (each page links to its own).
    //
    for (const hw of ['xt', 'at', '386']) demos.push({ path: `vt100/${hw}/noavo/`, key: 'vt100', hw });
    return demos;
}

/**
 * openPage(url)
 *
 * Starts a headless Chrome of our own (with its own profile) on the page.
 *
 * @returns {Object} { evaluate(expr), problems, close() }
 */
async function openPage(url)
{
    const profile = mkdtempSync(join(tmpdir(), 'demos-'));
    const chrome = spawn(chromePath, [
        '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
        '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
        '--disable-backgrounding-occluded-windows', '--window-size=1600,1200', 'about:blank'
    ], { stdio: 'ignore' });
    children.add(chrome);
    const close = () => {
        chrome.kill('SIGKILL');
        children.delete(chrome);
        try { rmSync(profile, { recursive: true, force: true, maxRetries: 5 }); } catch (e) { /* Chrome may still be exiting */ }
    };
    try {
        let target;
        for (let i = 0; i < 100 && !target; i++) {
            await sleep(100);
            try {
                const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
                const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
                target = list.find((t) => t.type == 'page');
            } catch (e) { /* not up yet */ }
        }
        if (!target) throw new Error('Chrome did not start');
        const ws = new WebSocket(target.webSocketDebuggerUrl);
        await new Promise((resolve, reject) => {
            ws.addEventListener('open', resolve);
            ws.addEventListener('error', reject);
        });
        let id = 0;
        const pending = new Map(), problems = [];
        const send = (method, params = {}) => new Promise((resolve) => {
            pending.set(++id, resolve);
            ws.send(JSON.stringify({ id, method, params }));
        });
        ws.addEventListener('message', (ev) => {
            const msg = JSON.parse(ev.data);
            if (msg.id && pending.has(msg.id)) {
                pending.get(msg.id)(msg);
                pending.delete(msg.id);
            } else if (msg.method == 'Page.javascriptDialogOpening') {
                problems.push('alert: ' + msg.params.message);
                send('Page.handleJavaScriptDialog', { accept: true });
            } else if (msg.method == 'Runtime.exceptionThrown') {
                const d = msg.params.exceptionDetails;
                problems.push('exception: ' + (d.exception?.description || d.text).split('\n')[0]);
            }
        });
        await send('Runtime.enable');
        await send('Page.enable');
        await send('Network.enable');
        await send('Network.setCacheDisabled', { cacheDisabled: true });
        await send('Page.addScriptToEvaluateOnNewDocument', { source: HOOKS });
        await send('Page.navigate', { url });
        const evaluate = async (expr) => {
            const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
            return r.result?.exceptionDetails? undefined : r.result?.result?.value;
        };
        return { evaluate, problems, close: () => { ws.close(); close(); } };
    } catch (e) {
        close();
        throw e;
    }
}

/**
 * runDemo(demo)
 *
 * @returns {Object} { failures, seconds, state }
 */
async function runDemo(demo)
{
    const spec = DEMOS[demo.key]?.(demo.hw);
    if (!spec) return { failures: [`no entry for "${demo.key}" in the DEMOS table`], seconds: 0 };
    const start = Date.now(), failures = [];
    const page = await openPage(`${opts.url}/demos/${demo.path}`);
    let state = null;
    const strip = (s) => (s || '').replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');
    const getState = async () => {
        const s = await page.evaluate('window.__dx && __dx.state()');
        if (s) {
            for (const n in s.com) s.com[n] = strip(s.com[n]);
            state = s;
        }
        return s;
    };
    /**
     * Wait until every check passes (once it has, it stays passed); returns those that didn't.
     */
    const waitFor = async (checks, seconds, tick) => {
        let left = checks;
        for (let i = 0; i < seconds && left.length; i++) {
            await sleep(1000);
            const s = await getState();
            if (!s) continue;
            left = left.filter((c) => !c.test(s));
            if (left.length && tick) await tick(i, s);
        }
        return left.map((c) => c.name);
    };
    try {
        const keys = spec.keys !== false;
        const checks = (spec.screen || []).map((re) => ({ name: `screen ${re}`, test: (s) => re.test(s.screen) }));
        if (keys) checks.push({ name: 'screen prompt', test: (s) => PROMPT.test(s.screen) && !s.typing });
        for (const n of spec.com || []) {
            checks.push({ name: `COM${n} prompt`, test: (s) => PROMPT.test(s.com[n]) });
        }
        if (spec.debug) {
            checks.push({ name: `COM${spec.debug} debugger`, test: (s) => /BASIC-DOS Debugger/.test(s.com[spec.debug]) });
        }
        if (spec.graphics) {
            checks.push({ name: 'graphics mode', test: (s) => s.graphics });
        }
        if (spec.pm) {
            const bits = demo.hw == '386'? 0x80000001 : 1;
            checks.push({ name: 'protected mode', test: (s) => (s.cr0 & bits) >>> 0 == bits });
        }
        const tick = spec.cycle && (async (i) => { if (i % 10 == 9) await page.evaluate('__dx.shiftTab()'); });
        const missing = await waitFor(checks, opts.timeout, tick);
        if (!state) {
            failures.push('the machine never loaded');
        } else if (missing.length) {
            failures.push('missing ' + missing.join(', '));
        } else {
            if (keys) {
                await page.evaluate(`__dx.type(${JSON.stringify(COMMAND)})`);
                if ((await waitFor([{ test: (s) => ANSWER.test(s.screen) }], 45)).length) {
                    failures.push('no answer to a command typed on the keyboard');
                }
            }
            for (const n of spec.com || []) {
                await page.evaluate(`__dx.send(${n}, ${JSON.stringify(COMMAND)})`);
                if ((await waitFor([{ test: (s) => ANSWER.test(s.com[n]) }], 45)).length) {
                    failures.push(`no answer to a command sent to COM${n}`);
                }
            }
            const cycles = state.cycles;
            await sleep(1000);
            await getState();
            if (!state.running || state.cycles == cycles) failures.push('the machine stopped');
        }
        failures.push(...new Set(page.problems));
    } finally {
        page.close();
    }
    return { failures, seconds: Math.round((Date.now() - start) / 1000), state };
}

/**
 * dump(state)
 *
 * Prints the non-blank rows of video memory (as 80-column rows) and each serial port's text.
 */
function dump(state)
{
    if (!state) return;
    const show = (name, text) => (text.match(/.{80}/g) || []).forEach((row, i) => {
        if (row.trim()) console.log(`      ${name} ${String(i).padStart(3)}  ${row.trimEnd()}`);
    });
    const color = state.screen.slice(2000), half = color.length / 2;
    show('B000', state.screen.slice(0, 2000));
    show('B800', color.slice(half) == color.slice(0, half)? color.slice(0, half) : color);  // (a CGA's 16K repeats)
    for (const n in state.com) {
        if (state.com[n].trim()) console.log(`      COM${n}: ${JSON.stringify(state.com[n].slice(-600))}`);
    }
}

const demos = getDemos().filter((d) => !filters.length || filters.some((f) => ('/' + d.path).includes(f)));
if (opts.list) {
    demos.forEach((d) => console.log(d.path));
    process.exit(0);
}
if (!chromePath) {
    console.error('Google Chrome not found; set CHROME to its path');
    process.exit(2);
}
try {
    if (!(await fetch(`${opts.url}/demos/`)).ok) throw new Error();
} catch (e) {
    console.error(`${opts.url}/demos/ isn't responding; start the Jekyll server first`);
    process.exit(2);
}
for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, () => {
        children.forEach((c) => c.kill('SIGKILL'));
        process.exit(130);
    });
}

let next = 0, failed = 0;
await Promise.all(Array.from({ length: Math.min(opts.jobs, demos.length) }, async () => {
    while (next < demos.length) {
        const demo = demos[next++];
        let result;
        try {
            result = await runDemo(demo);
        } catch (e) {
            result = { failures: [e.message], seconds: 0 };
        }
        const ok = !result.failures.length;
        if (!ok) failed++;
        console.log(`${ok? 'PASS' : 'FAIL'}  ${demo.path.padEnd(20)} ${String(result.seconds).padStart(4)}s`);
        result.failures.forEach((f) => console.log(`      ${f}`));
        if (!ok || opts.dump) dump(result.state);
    }
}));
console.log(`\n${demos.length - failed} of ${demos.length} demos passed`);
process.exit(failed? 1 : 0);
