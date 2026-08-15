'use strict';
'require baseclass';
'require fs';

function requestId() {
	const bytes = new Uint8Array(16);
	window.crypto.getRandomValues(bytes);
	return Array.prototype.map.call(bytes, function(value) {
		return value.toString(16).padStart(2, '0');
	}).join('');
}

function read(method, args) {
	return fs.exec_direct('/usr/libexec/acmesh-console/rpc-read',
		[ method ].concat(args || []), 'json', false, false);
}

const IMPORT_UPLOAD_CHUNK_SIZE = 16 * 1024;
const IMPORT_UPLOAD_THRESHOLD = 32 * 1024;

function importChunkPath(id, index) {
	return '/var/run/acmesh-console/requests/' + id + '.part.' + index;
}

function cleanupChunkedImport(id, count) {
	return fs.exec_direct('/usr/libexec/acmesh-console/rpc-write', [
		'import_preview_cleanup', '--request-id', id, '--chunk-count', String(count)
	], 'json', false, false);
}

function writeChunkedImport(payloadText) {
	const id = requestId();
	const count = Math.ceil(payloadText.length / IMPORT_UPLOAD_CHUNK_SIZE);
	let upload = Promise.resolve();

	for (let index = 0; index < count; index++) {
		const start = index * IMPORT_UPLOAD_CHUNK_SIZE;
		const chunk = payloadText.slice(start, start + IMPORT_UPLOAD_CHUNK_SIZE);
		upload = upload.then(function() {
			return fs.write(importChunkPath(id, index), chunk, 384);
		});
	}

	return upload.then(function() {
		return fs.exec_direct('/usr/libexec/acmesh-console/rpc-write', [
			'import_preview', '--request-id', id, '--chunk-count', String(count)
		], 'json', false, false);
	}).finally(function() {
		return L.resolveDefault(cleanupChunkedImport(id, count), 0);
	});
}

function write(method, payload) {
	const payloadText = JSON.stringify(payload || {});
	if (method === 'import_preview' && payloadText.length > IMPORT_UPLOAD_THRESHOLD)
		return writeChunkedImport(payloadText);

	const id = requestId();
	const path = '/var/run/acmesh-console/requests/' + id + '.json';
	return fs.write(path, payloadText, 384).then(function() {
		return fs.exec_direct('/usr/libexec/acmesh-console/rpc-write',
			[ method, '--request-id', id ], 'json', false, false);
	}).finally(function() {
		return L.resolveDefault(fs.remove(path), 0);
	});
}

return baseclass.extend({
	read: read,
	write: write
});
