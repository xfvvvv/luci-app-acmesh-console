#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function usage() {
	console.error(`Usage: ${path.basename(process.argv[1])} input.po output.lmo`);
	process.exit(1);
}

function u32(value) {
	return value >>> 0;
}

function get16(buf, offset) {
	return ((buf[offset + 1] || 0) << 8) + (buf[offset] || 0);
}

function signedByte(value) {
	value &= 0xff;
	return value > 127 ? value - 256 : value;
}

function sfhHash(text) {
	const data = Buffer.from(text, 'utf8');
	let len = data.length;
	let hash = u32(len);
	let offset = 0;
	const rem = len & 3;
	len >>= 2;

	for (; len > 0; len--) {
		hash = u32(hash + get16(data, offset));
		const tmp = u32((get16(data, offset + 2) << 11) ^ hash);
		hash = u32((hash << 16) ^ tmp);
		offset += 4;
		hash = u32(hash + (hash >>> 11));
	}

	if (rem === 3) {
		hash = u32(hash + get16(data, offset));
		hash = u32(hash ^ (hash << 16));
		hash = u32(hash ^ (signedByte(data[offset + 2]) << 18));
		hash = u32(hash + (hash >>> 11));
	} else if (rem === 2) {
		hash = u32(hash + get16(data, offset));
		hash = u32(hash ^ (hash << 11));
		hash = u32(hash + (hash >>> 17));
	} else if (rem === 1) {
		hash = u32(hash + signedByte(data[offset]));
		hash = u32(hash ^ (hash << 10));
		hash = u32(hash + (hash >>> 1));
	}

	hash = u32(hash ^ (hash << 3));
	hash = u32(hash + (hash >>> 5));
	hash = u32(hash ^ (hash << 4));
	hash = u32(hash + (hash >>> 17));
	hash = u32(hash ^ (hash << 25));
	hash = u32(hash + (hash >>> 6));

	return hash;
}

function appendPadded(chunks, text) {
	const data = Buffer.from(text, 'utf8');
	chunks.push(data);

	const pad = (4 - (data.length % 4)) % 4;
	if (pad)
		chunks.push(Buffer.alloc(pad));

	return data.length + pad;
}

function extractPoString(line) {
	const trimmed = line.trimStart();
	if (trimmed.startsWith('#'))
		return null;

	const firstQuote = line.indexOf('"');
	if (firstQuote < 0)
		return null;

	let out = '';
	let esc = false;

	for (let i = firstQuote + 1; i < line.length; i++) {
		const ch = line[i];

		if (esc) {
			if (ch === '"' || ch === '\\')
				out += ch;
			else
				out += '\\' + ch;
			esc = false;
		} else if (ch === '\\') {
			esc = true;
		} else if (ch === '"') {
			return out;
		} else {
			out += ch;
		}
	}

	return out;
}

function emptyMsg() {
	return {
		pluralNum: -1,
		ctxt: null,
		id: null,
		idPlural: null,
		val: [],
		cur: null
	};
}

function ensureCurrent(msg) {
	if (msg.cur === 'ctxt' && msg.ctxt == null)
		msg.ctxt = '';
	else if (msg.cur === 'id' && msg.id == null)
		msg.id = '';
	else if (msg.cur === 'idPlural' && msg.idPlural == null)
		msg.idPlural = '';
	else if (msg.cur && msg.cur.startsWith('val:')) {
		const idx = Number(msg.cur.slice(4));
		if (msg.val[idx] == null)
			msg.val[idx] = '';
	}
}

function appendCurrent(msg, text) {
	if (!msg.cur)
		return;

	ensureCurrent(msg);

	if (msg.cur === 'ctxt')
		msg.ctxt += text;
	else if (msg.cur === 'id')
		msg.id += text;
	else if (msg.cur === 'idPlural')
		msg.idPlural += text;
	else if (msg.cur.startsWith('val:')) {
		const idx = Number(msg.cur.slice(4));
		msg.val[idx] += text;
	}
}

function emitMsg(msg, chunks, entries, offsetRef) {
	if (msg.id != null && msg.id !== '' && msg.val[0] != null) {
		for (let i = 0; i <= msg.pluralNum; i++) {
			if (msg.val[i] == null)
				continue;

			let key;
			if (msg.ctxt != null && msg.idPlural != null)
				key = `${msg.ctxt}\x01${msg.id}\x02${i}`;
			else if (msg.ctxt != null)
				key = `${msg.ctxt}\x01${msg.id}`;
			else if (msg.idPlural != null)
				key = `${msg.id}\x02${i}`;
			else
				key = msg.id;

			const keyId = sfhHash(key);
			const valId = sfhHash(msg.val[i]);

			if (keyId !== valId) {
				const length = Buffer.byteLength(msg.val[i], 'utf8');
				entries.push({
					keyId,
					valId: msg.pluralNum + 1,
					offset: offsetRef.value,
					length
				});
				offsetRef.value += appendPadded(chunks, msg.val[i]);
			}
		}
	}
}

function parsePo(source) {
	const chunks = [];
	const entries = [];
	const offsetRef = { value: 0 };
	let msg = emptyMsg();

	for (const rawLine of source.split(/\r?\n/)) {
		const line = rawLine;

		if (line.startsWith('msgctxt "')) {
			if (msg.id != null || msg.val[0] != null) {
				emitMsg(msg, chunks, entries, offsetRef);
				msg = emptyMsg();
			}
			msg.cur = 'ctxt';
			msg.ctxt = '';
		} else if (line.startsWith('msgid "')) {
			if (msg.id != null || msg.val[0] != null) {
				emitMsg(msg, chunks, entries, offsetRef);
				msg = emptyMsg();
			}
			msg.cur = 'id';
			msg.id = '';
		} else if (line.startsWith('msgid_plural "')) {
			msg.cur = 'idPlural';
			msg.idPlural = '';
		} else if (line.startsWith('msgstr "') || line.startsWith('msgstr[')) {
			let idx = 0;
			const pluralMatch = line.match(/^msgstr\[(\d+)\]/);
			if (pluralMatch)
				idx = Number(pluralMatch[1]);

			if (idx >= 10)
				throw new Error('Too many plural forms');

			msg.pluralNum = idx;
			msg.cur = `val:${idx}`;
			msg.val[idx] = '';
		}

		const extracted = extractPoString(line);
		if (extracted != null)
			appendCurrent(msg, extracted);
	}

	if (msg.id != null || msg.val[0] != null)
		emitMsg(msg, chunks, entries, offsetRef);

	return { chunks, entries, stringsLength: offsetRef.value };
}

function buildLmo(source) {
	const { chunks, entries, stringsLength } = parsePo(source);
	if (!stringsLength)
		throw new Error('No translatable entries found');

	entries.sort((a, b) => a.keyId - b.keyId);

	for (const entry of entries) {
		const buf = Buffer.alloc(16);
		buf.writeUInt32BE(entry.keyId >>> 0, 0);
		buf.writeUInt32BE(entry.valId >>> 0, 4);
		buf.writeUInt32BE(entry.offset >>> 0, 8);
		buf.writeUInt32BE(entry.length >>> 0, 12);
		chunks.push(buf);
	}

	const footer = Buffer.alloc(4);
	footer.writeUInt32BE(stringsLength >>> 0, 0);
	chunks.push(footer);

	return Buffer.concat(chunks);
}

if (process.argv.length !== 4)
	usage();

const input = process.argv[2];
const output = process.argv[3];
const lmo = buildLmo(fs.readFileSync(input, 'utf8'));

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, lmo);
