'use strict';
'require baseclass';
'require ui';
'require acmesh.api_v2 as acmeshApi';

const ACKNOWLEDGEMENT = _('The plugin will execute the operation strictly according to the parameters above. By continuing, you confirm that you have reviewed and accept the consequences of certificate issuance quotas, remote file overwrite, service reload, and target system configuration.');

function isBooleanTrue(value) {
	return value === true || value === 1 || value === 'true' || value === '1';
}

function safeText(value) {
	return value == null || value === '' ? '-' : String(value);
}

function summaryRows(summary) {
	if (!summary || typeof summary !== 'object' || Array.isArray(summary))
		return [];
	return Object.keys(summary).sort().map(function(key) {
		const value = summary[key];
		return E('tr', {}, [
			E('th', {}, safeText(key)),
			E('td', {}, Array.isArray(value) ? value.map(safeText).join(', ') : safeText(value))
		]);
	});
}

function showChallenge(response, options) {
	options = options || {};
	return new Promise(function(resolve, reject) {
		const destructive = !!options.destructive || [ 'certificate-revoke', 'certificate-remove', 'profile-delete', 'import-apply' ].indexOf(response.operation) >= 0;
		const summary = response.riskSummary && typeof response.riskSummary === 'object' ? response.riskSummary : {};
		const sudoPasswordRequired = isBooleanTrue(response.sudoPasswordRequired) || isBooleanTrue(summary.sudoPasswordRequired) || isBooleanTrue(summary.deploySudoPasswordRequired);
		const sudoPasswordInput = sudoPasswordRequired ? E('input', { 'class': 'form-control', 'type': 'password', 'autocomplete': 'off', 'spellcheck': 'false' }) : null;
		const finish = function(decision) {
			if (decision === 'remember' && sudoPasswordInput && sudoPasswordInput.value)
				return;
			ui.hideModal();
			if (!decision) {
				resolve({ ok: false, cancelled: true });
				return;
			}
			const request = { challengeId: response.challengeId, decision: decision };
			if (sudoPasswordInput && sudoPasswordInput.value)
				request.sudoPassword = sudoPasswordInput.value;
			if (sudoPasswordInput)
				sudoPasswordInput.value = '';
			const requestPromise = acmeshApi.write('authorization_execute', request);
			if (request.sudoPassword)
				request.sudoPassword = '';
			requestPromise.then(function(next) {
				if (next && next.authorizationRequired) {
					showChallenge(next, options).then(resolve, reject);
					return;
				}
				resolve(next);
			}, reject);
		};
		const buttons = [
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() { finish(null); } }, _('Cancel')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function() { finish('once'); } }, _('Run once'))
		];
		if (!destructive)
			buttons.push(E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': function() { finish('remember'); } }, _('Run and remember')));
		const content = [
			E('p', { 'class': 'acmesh-warning' }, _('Review the exact material operation before continuing.')),
			E('table', { 'class': 'table acmesh-authorization-summary' }, E('tbody', {}, summaryRows(response.riskSummary))),
			E('p', { 'class': 'acmesh-authorization-ack' }, ACKNOWLEDGEMENT),
			E('div', { 'class': 'right' }, buttons)
		];
		if (sudoPasswordInput) {
			content.splice(2, 0, E('div', { 'class': 'acmesh-sudo-password' }, [
				E('label', {}, [_('One-time sudo password (leave blank for passwordless sudo)'), sudoPasswordInput])
			]));
		}
		ui.showModal(_('Risk authorization required'), content);
	});
}

function showHostKey(response, options) {
	options = options || {};
	const changed = response.hostKeyChanged || response.error === 'hostKeyChanged';
	if (changed) {
		ui.showModal(_('SSH host key changed'), [
			E('p', { 'class': 'alert-message error' }, _('The SSH host identity changed. Deployment is blocked. Verify the host outside this operation before replacing the pinned identity.')),
			E('dl', {}, [ E('dt', {}, _('Key algorithm')), E('dd', {}, safeText(response.algorithm)), E('dt', {}, _('Fingerprint')), E('dd', {}, safeText(response.fingerprint)) ]),
			E('div', { 'class': 'right' }, E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close')))
		]);
		return Promise.resolve(response);
	}
	return new Promise(function(resolve, reject) {
		ui.showModal(_('Confirm SSH host identity'), [
			E('dl', {}, [ E('dt', {}, _('Host')), E('dd', {}, safeText(response.host || options.host)), E('dt', {}, _('Port')), E('dd', {}, safeText(response.port || options.port || 22)), E('dt', {}, _('Key algorithm')), E('dd', {}, safeText(response.algorithm)), E('dt', {}, _('Fingerprint')), E('dd', {}, safeText(response.fingerprint)) ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); resolve({ ok: false, cancelled: true }); } }, _('Cancel')),
				E('button', { 'class': 'btn cbi-button-positive', 'click': function() { ui.hideModal(); acmeshApi.write('ssh_hostkey_confirm', { challengeId: response.challengeId }).then(resolve, reject); } }, _('Confirm and pin'))
			])
		]);
	});
}

function run(method, payload, options) {
	return acmeshApi.write(method, payload).then(function(response) {
		if (response && (response.hostKeyChanged || response.error === 'hostKeyChanged'))
			return showHostKey(response, options);
		if (response && (response.hostKeyRequired || response.error === 'hostKeyRequired')) {
			const challenge = response.challengeId ? Promise.resolve(response) : acmeshApi.write('ssh_hostkey_probe', { host: options && options.host, port: options && options.port || 22 });
			return challenge.then(function(probed) {
				if (!probed || probed.ok || (!probed.challengeId && probed.error !== 'hostKeyChanged'))
					return probed || { ok: false, error: 'hostKeyProbeFailed' };
				return showHostKey(probed, options);
			}).then(function(confirmed) {
				return confirmed && confirmed.ok ? run(method, payload, options) : confirmed;
			});
		}
		if (!response || !response.authorizationRequired)
			return response;
		return showChallenge(response, options);
	});
}

function badge(status) {
	const active = status === true || status === 'Active' || status === 'authorized';
	return E('span', { 'class': 'acmesh-authorization-badge ' + (active ? 'is-authorized' : 'is-stale') }, active ? _('Authorized') : safeText(status));
}

return baseclass.extend({
	run: run,
	showChallenge: showChallenge,
	showHostKey: showHostKey,
	badge: badge
});
