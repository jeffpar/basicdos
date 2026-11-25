#!/usr/bin/env node
/**
 * @fileoverview Connects a BASIC-DOS serial port to Claude (see CLAUDE.BAS)
 * @copyright © 2026 Jeff Parsons
 * @license MIT <https://www.pcjs.org/LICENSE.txt>
 *
 * The gateway reads the serial port's bytes on stdin and writes the replies on stdout,
 * so it can be connected to a pc.js machine's COM2:
 *
 *      pc.js ... --com2="node tools/claude/gateway.js"
 *
 * or to a real PC's serial port (eg, through a null-modem cable and a USB adapter):
 *
 *      socat /dev/cu.usbserial,raw,echo=0,b9600 EXEC:"node tools/claude/gateway.js"
 *
 * The API key comes from the environment (ANTHROPIC_API_KEY), and stays on the host.  The protocol
 * itself is in assets/js/claude-gateway.js, which the demo pages use, too.
 *
 * Options:
 *
 *      --model=id      Claude model (default claude-opus-5-5)
 *      --effort=level  low, medium, high, xhigh, or max (default low)
 *      --help=file     reference text for the system prompt (default src/os/cmd/HELP.TXT,
 *                      or --help=none for no reference text)
 *      --log=file      append a log of requests and errors to file
 *      --echo          answer every question with the question itself (no API calls), for testing
 */

import fs from "fs";
import os from "os";
import path from "path";
import { fileURLToPath } from "url";
import Anthropic from "@anthropic-ai/sdk";
import { Gateway, GatewayError, systemPrompt } from "../../assets/js/claude-gateway.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = {};
for (let arg of process.argv.slice(2)) {
    let match = arg.match(/^--([a-z]+)(?:=(.*))?$/);
    if (!match) {
        process.stderr.write("gateway.js: unrecognized argument: " + arg + "\n");
        process.exit(1);
    }
    args[match[1]] = match[2] ?? true;
}

let help = "";
let helpFile = args.help ?? path.join(here, "../../src/os/cmd/HELP.TXT");
if (helpFile !== "none" && helpFile !== true) {
    try {
        help = fs.readFileSync(helpFile, "utf8");
    } catch (err) {
        process.stderr.write("gateway.js: unable to read " + helpFile + "\n");
    }
}

let client = null;
let gateway = new Gateway({
    send: (bytes) => process.stdout.write(Buffer.from(bytes)),
    getClient: async function() {
        /**
         * The SDK reports missing credentials only when it sends a request (and as a plain Error), so look for
         * them first: a key or token in the environment, or a profile from `ant auth login`.
         */
        if (!client) {
            let profiles = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "anthropic");
            if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN && !fs.existsSync(profiles)) {
                throw new GatewayError("The gateway has no API key (set ANTHROPIC_API_KEY).");
            }
            client = new Anthropic();
        }
        return client;
    },
    system: systemPrompt(help),
    log: args.log? (s) => fs.appendFileSync(args.log, new Date().toISOString() + " " + s + "\n") : null,
    model: args.model,
    effort: args.effort,
    echo: !!args.echo
});

process.stdin.on("data", (data) => gateway.receive(data));
process.stdin.on("end", () => process.exit(0));
process.stdout.on("error", () => process.exit(0));
