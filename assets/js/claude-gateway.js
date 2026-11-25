/**
 * @fileoverview Claude gateway for CLAUDE.BAS, shared by tools/claude/gateway.js (Node) and the demo pages
 * @copyright © 2026 Jeff Parsons
 * @license MIT <https://www.pcjs.org/LICENSE.txt>
 *
 * A Gateway answers the questions that CLAUDE.BAS sends through a serial port (COM2).  The serial port's bytes
 * go to receive(), and the replies go to the send() function given to the constructor.  In Node, those are
 * stdin and stdout (see tools/claude/gateway.js); on a demo page, connectPage() binds the machine's COM2.
 *
 * Protocol (all control bytes are ASCII control codes that never appear in text):
 *
 *      PC -> gateway:  ENQ             end any answer in progress, and reply ACK
 *                      text... EOT     a question: a parameter line (the console's columns,
 *                                      and NEW to start a new conversation), CR, and the question
 *                      ACK             send the next chunk
 *
 *      gateway -> PC:  ACK             reply to ENQ
 *                      text... ETB     a chunk of the answer (at most CHUNK bytes); wait for ACK
 *                      text... EOT     the last chunk
 *                      NAK             (anywhere in a chunk) the rest of the answer is an error message
 *
 * Answers are converted to code page 437, with CR LF line endings, and wrapped to the console's
 * width.  Chunks keep the PC's serial input buffer (128 bytes by default) from overflowing, since
 * its driver drops bytes when the buffer is full.  The gateway never sends CTRL-C, CTRL-Q, or
 * CTRL-S, which the COM driver handles itself, and the only other control codes it sends are
 * CR, LF, and the ones above.
 */

const EOT = 0x04, ENQ = 0x05, ACK = 0x06, LF = 0x0A, CR = 0x0D, NAK = 0x15, ETB = 0x17;
const CHUNK = 100;              // maximum text bytes per chunk
const MAXREQUEST = 1 << 20;     // maximum question bytes (anything more is ignored)

export const MODEL = "claude-opus-5-5";
export const EFFORT = "low";

/**
 * The characters of code page 437 from 80h through FFh (00h-1Fh are control codes here, not glyphs).
 */
const CP437 = "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ";

/**
 * Characters that code page 437 lacks, and their replacements; anything else that's missing
 * is decomposed (eg, an accented letter becomes the plain letter) or becomes "?".
 */
const SUBST = {
    " ": " ", " ": " ", " ": " ", " ": " ", "​": "",
    "‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "--", "―": "--", "−": "-",
    "‘": "'", "’": "'", "‚": "'", "‛": "'", "′": "'",
    "“": "\"", "”": "\"", "„": "\"", "″": "\"",
    "…": "...", "•": "*", "‣": "*", "⁃": "-", "×": "x",
    "←": "<-", "→": "->", "↔": "<->", "⇒": "=>", "≠": "!=", "©": "(c)",
    "™": "(TM)", "®": "(R)", "✓": "v", "✔": "v", "✗": "x", "✘": "x"
};

/**
 * toBytes(ch)
 *
 * @param {string} ch (one character)
 * @returns {Array.<number>} (CP437 bytes)
 */
function toBytes(ch)
{
    let c = ch.codePointAt(0);
    if (c >= 0x20 && c < 0x7F) return [c];
    let s = SUBST[ch];
    if (s == undefined) {
        let i = CP437.indexOf(ch);
        if (i >= 0) return [0x80 + i];
        s = ch.normalize("NFKD").replace(/[^\x20-\x7E]/g, "") || "?";
    }
    return Array.from(s, (t) => t.charCodeAt(0));
}

/**
 * fromBytes(bytes)
 *
 * @param {Array.<number>} bytes (CP437)
 * @returns {string}
 */
function fromBytes(bytes)
{
    return bytes.map((b) => b < 0x80? String.fromCharCode(b) : CP437[b - 0x80]).join("");
}

/**
 * Formatter converts text to CP437 lines that fit the console, adding the bytes to an output array.
 *
 * Lines are wrapped one column short of the console's width, because a console that wraps after
 * its last column would turn a full line plus CR LF into an extra blank line.  Spaces at a wrap
 * are dropped, but spaces at the start of a line (eg, indented code) are kept.
 */
class Formatter {

    constructor(output, cols)
    {
        this.output = output;
        this.width = Math.max(cols - 1, 19);
        this.col = 0;
        this.spaces = 0;
        this.word = [];
    }

