/**
 * Mailgun Inbound Relay
 * Receives Mailgun webhook POSTs (multipart/form-data via busboy),
 * verifies signature, reconstructs MIME if needed, and injects into
 * Stalwart via SMTP on port 25 using MAIL FROM:<relay@eurion.se>.
 */

'use strict';

const http = require('http');
const https = require('https');
const crypto = require('crypto');
const net = require('net');
const Busboy = require('busboy');

const PORT = process.env.PORT || 8025;
const MAILGUN_SIGNING_KEY = process.env.MAILGUN_SIGNING_KEY || '';
const MAILGUN_API_KEY = process.env.MAILGUN_API_KEY || '';
const STALWART_HOST = process.env.STALWART_HOST || 'eurion-stalwart';
const STALWART_PORT = parseInt(process.env.STALWART_PORT || '25', 10);
const STALWART_IMAP_PORT = parseInt(process.env.STALWART_IMAP_PORT || '143', 10);
const IMAP_ADMIN_USER = process.env.IMAP_ADMIN_USER || 'admin';
const IMAP_ADMIN_PASS = process.env.IMAP_ADMIN_PASS || '';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

function log(level, msg, data) {
  if (level === 'debug' && LOG_LEVEL !== 'debug') return;
  const entry = { ts: new Date().toISOString(), level, msg };
  if (data) Object.assign(entry, data);
  console.log(JSON.stringify(entry));
}

// ── Mailgun signature verification ─────────────────────────────────────────
function verifyMailgunSignature(timestamp, token, signature) {
  if (!MAILGUN_SIGNING_KEY) {
    log('debug', 'Skipping signature verification (no key set)');
    return true;
  }
  if (!timestamp || !token || !signature) return false;
  var tsStr = String(timestamp);
  var age = Math.abs(Date.now() / 1000 - parseInt(tsStr, 10));
  if (age > 300) return false;
  var hmac = crypto.createHmac('sha256', MAILGUN_SIGNING_KEY);
  hmac.update(tsStr + String(token));
  var computed = hmac.digest('hex');
  var sigStr = String(signature);
  if (computed.length !== sigStr.length) return false;
  return crypto.timingSafeEqual(Buffer.from(computed), Buffer.from(sigStr));
}

// ── Reconstruct raw MIME from Mailgun parsed fields ────────────────────────
// Used when body-mime is not present (free plan / store action without TTL)
function reconstructMime(fields) {
  const from = fields['from'] || fields['sender'] || 'unknown@mailgun';
  const to = fields['recipient'] || '';
  const subject = fields['subject'] || '(no subject)';
  const date = new Date().toUTCString();
  const msgId = fields['Message-Id'] || `<${Date.now()}@eurion.se>`;
  const boundary = '----=_Part_' + Math.random().toString(36).slice(2);

  const plain = fields['body-plain'] || fields['stripped-text'] || '';
  const html = fields['body-html'] || fields['stripped-html'] || '';

  let mime = `From: ${from}\r\n`;
  mime += `To: ${to}\r\n`;
  mime += `Subject: ${subject}\r\n`;
  mime += `Date: ${date}\r\n`;
  mime += `Message-ID: ${msgId}\r\n`;
  mime += `MIME-Version: 1.0\r\n`;

  if (html) {
    mime += `Content-Type: multipart/alternative; boundary="${boundary}"\r\n\r\n`;
    mime += `--${boundary}\r\n`;
    mime += `Content-Type: text/plain; charset=UTF-8\r\n\r\n`;
    mime += plain + '\r\n';
    mime += `--${boundary}\r\n`;
    mime += `Content-Type: text/html; charset=UTF-8\r\n\r\n`;
    mime += html + '\r\n';
    mime += `--${boundary}--\r\n`;
  } else {
    mime += `Content-Type: text/plain; charset=UTF-8\r\n\r\n`;
    mime += plain + '\r\n';
  }

  return mime;
}

// ── Fetch raw MIME from Mailgun storage API (fallback) ─────────────────────
function fetchFromMailgunStorage(storageUrl) {
  return new Promise((resolve, reject) => {
    if (!MAILGUN_API_KEY) return reject(new Error('No MAILGUN_API_KEY set'));
    const url = new URL(storageUrl);
    const opts = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      headers: {
        Authorization: 'Basic ' + Buffer.from('api:' + MAILGUN_API_KEY).toString('base64'),
        Accept: 'message/rfc2822',
      },
    };
    https.get(opts, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        if (res.statusCode !== 200) return reject(new Error('Storage fetch ' + res.statusCode));
        const body = JSON.parse(Buffer.concat(chunks).toString());
        resolve(body['body-mime'] || '');
      });
    }).on('error', reject);
  });
}

// ── Extract local part from email address ──────────────────────────────────
function localPart(addr) {
  const m = addr.match(/<?([^@>]+)@/);
  return m ? m[1] : addr;
}

