#!/usr/bin/env node
/**
 * Headless browser console checker
 * Usage: node check-console.js <url> [--wait <ms>]
 *
 * Opens URL in headless Chrome, waits for page load + optional delay,
 * captures all console messages and errors, then exits.
 */

const puppeteer = require('puppeteer');

async function checkConsole(url, waitMs = 2000) {
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    const page = await browser.newPage();

    const messages = [];
    const errors = [];

    // Capture console messages
    page.on('console', msg => {
        const type = msg.type();
        const text = msg.text();

        if (type === 'error') {
            errors.push({ type: 'console.error', text });
        } else if (type === 'warning') {
            messages.push({ type: 'console.warn', text });
        } else {
            messages.push({ type: `console.${type}`, text });
        }
    });

    // Capture page errors (uncaught exceptions)
    page.on('pageerror', err => {
        errors.push({ type: 'uncaught', text: err.message });
    });

    // Capture failed requests
    page.on('requestfailed', req => {
        errors.push({
            type: 'network',
            text: `${req.failure().errorText}: ${req.url()}`
        });
    });

    try {
        // Navigate to page
        const response = await page.goto(url, {
            waitUntil: 'networkidle2',
            timeout: 30000
        });

        const status = response.status();

        // Wait for any async errors
        await new Promise(r => setTimeout(r, waitMs));

        // Output results
        console.log(JSON.stringify({
            url,
            status,
            errors,
            warnings: messages.filter(m => m.type === 'console.warn'),
            logs: messages.filter(m => m.type !== 'console.warn'),
            summary: {
                errorCount: errors.length,
                warningCount: messages.filter(m => m.type === 'console.warn').length
            }
        }, null, 2));

    } catch (err) {
        console.log(JSON.stringify({
            url,
            status: 'failed',
            errors: [{ type: 'navigation', text: err.message }],
            warnings: [],
            logs: [],
            summary: { errorCount: 1, warningCount: 0 }
        }, null, 2));
    }

    await browser.close();
}

// Parse args
const args = process.argv.slice(2);
const url = args[0];
const waitIdx = args.indexOf('--wait');
const waitMs = waitIdx !== -1 ? parseInt(args[waitIdx + 1]) : 2000;

if (!url) {
    console.error('Usage: node check-console.js <url> [--wait <ms>]');
    process.exit(1);
}

checkConsole(url, waitMs);
