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

function write(method, payload) {
	const id = requestId();
	const path = '/var/run/acmesh-console/requests/' + id + '.json';
	return fs.write(path, JSON.stringify(payload || {}), 384).then(function() {
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