    write(text)
    {
        for (let ch of text) {
            if (ch == "\n") {
                this.flushWord();
                this.newLine();
            } else if (ch == " " || ch == "\t") {
                this.flushWord();
                this.spaces += (ch == "\t"? 8 - (this.col + this.spaces) % 8 : 1);
            } else if (ch != "\r") {
                this.word.push(...toBytes(ch));
                if (this.word.length >= this.width) this.flushWord();
            }
        }
    }

    flushWord()
    {
        if (this.word.length) {
            if (this.col + this.spaces + this.word.length > this.width) {
                this.newLine();
            }
            this.col += this.spaces + this.word.length;
            for (; this.spaces; this.spaces--) this.output.push(0x20);
            this.output.push(...this.word);
            this.word = [];
        }
    }

    newLine()
    {
        this.output.push(CR, LF);
        this.col = this.spaces = 0;
    }

    /**
     * end()
     *
     * Ends any partial line, so that the console's cursor ends up in the first column.
     */
    end()
    {
        this.flushWord();
        if (this.col) this.newLine();
    }
}

/**
 * systemPrompt(help)
 *
 * Returns the system prompt: a description of BASIC-DOS and the console, followed by HELP.TXT (if any) as a
 * reference, with a cache breakpoint, since it's the same for every question.
 *
 * @param {string} [help] (the contents of HELP.TXT)
 * @returns {Array.<Object>}
 */
export function systemPrompt(help)
{
    let system = [{
        type: "text",
        text: "You are Claude, answering questions typed at the command prompt of BASIC-DOS, an operating system " +
            "for the IBM PC whose command shell (COMMAND.COM) runs DOS commands, BASIC statements, and BASIC programs " +
            "(BAS and BAT files) at the same prompt.  The user may be on an original IBM PC, PC XT, or PC AT, or one " +
            "emulated by PCjs, with as little as 64K of memory.\n\n" +
            "Your answer is displayed on a text console (often 80 columns, sometimes 40) that shows only plain text in " +
            "code page 437, and the lines are wrapped for you, so:\n" +
            "- write plain text, with no Markdown (no #, *, `, or tables) and no emoji\n" +
            "- keep answers brief: a few short paragraphs at most, unless the user asks for more\n" +
            "- put each command or program line on a line of its own, indented with 2 spaces, and keep them short\n" +
            "- when you show a BASIC program, use the BASIC-DOS dialect described below, not GW-BASIC's, where they differ"
    }];
    if (help) {
        system.push({
            type: "text",
            text: "The following is HELP.TXT, the text that BASIC-DOS's HELP command displays: an entry for every " +
                "command, statement, and function, beginning with its syntax.  A bracketed tag starts each entry " +
                "([b] BASIC statement, [c] internal command, [e] external command, [f] function, and + for a feature " +
                "that may be unavailable on low memory systems), *word* marks a placeholder, and ~ stands for the " +
                "switch character (normally /).\n\n<help>\n" + help + "\n</help>",
            cache_control: {type: "ephemeral"}
        });
    }
    return system;
}

/**
 * GatewayError is an error whose message is displayed as is (eg, "No API key was entered").
 */
export class GatewayError extends Error {}

/**
 * @class Gateway
 */
export class Gateway {

    /**
     * constructor(options)
     *
     * @param {Object} options
     * @param {function(Array.<number>)} options.send (sends bytes to the PC)
     * @param {function():Promise<Object>} options.getClient (returns an Anthropic client, or throws a GatewayError)
     * @param {Array.<Object>|function():Promise<Array.<Object>>} [options.system] (the system prompt, or a function that returns it)
     * @param {function()} [options.onKeyError] (called when the API rejects the client's key)
     * @param {function(string)} [options.log]
     * @param {string} [options.model]
     * @param {string} [options.effort]
     * @param {boolean} [options.echo] (answer every question with the question itself, for testing)
     */
    constructor(options)
    {
        this.options = options;
        this.model = options.model || MODEL;
        this.effort = options.effort || EFFORT;
        this.log = options.log || function() {};
        this.history = [];              // the conversation (MessageParam objects)
        this.request = [];              // question bytes received so far
        this.output = [];               // answer bytes not sent yet
        this.waiting = false;           // true while a chunk awaits the PC's ACK
        this.answering = null;          // AbortController of the answer in progress, if any
        this.finished = false;          // true when the answer in progress has been generated
    }

    /**
     * receive(data)
     *
     * @this {Gateway}
     * @param {Iterable.<number>} data (bytes from the PC)
     */
    receive(data)
    {
        for (let b of data) {
            if (b == ENQ) {
                this.stop();
                this.request = [];
                this.options.send([ACK]);
            } else if (b == ACK) {
                if (this.waiting) {
                    this.waiting = false;
                    this.pump();
                }
            } else if (b == EOT) {
                if (!this.answering) {
                    let text = fromBytes(this.request).replace(/\r\n?/g, "\n");
                    let i = text.indexOf("\n");
                    if (i < 0) i = text.length;
                    this.ask(text.slice(0, i), text.slice(i + 1));
                }
                this.request = [];
            } else if (b != LF && this.request.length < MAXREQUEST) {
                this.request.push(b);
            }
        }
    }