// ── SMTP injection into Stalwart ───────────────────────────────────────────
function injectViaSMTP(sender, recipients, rawMime) {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection(STALWART_PORT, STALWART_HOST);
    let state = 'GREETING';
    let buffer = '';
    const recipientList = Array.isArray(recipients) ? recipients : [recipients];
    let rcptIndex = 0;

    const send = (cmd) => {
      log('debug', `SMTP >> ${cmd}`);
      sock.write(cmd + '\r\n');
    };

    sock.on('data', (data) => {
      buffer += data.toString();
      const lines = buffer.split('\r\n');
      buffer = lines.pop();
      for (const line of lines) {
        if (!line) continue;
        const code = parseInt(line.slice(0, 3), 10);
        if (line[3] === '-') continue;
        switch (state) {
          case 'GREETING':
            if (code === 220) { send('EHLO mail.eurion.se'); state = 'EHLO'; }
            else { sock.destroy(); reject(new Error(`Bad greeting: ${line}`)); }
            break;
          case 'EHLO':
            if (code === 250) { send('MAIL FROM:<relay@eurion.se>'); state = 'MAIL'; }
            break;
          case 'MAIL':
            if (code === 250) { send(`RCPT TO:<${recipientList[rcptIndex]}>`); state = 'RCPT'; }
            else { sock.destroy(); reject(new Error(`MAIL FROM failed: ${line}`)); }
            break;
          case 'RCPT':
            if (code === 250) {
              rcptIndex++;
              if (rcptIndex < recipientList.length) send(`RCPT TO:<${recipientList[rcptIndex]}>`);
              else { send('DATA'); state = 'DATA_CMD'; }
            } else { sock.destroy(); reject(new Error(`RCPT TO failed: ${line}`)); }
            break;
          case 'DATA_CMD':
            if (code === 354) {
              sock.write(rawMime.replace(/\n\./g, '\n..') + '\r\n.\r\n');
              state = 'DATA_BODY';
            } else { sock.destroy(); reject(new Error(`DATA failed: ${line}`)); }
            break;
          case 'DATA_BODY':
            if (code === 250) { send('QUIT'); state = 'QUIT'; }
            else { sock.destroy(); reject(new Error(`Message rejected: ${line}`)); }
            break;
          case 'QUIT':
            sock.destroy(); resolve({ status: 'delivered', recipients: recipientList });
            break;
        }
      }
    });
    sock.on('error', reject);
    sock.on('timeout', () => { sock.destroy(); reject(new Error('SMTP timeout')); });
    sock.setTimeout(15000);
  });
}

// ── Parse multipart form using busboy ──────────────────────────────────────
function parseMultipart(req) {
  return new Promise((resolve, reject) => {
    const fields = {};
    const bb = Busboy({ headers: req.headers });
    bb.on('field', (name, val) => {
      fields[name] = val;
      log('debug', `Field: ${name} = ${val.slice(0, 80)}`);
    });
    bb.on('finish', () => resolve(fields));
    bb.on('error', reject);
    req.pipe(bb);
  });
}

// ── HTTP Server ────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service: 'mailgun-inbound-relay' }));
    return;
  }

  if (req.method !== 'POST' ||
      (req.url !== '/inbound' && req.url !== '/v1/mail/inbound')) {
    res.writeHead(404); res.end('Not found'); return;
  }

  const contentType = req.headers['content-type'] || '';

  const processFields = async (fields) => {
    log('debug', 'Parsed fields', { keys: Object.keys(fields) });

    const { timestamp, token, signature } = fields;

    if (!verifyMailgunSignature(timestamp, token, signature)) {
      log('warn', 'Invalid Mailgun signature — rejected');
      res.writeHead(406); res.end('Invalid signature'); return;
    }

    const sender = fields.sender || fields['from'] || 'unknown@mailgun';
    const recipient = fields.recipient || fields['to'] || '';
    let rawMime = fields['body-mime'] || '';

    if (!recipient) {
      log('warn', 'Missing recipient', { keys: Object.keys(fields) });
      res.writeHead(400); res.end('Missing recipient'); return;
    }

    // Fallback: reconstruct MIME from parsed fields (free plan - no storage retrieval)
    if (!rawMime) {
      const storageUrl = fields['message-url'];
      if (storageUrl) {
        log('info', 'body-mime missing, trying storage fetch', { url: storageUrl });
        try {
          rawMime = await fetchFromMailgunStorage(storageUrl);
        } catch (e) {
          log('debug', 'Storage fetch failed (expected on free plan)', { error: e.message });
        }
      }
      if (!rawMime) {
        log('info', 'Reconstructing MIME from parsed fields');
        rawMime = reconstructMime(fields);
      }
    }

    if (!rawMime) {
      log('warn', 'Could not obtain message body', { recipient, keys: Object.keys(fields) });
      res.writeHead(400); res.end('Missing body'); return;
    }

    log('info', 'Injecting message', { from: sender, to: recipient, size: rawMime.length });

    try {
      const result = await injectViaSMTP(sender, recipient.split(',').map(r => r.trim()), rawMime);
      log('info', 'Message delivered to Stalwart', result);
      res.writeHead(200); res.end('OK');
    } catch (err) {
      log('error', 'Injection failed', { error: err.message });
      res.writeHead(500); res.end('Error: ' + err.message);
    }
  };

  if (contentType.includes('multipart/form-data')) {
    parseMultipart(req).then(processFields).catch(err => {
      log('error', 'Multipart parse failed', { error: err.message });
      res.writeHead(400); res.end('Parse error');
    });
  } else {
    // application/x-www-form-urlencoded
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const fields = Object.fromEntries(new URLSearchParams(Buffer.concat(chunks).toString()));
      processFields(fields).catch(err => {
        log('error', 'Processing failed', { error: err.message });
        res.writeHead(500); res.end('Error');
      });
    });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  log('info', 'Mailgun inbound relay started', {
    port: PORT,
    stalwart: `${STALWART_HOST}:${STALWART_PORT}`,
    method: IMAP_ADMIN_PASS ? 'IMAP-APPEND' : 'SMTP-relay',
    sigVerify: !!MAILGUN_SIGNING_KEY,
  });
});