    /**
     * pump()
     *
     * Sends the next chunk of the answer, unless the previous chunk hasn't been acknowledged, or there's
     * nothing to send yet.
     *
     * @this {Gateway}
     */
    pump()
    {
        if (!this.answering || this.waiting || !this.output.length && !this.finished) return;
        let chunk = this.output.splice(0, CHUNK);
        if (this.finished && !this.output.length) {
            chunk.push(EOT);
            this.answering = null;
        } else {
            chunk.push(ETB);
            this.waiting = true;
        }
        this.options.send(chunk);
    }

    /**
     * stop()
     *
     * Ends any answer in progress (and removes its question from the conversation).
     *
     * @this {Gateway}
     */
    stop()
    {
        if (this.answering) {
            this.answering.abort();
            if (this.answering.length != undefined) this.history.length = this.answering.length;
            this.answering = null;
        }
        this.output = [];
        this.waiting = this.finished = false;
    }

    /**
     * fail(formatter, message)
     *
     * Ends the answer with an error message.
     *
     * @this {Gateway}
     * @param {Formatter} formatter
     * @param {string} message
     */
    fail(formatter, message)
    {
        this.log("error: " + message);
        formatter.end();
        this.output.push(NAK);
        formatter.write(message);
        formatter.end();
    }

    /**
     * ask(params, question)
     *
     * @this {Gateway}
     * @param {string} params (the parameter line: the console's columns, and NEW for a new conversation)
     * @param {string} question
     */
    async ask(params, question)
    {
        let cols = 80;
        for (let word of params.trim().toUpperCase().split(/\s+/)) {
            if (word == "NEW") {
                this.history = [];
            } else if (+word >= 20 && +word <= 255) {
                cols = +word;
            }
        }
        let controller = new AbortController();
        let formatter = new Formatter(this.output, cols);
        this.answering = controller;
        this.finished = false;
        this.log("question: " + question);
        if (!question.trim()) {
            this.finished = true;
            this.pump();
            return;
        }
        if (this.options.echo) {
            for (let word of question.match(/\s*\S+/g)) {
                await new Promise((resolve) => setTimeout(resolve, 20));
                if (this.answering != controller) return;
                formatter.write(word);
                this.pump();
            }
            formatter.end();
            this.finished = true;
            this.pump();
            return;
        }
        /**
         * If stop() ends this answer, it removes the question from the conversation (see controller.length),
         * since another question may follow before the code below notices.
         */
        let length = controller.length = this.history.length;
        this.history.push({role: "user", content: question});
        let client = null;
        try {
            client = await this.options.getClient();
            if (this.answering != controller) return;
            let system = this.options.system;
            if (typeof system == "function") system = await system();
            if (this.answering != controller) return;
            let stream = client.beta.messages.stream({
                model: this.model,
                max_tokens: 64000,
                betas: ["server-side-fallback-2026-07-01"],
                fallbacks: "default",
                output_config: {effort: this.effort},
                system,
                messages: this.history
            }, {signal: controller.signal});
            stream.on("text", (text) => {
                if (this.answering == controller) {
                    formatter.write(text);
                    this.pump();
                }
            });
            let message = await stream.finalMessage();
            if (this.answering != controller) return;
            if (message.stop_reason == "refusal") {
                this.history.length = length;
                this.fail(formatter, "Claude declined to answer that.");
            } else {
                this.history.push({role: "assistant", content: message.content});
                if (message.stop_reason == "max_tokens") this.fail(formatter, "The answer was too long, so it was cut off.");
                formatter.end();
            }
            let usage = message.usage;
            this.log(`answer: ${message.stop_reason}, ${usage.input_tokens} input tokens (${usage.cache_read_input_tokens || 0} cached), ${usage.output_tokens} output tokens`);
        } catch (err) {
            if (this.answering != controller) return;
            this.history.length = length;
            let Anthropic = client && client.constructor;
            let message;
            if (err instanceof GatewayError) {
                message = err.message;
            } else if (Anthropic && err instanceof Anthropic.AuthenticationError) {
                message = "The API key is invalid.";
                if (this.options.onKeyError) this.options.onKeyError();
            } else if (Anthropic && err instanceof Anthropic.RateLimitError) {
                message = "Claude is busy; try again later.";
            } else if (Anthropic && err instanceof Anthropic.APIConnectionError) {
                message = "Unable to reach the Claude API.";
            } else if (Anthropic && err instanceof Anthropic.APIError && err.status) {
                message = `Claude API error ${err.status}: ${err.error?.error?.message || err.message}`;
            } else {
                message = "Gateway error: " + err.message;
            }
            this.fail(formatter, message.slice(0, 400));
        }
        this.finished = true;
        this.pump();
    }
}

/**
 * The browser side: connectPage(machineID) connects the machine's COM2 to a Gateway that calls the Claude API from
 * the page, with the visitor's own API key.  The key comes from the page's URL fragment (eg, #claudekey=sk-ant-...),
 * which browsers never send to the server, and which is removed from the address bar as soon as this script runs;
 * otherwise, the first question asks for it with a prompt.  The key is kept in sessionStorage, so it lasts only as
 * long as the tab, and an invalid key is forgotten, so the next question asks again.
 *
 * The SDK is loaded (from a CDN) when the first question needs it, and HELP.TXT comes from the BASIC-DOS repository,
 * since the site doesn't publish src.
 */
const SDK_URL = "https://cdn.jsdelivr.net/npm/@anthropic-ai/sdk@1.14.0/+esm";
const HELP_URL = "https://raw.githubusercontent.com/jeffpar/basicdos/main/src/os/cmd/HELP.TXT";
const KEY_ITEM = "claudeKey";

let pageKey = "";

/**
 * readKey()
 *
 * @returns {string}
 */
function readKey()
{
    if (!pageKey) {
        try {
            pageKey = window.sessionStorage.getItem(KEY_ITEM) || "";
        } catch (err) {}
    }
    return pageKey;
}

/**
 * saveKey(key)
 *
 * @param {string} key (or "" to forget the key)
 */
function saveKey(key)
{
    pageKey = key;
    try {
        if (key) {
            window.sessionStorage.setItem(KEY_ITEM, key);
        } else {
            window.sessionStorage.removeItem(KEY_ITEM);
        }
    } catch (err) {}
}

/**
 * takeFragmentKey()
 *
 * Saves the key in the URL fragment, if any (#claudekey=..., alone or among other &-separated fragment items),
 * and removes it from the address bar (and from the page's history entry).
 */
function takeFragmentKey()
{
    let items = window.location.hash.slice(1).split("&");
    let i = items.findIndex((item) => item.startsWith("claudekey="));
    if (i >= 0) {
        let key = decodeURIComponent(items[i].slice(10)).trim();
        if (key) saveKey(key);
        items.splice(i, 1);
        let hash = items.join("&");
        window.history.replaceState(window.history.state, "", window.location.pathname + window.location.search + (hash? "#" + hash : ""));
    }
}

/**
 * connectPage(machineID, [portID])
 *
 * @param {string} machineID (eg, "ibm5160")
 * @param {string} [portID] (default "com2")
 */
export function connectPage(machineID, portID = "com2")
{
    takeFragmentKey();
    let sdk = null, client = null, help = null;
    let gateway = new Gateway({
        send: (bytes) => port['exports']['receiveData'].call(port, bytes),
        getClient: async function() {
            let key = readKey();
            if (!key) {
                key = (window.prompt("CLAUDE needs a Claude API key, which calls Claude from this page on your account.  Paste your key here (it's kept only until you close this tab):") || "").trim();
                if (!key) throw new GatewayError("No API key was entered.");
                saveKey(key);
                client = null;
            }
            if (!sdk) {
                try {
                    sdk = (await import(SDK_URL)).default;
                } catch (err) {
                    throw new GatewayError("Unable to load the Claude SDK.");
                }
            }
            if (!client || client.apiKey != key) client = new sdk({apiKey: key, dangerouslyAllowBrowser: true});
            return client;
        },
        system: async function() {
            if (help == null) {
                try {
                    let response = await fetch(HELP_URL);
                    help = response.ok? await response.text() : "";
                } catch (err) {
                    help = "";
                }
            }
            return systemPrompt(help);
        },
        onKeyError: () => saveKey(""),
        echo: /(^#|&)claudeecho(&|$)/.test(window.location.hash)
    });
    let port = null;
    let id = machineID + "." + portID;
    let attach = function() {
        let components = window['PCjs'] && window['PCjs']['components'] || [];
        port = components.find((component) => component['id'] == id && component['exports'] && component['exports']['bind']) || null;
        if (!port) {
            setTimeout(attach, 500);
            return;
        }
        if (!port['exports']['bind'].call(port, gateway, function(b) {
            gateway.receive([b]);
            return true;
        })) {
            console.log("claude-gateway: " + id + " is already connected");
        }
    };
    attach();
}
