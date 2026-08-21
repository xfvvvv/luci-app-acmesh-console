'use strict';
'require view';
'require ui';
'require acmesh.api_v2 as acmeshApi';
'require acmesh.authorization_v2 as authorization';

const DEFAULT_CONFIG = {
	global: {
		defaultAccountEmail: '',
		coreTag: 'v3.1.4',
		acmeHome: '/etc/acme'
	},
	accountProfiles: [],
	issueProfiles: [],
	deployProfiles: []
};

const SECRET_PLACEHOLDER = '********';
const TERMINAL_TASK_STATES = [ 'success', 'failed', 'interrupted', 'cancelled' ];

function requireConfig(response) {
	if (!response || response.ok === false || !response.global ||
		!Array.isArray(response.accountProfiles) ||
		!Array.isArray(response.issueProfiles) ||
		!Array.isArray(response.deployProfiles))
		throw new Error(response && response.error || _('Unable to load configuration'));
	return response;
}

const DNS_PROVIDER_TEMPLATES = {
	dns_cf: {
		title: _('Cloudflare'),
		modes: [
			{
				id: 'token',
				title: _('Token'),
				fields: [
					{ env: 'CF_Token', label: _('Cloudflare API Token'), secret: true, required: true },
					{ env: 'CF_Zone_ID', label: _('Cloudflare Zone ID') },
					{ env: 'CF_Account_ID', label: _('Cloudflare Account ID') }
				]
			},
			{
				id: 'global-key',
				title: _('Global Key'),
				fields: [
					{ env: 'CF_Email', label: _('Cloudflare Email'), required: true },
					{ env: 'CF_Key', label: _('Cloudflare Global API Key'), secret: true, required: true }
				]
			}
		]
	},
	dns_ali: {
		title: _('Aliyun'),
		modes: [
			{ id: 'access-key', title: _('AccessKey'), fields: [
				{ env: 'Ali_Key', label: _('Aliyun AccessKey ID'), required: true },
				{ env: 'Ali_Secret', label: _('Aliyun AccessKey Secret'), secret: true, required: true }
			] }
		]
	},
	dns_dp: {
		title: _('DNSPod.cn'),
		modes: [
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'DP_Id', label: _('DNSPod ID'), required: true },
				{ env: 'DP_Key', label: _('DNSPod Token'), secret: true, required: true }
			] }
		]
	},
	dns_tencent: {
		title: _('Tencent Cloud DNSPod'),
		modes: [
			{ id: 'secret', title: _('SecretId / SecretKey'), fields: [
				{ env: 'Tencent_SecretId', label: _('Tencent SecretId'), required: true },
				{ env: 'Tencent_SecretKey', label: _('Tencent SecretKey'), secret: true, required: true }
			] }
		]
	},
	dns_duckdns: {
		title: _('DuckDNS'),
		modes: [
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'DuckDNS_Token', label: _('DuckDNS Token'), secret: true, required: true }
			] }
		]
	},
	dns_cloudns: {
		title: _('ClouDNS'),
		modes: [
			{ id: 'regular-auth', title: _('Regular Auth ID'), fields: [
				{ env: 'CLOUDNS_AUTH_ID', label: _('ClouDNS Auth ID'), required: true },
				{ env: 'CLOUDNS_AUTH_PASSWORD', label: _('ClouDNS Auth Password'), secret: true, required: true }
			] },
			{ id: 'sub-auth', title: _('Sub Auth ID'), fields: [
				{ env: 'CLOUDNS_SUB_AUTH_ID', label: _('ClouDNS Sub Auth ID'), required: true },
				{ env: 'CLOUDNS_AUTH_PASSWORD', label: _('ClouDNS Auth Password'), secret: true, required: true }
			] }
		]
	},
	dns_dynv6: {
		title: _('dynv6'),
		modes: [
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'DYNV6_TOKEN', label: _('dynv6 Token'), secret: true, required: true }
			] },
			{ id: 'ssh-key', title: _('SSH Key'), fields: [
				{ env: 'KEY', label: _('dynv6 SSH private key path'), required: true }
			] }
		]
	},
	dns_gd: {
		title: _('GoDaddy'),
		modes: [
			{ id: 'key-secret', title: _('Key / Secret'), fields: [
				{ env: 'GD_Key', label: _('GoDaddy Key'), required: true },
				{ env: 'GD_Secret', label: _('GoDaddy Secret'), secret: true, required: true }
			] }
		]
	},
	dns_gcore: {
		title: _('Gcore DNS'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'GCORE_Key', label: _('Gcore API Key'), secret: true, required: true }
			] }
		]
	},
	dns_aws: {
		title: _('Amazon Route 53'),
		modes: [
			{ id: 'access-key', title: _('Access Key'), fields: [
				{ env: 'AWS_ACCESS_KEY_ID', label: _('AWS Access Key ID'), required: true },
				{ env: 'AWS_SECRET_ACCESS_KEY', label: _('AWS Secret Access Key'), secret: true, required: true },
				{ env: 'AWS_SESSION_TOKEN', label: _('AWS Session Token'), secret: true },
				{ env: 'AWS_DNS_SLOWRATE', label: _('AWS DNS slow rate') }
			] }
		]
	},
	dns_baidu: {
		title: _('Baidu Cloud DNS'),
		modes: [
			{ id: 'access-key', title: _('Access Key'), fields: [
				{ env: 'Baidu_AK', label: _('Baidu Access Key ID'), required: true },
				{ env: 'Baidu_SK', label: _('Baidu Secret Access Key'), secret: true, required: true },
				{ env: 'Baidu_API_Preference', label: _('Baidu API preference') },
				{ env: 'Baidu_View', label: _('Baidu DNS view') },
				{ env: 'Baidu_Line', label: _('Baidu DNS line') }
			] }
		]
	},
	dns_azure: {
		title: _('Azure DNS'),
		modes: [
			{ id: 'service-principal', title: _('Service Principal'), fields: [
				{ env: 'AZUREDNS_SUBSCRIPTIONID', label: _('Azure Subscription ID'), required: true },
				{ env: 'AZUREDNS_TENANTID', label: _('Azure Tenant ID'), required: true },
				{ env: 'AZUREDNS_APPID', label: _('Azure App ID'), required: true },
				{ env: 'AZUREDNS_CLIENTSECRET', label: _('Azure Client Secret'), secret: true, required: true }
			] },
			{ id: 'bearer-token', title: _('Bearer Token'), fields: [
				{ env: 'AZUREDNS_SUBSCRIPTIONID', label: _('Azure Subscription ID'), required: true },
				{ env: 'AZUREDNS_BEARERTOKEN', label: _('Azure Bearer Token'), secret: true, required: true }
			] },
			{ id: 'managed-identity', title: _('Managed Identity'), fields: [
				{ env: 'AZUREDNS_SUBSCRIPTIONID', label: _('Azure Subscription ID'), required: true },
				{ env: 'AZUREDNS_MANAGEDIDENTITY', label: _('Use Azure Managed Identity'), required: true }
			] }
		]
	},
	dns_he: {
		title: _('Hurricane Electric'),
		modes: [
			{ id: 'password', title: _('Password'), fields: [
				{ env: 'HE_Username', label: _('HE Username'), required: true },
				{ env: 'HE_Password', label: _('HE Password'), secret: true, required: true }
			] }
		]
	},
	dns_huaweicloud: {
		title: _('Huawei Cloud DNS'),
		modes: [
			{ id: 'password', title: _('Username / Password'), fields: [
				{ env: 'HUAWEICLOUD_Username', label: _('Huawei Cloud Username'), required: true },
				{ env: 'HUAWEICLOUD_Password', label: _('Huawei Cloud Password'), secret: true, required: true },
				{ env: 'HUAWEICLOUD_DomainName', label: _('Huawei Cloud Domain Name'), required: true },
				{ env: 'HUAWEICLOUD_Region', label: _('Huawei Cloud Region') }
			] }
		]
	},
	dns_namecheap: {
		title: _('Namecheap'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'NAMECHEAP_USERNAME', label: _('Namecheap Username'), required: true },
				{ env: 'NAMECHEAP_API_KEY', label: _('Namecheap API Key'), secret: true, required: true },
				{ env: 'NAMECHEAP_SOURCEIP', label: _('Namecheap Source IP'), required: true }
			] }
		]
	},
	dns_la: {
		title: _('DNS.LA'),
		modes: [
			{ id: 'id-secret', title: _('ID / Secret'), fields: [
				{ env: 'LA_Id', label: _('DNS.LA API ID'), required: true },
				{ env: 'LA_Sk', label: _('DNS.LA API Secret'), secret: true, required: true }
			] },
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'LA_Token', label: _('DNS.LA API Token'), secret: true, required: true }
			] }
		]
	},
	dns_namecom: {
		title: _('Name.com'),
		modes: [
			{ id: 'api-token', title: _('API Token'), fields: [
				{ env: 'Namecom_Username', label: _('Name.com Username'), required: true },
				{ env: 'Namecom_Token', label: _('Name.com API Token'), secret: true, required: true }
			] }
		]
	},
	dns_namesilo: {
		title: _('NameSilo'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'Namesilo_Key', label: _('NameSilo API Key'), secret: true, required: true }
			] }
		]
	},
	dns_nsone: {
		title: _('IBM NS1 Connect'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'NS1_Key', label: _('NS1 API Key'), secret: true, required: true }
			] }
		]
	},
	dns_porkbun: {
		title: _('Porkbun'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'PORKBUN_API_KEY', label: _('Porkbun API Key'), secret: true, required: true },
				{ env: 'PORKBUN_SECRET_API_KEY', label: _('Porkbun Secret API Key'), secret: true, required: true }
			] }
		]
	},
	dns_volcengine: {
		title: _('Volcengine DNS'),
		modes: [
			{ id: 'access-key', title: _('Access Key'), fields: [
				{ env: 'Volcengine_ACCESS_KEY_ID', label: _('Volcengine Access Key ID'), required: true },
				{ env: 'Volcengine_SECRET_ACCESS_KEY', label: _('Volcengine Secret Access Key'), secret: true, required: true },
				{ env: 'Volcengine_SESSION_TOKEN', label: _('Volcengine Session Token'), secret: true }
			] }
		]
	},
	dns_spaceship: {
		title: _('Spaceship'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'SPACESHIP_API_KEY', label: _('Spaceship API Key'), secret: true, required: true },
				{ env: 'SPACESHIP_API_SECRET', label: _('Spaceship API Secret'), secret: true, required: true },
				{ env: 'SPACESHIP_ROOT_DOMAIN', label: _('Spaceship root domain') }
			] }
		]
	},
	dns_vercel: {
		title: _('Vercel'),
		modes: [
			{ id: 'api-token', title: _('API Token'), fields: [
				{ env: 'VERCEL_TOKEN', label: _('Vercel API Token'), secret: true, required: true }
			] }
		]
	},
	dns_linode_v4: {
		title: _('Linode'),
		modes: [
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'LINODE_V4_API_KEY', label: _('Linode API Key'), secret: true, required: true }
			] }
		]
	},
	dns_dgon: {
		title: _('DigitalOcean'),
		modes: [
			{ id: 'token', title: _('Token'), fields: [
				{ env: 'DO_API_KEY', label: _('DigitalOcean API Token'), secret: true, required: true }
			] }
		]
	},
	dns_gcloud: {
		title: _('Google Cloud DNS'),
		modes: [
			{ id: 'gcloud', title: _('gcloud'), fields: [
				{ env: 'CLOUDSDK_ACTIVE_CONFIG_NAME', label: _('gcloud active config') }
			] }
		]
	},
	dns_zonomi: {
		title: _('Zonomi'),
		modes: [
			{ id: 'api-key', title: _('API Key'), fields: [
				{ env: 'ZM_Key', label: _('Zonomi API Key'), secret: true, required: true }
			] }
		]
	}
};

const OFFICIAL_DNS_API_CANDIDATES = [
	'dns_1984hosting', 'dns_acmedns', 'dns_acmeproxy', 'dns_active24', 'dns_ad', 'dns_ali', 'dns_alviy', 'dns_anx',
	'dns_artfiles', 'dns_arubabusiness', 'dns_arvan', 'dns_aurora', 'dns_autodns', 'dns_aws', 'dns_azion', 'dns_azure',
	'dns_baidu', 'dns_beget', 'dns_bh', 'dns_bhosted', 'dns_bookmyname', 'dns_bunny', 'dns_calrissia', 'dns_cdmon',
	'dns_cf', 'dns_clouddns', 'dns_cloudns', 'dns_cn', 'dns_conoha', 'dns_constellix', 'dns_cpanel', 'dns_cpanel_uapi',
	'dns_curanet', 'dns_cyon', 'dns_czechia', 'dns_da', 'dns_ddnss', 'dns_desec', 'dns_df', 'dns_dgon',
	'dns_dnsexit', 'dns_dnshome', 'dns_dnsimple', 'dns_dnsservices', 'dns_doapi', 'dns_domeneshop', 'dns_dp', 'dns_dpi',
	'dns_dreamhost', 'dns_duckdns', 'dns_durabledns', 'dns_dyn', 'dns_dynu', 'dns_dynv6', 'dns_easydns', 'dns_edgecenter',
	'dns_edgedns', 'dns_efficientip', 'dns_eurodns', 'dns_euserv', 'dns_exoscale', 'dns_firestorm', 'dns_fornex', 'dns_freedns',
	'dns_freemyip', 'dns_gandi_livedns', 'dns_gcloud', 'dns_gcore', 'dns_gd', 'dns_geoscaling', 'dns_glesys', 'dns_gname',
	'dns_googledomains', 'dns_he', 'dns_he_ddns', 'dns_hetznercloud', 'dns_hexonet', 'dns_hostingde', 'dns_hostup', 'dns_huaweicloud',
	'dns_infoblox', 'dns_infoblox_uddi', 'dns_infomaniak', 'dns_internetbs', 'dns_inwx', 'dns_ionos', 'dns_ionos_cloud', 'dns_ipprojects',
	'dns_ipv64', 'dns_ispconfig', 'dns_jd', 'dns_joker', 'dns_kappernet', 'dns_kas', 'dns_kinghost', 'dns_knot',
	'dns_la', 'dns_laodc', 'dns_leaseweb', 'dns_level27', 'dns_lexicon', 'dns_limacity', 'dns_linode', 'dns_linode_v4',
	'dns_loopia', 'dns_lua', 'dns_maradns', 'dns_me', 'dns_mgwm', 'dns_miab', 'dns_mijnhost', 'dns_misaka',
	'dns_muumuu', 'dns_myapi', 'dns_mydevil', 'dns_mydnsjp', 'dns_mythic_beasts', 'dns_namecheap', 'dns_namecom', 'dns_namesilo',
	'dns_nanelo', 'dns_nederhost', 'dns_neodigit', 'dns_netcup', 'dns_netlify', 'dns_nic', 'dns_njalla', 'dns_nm',
	'dns_nsd', 'dns_nsone', 'dns_nsupdate', 'dns_nw', 'dns_oci', 'dns_omglol', 'dns_one', 'dns_online',
	'dns_openprovider', 'dns_openprovider_rest', 'dns_openstack', 'dns_opnsense', 'dns_opusdns', 'dns_ovh', 'dns_pdns', 'dns_pleskxml',
	'dns_pointhq', 'dns_porkbun', 'dns_poweradmin', 'dns_qc', 'dns_rackcorp', 'dns_rackspace', 'dns_rage4', 'dns_rcode0',
	'dns_regru', 'dns_scaleway', 'dns_schlundtech', 'dns_selectel', 'dns_selfhost', 'dns_servercow', 'dns_simply', 'dns_sitehost',
	'dns_sotoon', 'dns_spaceship', 'dns_subreg', 'dns_technitium', 'dns_tele3', 'dns_tencent', 'dns_timeweb', 'dns_transip',
	'dns_udr', 'dns_ultra', 'dns_unoeuro', 'dns_variomedia', 'dns_veesp', 'dns_vercel', 'dns_virakcloud', 'dns_volcengine',
	'dns_vscale', 'dns_vultr', 'dns_websupport', 'dns_wedos', 'dns_west_cn', 'dns_world4you', 'dns_yandex360', 'dns_yc',
	'dns_zilore', 'dns_zone', 'dns_zoneedit', 'dns_zonomi'
];

const DNS_PROVIDER_OPTIONS = Object.keys(DNS_PROVIDER_TEMPLATES).map(function(dnsApi) {
	return [ dnsApi, DNS_PROVIDER_TEMPLATES[dnsApi].title + ' (' + dnsApi + ')' ];
}).concat([[ 'custom', _('Custom dns_xxx') ]]);

function mergeConfig(config) {
	config = config || {};
	config.global = Object.assign({}, DEFAULT_CONFIG.global, config.global || {});
	delete config.global.testMode;
	config.accountProfiles = Array.isArray(config.accountProfiles) ? config.accountProfiles : [];
	config.issueProfiles = Array.isArray(config.issueProfiles) ? config.issueProfiles : [];
	config.issueProfiles.forEach(function(profile) {
		if (!profile.testModeOverride || profile.testModeOverride === 'inherit-global-test-mode')
			profile.testModeOverride = 'force-real-mode';
	});
	config.deployProfiles = Array.isArray(config.deployProfiles) ? config.deployProfiles : [];
	return config;
}

function id(prefix) {
	return prefix + '-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 100000).toString(36);
}

function field(label, child) {
	return E('label', { 'class': 'acmesh-field' }, [
		E('span', {}, label),
		child
	]);
}

function input(value, placeholder, type) {
	return E('input', { 'class': 'cbi-input-text', 'type': type || 'text', 'value': value || '', 'placeholder': placeholder || '' });
}

function select(value, options) {
	return E('select', { 'class': 'cbi-input-select' }, options.map(function(option) {
		return E('option', { 'value': option[0], 'selected': option[0] === value ? 'selected' : null }, option[1]);
	}));
}

function overlayEnabled(value) {
	return !ignoredValue(value);
}

function defaultOverlaySelect(enabled) {
	return select(enabled ? 'override' : 'inherit-default', [
		[ 'inherit-default', _('Inherit default') ],
		[ 'override', _('Override') ]
	]);
}

function terminal(text) {
	return E('pre', { 'class': 'acmesh-terminal' }, text || '');
}

function renderTable(headers, rows, emptyText) {
	if (!rows.length)
		return E('div', { 'class': 'acmesh-empty' }, emptyText || _('No entries'));
	return E('table', { 'class': 'table acmesh-table' }, [
		E('thead', {}, E('tr', {}, headers.map(function(header) {
			return E('th', {}, header);
		}))),
		E('tbody', {}, rows.map(function(row) {
			return E('tr', {}, row.map(function(cell) {
				return E('td', {}, cell);
			}));
		}))
	]);
}

function effectiveSummary(rows) {
	const node = E('div', { 'class': 'acmesh-effective-strip acmesh-span-all' }, [
		E('h4', { 'class': 'acmesh-effective-label' }, _('Effective configuration')),
		E('dl', {}, [])
	]);
	node.update = function(nextRows) {
		setEffectiveSummaryRows(node, nextRows);
	};
	node.update(rows);
	return node;
}

function setEffectiveSummaryRows(node, rows) {
	const dl = node.querySelector('dl');
	const summaryNodes = [];
	rows.forEach(function(row) {
		summaryNodes.push(E('dt', {}, row[0]));
		summaryNodes.push(E('dd', {}, row[1] || '-'));
	});
	dl.textContent = '';
	summaryNodes.forEach(function(child) {
		dl.appendChild(child);
	});
}

function providerTemplate(dnsApi) {
	return DNS_PROVIDER_TEMPLATES[dnsApi || 'dns_cf'];
}

function providerMode(dnsApi, modeId) {
	const template = providerTemplate(dnsApi);
	if (!template)
		return null;
	return template.modes.filter(function(mode) { return mode.id === modeId; })[0] || template.modes[0];
}

function credentialModeLabel(profile) {
	const mode = providerMode(profile.dnsApi, profile.credentialMode);
	return mode ? mode.title : _('Custom');
}

function ignoredValue(value) {
	value = (value == null ? '' : String(value)).trim();
	return !value || value === '-' || value.toLowerCase() === 'none' || value.toLowerCase() === 'null';
}

function credentialEnvLooksSecret(env) {
	return /(Token|TOKEN|token|Key|KEY|key|Secret|SECRET|secret|Password|PASSWORD|password|Credential|CREDENTIAL|credential|Authorization|AUTHORIZATION|authorization|_SK$|_Sk$|_sk$)/.test(env || '');
}

function credentialArgs(profile) {
	const credentials = profile.credentials || {};
	const mode = providerMode(profile.dnsApi, profile.credentialMode);
	const fields = mode ? mode.fields : Object.keys(credentials).map(function(env) { return { env: env }; });
	return fields.map(function(field) {
		const value = credentials[field.env];
		return ignoredValue(value) ? '' : field.env + '=' + value;
	}).filter(function(value) { return !!value; });
}

function validateIssueProfile(profile) {
	if ((profile.validationMethod || 'dns') !== 'dns')
		return '';

	const mode = providerMode(profile.dnsApi, profile.credentialMode);
	if (!mode)
		return '';

	const credentials = profile.credentials || {};
	const missing = mode.fields.filter(function(field) {
		return field.required && ignoredValue(credentials[field.env]);
	}).map(function(field) {
		return field.label;
	});

	(mode.anyOf || []).forEach(function(group) {
		const ok = group.envs.some(function(env) { return !ignoredValue(credentials[env]); });
		if (!ok)
			missing.push(group.label);
	});

	return missing.length ? _('Missing DNS credentials') + ': ' + missing.join(', ') : '';
}

function keyTypeFromAcme(value) {
	switch (value || '') {
	case 'ec-256':
	case 'ec256':
		return 'ec256';
	case 'ec-384':
	case 'ec384':
		return 'ec384';
	case 'ec-521':
	case 'ec521':
		return 'ec521';
	case '4096':
		return 'rsa4096';
	case '8192':
		return 'rsa8192';
	case '3072':
		return 'rsa3072';
	case '2048':
		return 'rsa2048';
	default:
		return (value || '').indexOf('ec') === 0 ? 'ec256' : 'rsa2048';
	}
}

function caFromAcmeApi(value) {
	value = value || '';
	if (value.indexOf('acme-staging-v02.api.letsencrypt.org') >= 0)
		return 'letsencrypt_staging';
	if (value.indexOf('acme-v02.api.letsencrypt.org') >= 0)
		return 'letsencrypt';
	if (value.indexOf('zerossl') >= 0)
		return 'zerossl';
	if (value.indexOf('pki.goog') >= 0)
		return 'google';
	return 'letsencrypt';
}

function importedCredentialMode(dnsApi, rawVars) {
	const template = providerTemplate(dnsApi);
	if (!template)
		return 'custom';
	const matched = template.modes.filter(function(mode) {
		return mode.fields.some(function(field) { return rawVars[field.env]; });
	})[0];
	return matched ? matched.id : template.modes[0].id;
}

return view.extend({
	load: function() {
		return Promise.all([ acmeshApi.write('config_get', {}).then(requireConfig), acmeshApi.read('core_status'), acmeshApi.read('status'), acmeshApi.read('authorization_list') ]);
	},

	render: function(results) {
		let config = mergeConfig(results[0]);
		const core = results[1] || {};
		let scannedCertificates = (results[2] && results[2].certificates) || [];
		let authorizationRecords = (results[3] && results[3].records) || [];
		const output = terminal('');
		let activeTab = 'accounts';
		let editState = null;

		const saveConfig = function() {
			return acmeshApi.write('config_save', config).then(function(res) {
				if (!res.ok)
					ui.addNotification(null, E('p', {}, res.error || _('Unable to save config')), 'danger');
				return res;
			});
		};

		const refresh = function() {
			return acmeshApi.write('config_get', {}).then(requireConfig).then(function(next) {
				config = mergeConfig(next);
				renderBody();
			});
		};

		const deleteProfile = function(profileType, profileId) {
			return authorization.run('profile_delete', { profileType: profileType, profileId: profileId }, { destructive: true }).then(function(result) {
				if (result && result.ok)
					return refresh();
				if (result && !result.cancelled)
					ui.addNotification(null, E('p', {}, result.error || _('Unable to delete profile')), 'danger');
				return result;
			});
		};

		const body = E('div', { 'class': 'acmesh-body' });

		const setEdit = function(kind, id) {
			editState = kind ? { kind: kind, id: id || '' } : null;
			renderBody();
			return Promise.resolve();
		};

		const setTab = function(tab) {
			activeTab = tab;
			editState = null;
			renderBody();
			return Promise.resolve();
		};

		const showTaskResult = function(taskId, status, logText) {
			const summary = summarizeTaskLog(logText || '');
			status.logText = logText || '';
			const lines = [
				'Task: ' + taskId,
				'Status: ' + (status.status || '-'),
				'Stage: ' + (status.stage || '-'),
				'Exit: ' + (status.exitCode == null ? '-' : status.exitCode),
				''
			];
			if (summary)
				lines.push(_('Summary') + ': ' + summary, '');
			lines.push(logText || '');
			output.textContent = lines.join('\n');
			return status;
		};

		const summarizeTaskLog = function(logText) {
			if (logText.indexOf('invalidContact') >= 0 && logText.indexOf('forbidden domain') >= 0)
				return _('The CA rejected the account email. Replace example.com with a real mailbox in the account profile or defaults.');
			if (logText.indexOf('Error adding TXT record') >= 0 && logText.indexOf('invalid domain') >= 0)
				return _('The DNS provider rejected the TXT record. Check that the domain belongs to this DNS account and that the selected DNS API credentials match the provider.');
			if (logText.indexOf('Error adding TXT record') >= 0)
				return _('The DNS provider failed to create the ACME TXT record. Recheck DNS API credentials, zone ownership, and provider-specific permissions.');
			if (logText.indexOf('Please install openssl first') >= 0 || logText.indexOf('openssl is required') >= 0)
				return _('OpenSSL is missing on the router. Install openssl-util before installing or upgrading acme.sh.');
			if (logText.indexOf('acme.sh not found') >= 0)
				return _('acme.sh is not installed in the configured ACME home. Install the selected core tag first.');
			if (logText.indexOf('unsupported ca') >= 0)
				return _('The selected CA value is not supported by the backend. Choose a known CA profile or a valid ACME directory URL.');
			if (logText.indexOf('ACMESH_DEPLOY_CONVERTIBLE_SSH_KEY=1') >= 0)
				return _('The SSH private key is in OpenSSH format, but this router is using Dropbear. Convert it temporarily and retry the deployment.');
			if (logText.indexOf('sudo: a password is required') >= 0 || logText.indexOf('sudo: a terminal is required') >= 0)
				return _('Remote sudo requires passwordless sudo. Configure NOPASSWD for the deploy user or deploy as root.');
			return '';
		};

		const fetchTask = function(taskId) {
			return Promise.all([
				acmeshApi.read('task_status', [ taskId ]),
				acmeshApi.read('task_log', [ taskId ])
			]).then(function(results) {
				return showTaskResult(taskId, results[0] || {}, (results[1] && results[1].log) || '');
			});
		};

		const showTask = function(taskId) {
			return new Promise(function(resolve) {
				window.setTimeout(resolve, 900);
			}).then(function() {
				return fetchTask(taskId);
			});
		};

		const waitTask = function(taskId, attempts) {
			attempts = attempts == null ? 80 : attempts;
			return fetchTask(taskId).then(function(status) {
				if (TERMINAL_TASK_STATES.indexOf(status.status) !== -1)
					return status;
				if (attempts <= 0)
					return status;
				return new Promise(function(resolve) {
					window.setTimeout(resolve, 1200);
				}).then(function() {
					return waitTask(taskId, attempts - 1);
				});
			});
		};

		const runTask = function(method, payload, authorizationOptions) {
			output.textContent = _('Creating task') + '...';
			return authorization.run(method, payload, authorizationOptions).then(function(res) {
				if (!res.taskId) {
					output.textContent = res.error || _('Unable to create task');
					return;
				}
				return showTask(res.taskId);
			});
		};

		const runDnsTestProfile = function(profile) {
			if (!profile.domain) {
				output.textContent = _('Domain is required');
				ui.addNotification(null, E('p', {}, _('Domain is required')), 'danger');
				return Promise.resolve();
			}
			return runTask('dns_test', { profileId: profile.id });
		};

		const accountEmail = function(account) {
			return account.accountEmail || config.global.defaultAccountEmail || '';
		};

		const effectiveTestMode = function(profile) {
			if (profile && profile.testModeOverride === 'force-test-mode')
				return true;
			if (profile && profile.testModeOverride === 'force-real-mode')
				return false;
			return false;
		};

		const testModePolicyLabel = function(profile) {
			if (profile && profile.testModeOverride === 'force-test-mode')
				return _('Always Test Mode');
			if (profile && profile.testModeOverride === 'force-real-mode')
				return _('Always Real Mode');
			return _('Always Real Mode');
		};

		const deploySourceLabel = function(profile) {
			switch ((profile && profile.certSource) || 'managed-acme') {
			case 'local-files':
				return _('Local certificate files');
			case 'paste-pem':
				return _('Paste PEM content');
			default:
				return _('Issued certificate');
			}
		};

		const deployTargetLabel = function(profile) {
			if (!profile)
				return '-';
			if ((profile.type || 'local') === 'ssh')
				return (profile.user || 'root') + '@' + (profile.host || '-') + ':' + (profile.port || '22');
			return profile.fullchainFile || '-';
		};

		const deployProfileLabel = function(profile) {
			if (!profile)
				return _('No deploy profile');
			return (profile.name || profile.id) + ' / ' + deploySourceLabel(profile) + ' / ' + deployTargetLabel(profile);
		};

		const deployMetadataLabel = function(profile) {
			if (!profile)
				return '-';
			if (profile.preserveMetadata === true)
				return _('Keep existing owner/group/mode');
			return (profile.owner || _('default owner')) + ':' + (profile.group || _('default group')) + ' / ' + (profile.mode || _('key 0600 / fullchain 0644'));
		};

		const resolveDeployProfile = function(profile) {
			if (!profile)
				return {
					label: _('No deploy profile'),
					target: '-',
					source: '-',
					reload: '-',
					metadata: '-'
				};
			return {
				label: deployProfileLabel(profile),
				target: deployTargetLabel(profile),
				source: deploySourceLabel(profile),
				reload: profile.reloadcmd || '-',
				metadata: deployMetadataLabel(profile)
			};
		};

		const resolveIssueProfile = function(profile) {
			const account = config.accountProfiles.filter(function(item) { return item.id === profile.accountProfileId; })[0] || {};
			const deploy = config.deployProfiles.filter(function(item) { return item.id === profile.deployProfileId; })[0];
			const testMode = effectiveTestMode(profile);
			return {
				account: account,
				deploy: deploy,
				email: accountEmail(account),
				testMode: testMode,
				testModeLabel: testMode ? _('Test') : _('Real'),
				testModeSource: _('Explicit profile policy'),
				deployLabel: resolveDeployProfile(deploy).label,
				accountLabel: account.name || profile.accountProfileId || _('No account profile')
			};
		};

		const validateDeployProfile = function(profile) {
			const missing = [];
			const certSource = profile.certSource || 'managed-acme';
			const deployType = profile.type || 'local';
			if (certSource === 'managed-acme' && !profile.domain)
				missing.push(_('Certificate domain'));
			if (certSource === 'local-files') {
				if (!profile.sourceKeyFile)
					missing.push(_('Source key file'));
				if (!profile.sourceFullchainFile)
					missing.push(_('Source fullchain file'));
			}
			if (certSource === 'paste-pem') {
				if (!profile.keyPem)
					missing.push(_('Private key PEM'));
				if (!profile.fullchainPem)
					missing.push(_('Fullchain PEM'));
			}
			if (!profile.keyFile)
				missing.push(deployType === 'ssh' ? _('Remote key file') : _('Local key file'));
			if (!profile.fullchainFile)
				missing.push(deployType === 'ssh' ? _('Remote fullchain file') : _('Local fullchain file'));
			if (deployType === 'ssh' && !profile.host)
				missing.push(_('SSH host'));
			return missing.length ? _('Missing deploy fields') + ': ' + missing.join(', ') : '';
		};

		const deployPayload = function(profile, options) {
			options = options || {};
			return { profileId: profile.id, allowKeyConvert: !!options.allowKeyConvert };
		};

		const runDeployProfile = function(profile, command, options) {
			options = options || {};
			const validationError = validateDeployProfile(profile);
			if (validationError) {
				output.textContent = validationError;
				ui.addNotification(null, E('p', {}, validationError), 'danger');
				return Promise.resolve();
			}
			return runTask(command === 'deploy-run' ? 'deploy_run' : 'deploy_test', deployPayload(profile, options), { host: profile.host, port: profile.port || 22 }).then(function(status) {
				if (command !== 'deploy-run' || options.allowKeyConvert)
					return status;
				if (!status || status.status !== 'failed' || !status.logText || status.logText.indexOf('ACMESH_DEPLOY_CONVERTIBLE_SSH_KEY=1') < 0)
					return status;
				return runDeployProfile(profile, command, { allowKeyConvert: true });
			});
		};

		const renderConfigMigration = function() {
			const file = E('input', {
				'class': 'cbi-input-file',
				'type': 'file',
				'accept': '.tar.gz,application/gzip,application/x-gzip'
			});
			const includeCertificates = E('input', { 'type': 'checkbox' });
			const summary = E('pre', { 'class': 'acmesh-migration-summary' }, _('No import selected'));
			let importedArchiveBase64 = null;
			let importPreviewId = null;

			const setSummary = function(text, ok) {
				summary.textContent = text;
				summary.classList.toggle('acmesh-ok', !!ok);
				summary.classList.toggle('acmesh-warning', !ok);
			};

			const showMigrationError = function(result, fallback) {
				const message = (result && (result.error || result.message)) || fallback;
				setSummary(message, false);
				ui.addNotification(null, E('p', {}, message), 'danger');
				return result || { ok: false, error: message };
			};

			const arrayBufferToBase64 = function(buffer) {
				const bytes = new Uint8Array(buffer);
				let binary = '';
				for (let offset = 0; offset < bytes.length; offset += 0x8000)
					binary += String.fromCharCode.apply(null, bytes.subarray(offset, Math.min(offset + 0x8000, bytes.length)));
				return btoa(binary);
			};

			const base64ToBlob = function(encoded) {
				const binary = atob(encoded);
				const bytes = new Uint8Array(binary.length);
				for (let index = 0; index < binary.length; index++)
					bytes[index] = binary.charCodeAt(index);
				return new Blob([ bytes ], { type: 'application/gzip' });
			};

			const exportConfig = function() {
				const scope = includeCertificates.checked ? 'migration-archive-with-deployment-certs' : 'migration-archive';
				return authorization.run('secret_export', { scope: scope }).then(function(archive) {
					if (!archive || archive.cancelled)
						return archive;
					if (!archive.ok)
						return showMigrationError(archive, _('Archive export failed'));
					const blob = base64ToBlob(archive.archiveBase64);
					const url = URL.createObjectURL(blob);
					const link = document.createElement('a');
					link.href = url;
					link.download = archive.filename || 'acmesh-console-backup.tar.gz';
					document.body.appendChild(link);
					link.click();
					link.remove();
					URL.revokeObjectURL(url);
					setSummary(_('Exported archive') + ': ' + archive.bytes + ' bytes', true);
					return archive;
				}).catch(function(error) {
					return showMigrationError(error, _('Archive export failed'));
				});
			};

			file.addEventListener('change', function() {
				const selected = file.files && file.files[0];
				if (!selected) {
					importedArchiveBase64 = null;
					importPreviewId = null;
					return;
				}
				if (selected.size > 16 * 1024 * 1024) {
					importedArchiveBase64 = null;
					importPreviewId = null;
					setSummary(_('Migration archive exceeds the 16 MiB limit'), false);
					file.value = '';
					return;
				}
				const reader = new FileReader();
				reader.onload = function() {
					importedArchiveBase64 = arrayBufferToBase64(reader.result);
					importPreviewId = null;
					setSummary(_('Archive selected. Preview it before applying.'), true);
				};
				reader.onerror = function() {
					importedArchiveBase64 = null;
					importPreviewId = null;
					setSummary(_('Unable to read selected archive'), false);
				};
				reader.readAsArrayBuffer(selected);
			});

			const previewImport = function() {
				if (!importedArchiveBase64) {
					setSummary(_('Select a .tar.gz migration archive first'), false);
					return Promise.resolve();
				}
				return authorization.run('import_preview', { archiveBase64: importedArchiveBase64 }).then(function(result) {
					if (!result || !result.ok) {
						if (result && result.cancelled)
							return result;
						return showMigrationError(result, _('Archive preview failed'));
					}
					importPreviewId = result.previewId;
					setSummary(_('Imported archive summary') + '\n' + JSON.stringify(result.summary, null, 2), true);
					return result;
				}).catch(function(error) {
					return showMigrationError(error, _('Archive preview failed'));
				});
			};

			const applyImport = function() {
				const preview = importPreviewId ? Promise.resolve({ ok: true }) : previewImport();
				return preview.then(function(result) {
					if (result && !result.ok)
						return result;
					if (!importPreviewId) {
						setSummary(_('Preview the archive before applying'), false);
						return;
					}
					return authorization.run('import_apply', { previewId: importPreviewId }).then(function(applied) {
						if (applied && applied.ok) {
							ui.addNotification(null, E('p', {}, _('Migration archive imported')), 'info');
							importPreviewId = null;
							return refresh();
						}
						if (applied && applied.cancelled)
							return applied;
						return showMigrationError(applied, _('Migration archive import failed'));
					}).catch(function(error) {
						return showMigrationError(error, _('Migration archive import failed'));
					});
				}).catch(function(error) {
					return showMigrationError(error, _('Migration archive import failed'));
				});
			};

			return E('div', { 'class': 'acmesh-section acmesh-migration' }, [
				E('h3', {}, _('Configuration migration')),
				E('p', { 'class': 'acmesh-warning' }, _('The archive contains sensitive ACME account data and console credentials. Deployment certificates are included only when selected.')),
				E('p', { 'class': 'acmesh-warning' }, _('Do not manually extract migration archives over /. Use this page to preview and restore them safely.')),
				E('div', { 'class': 'acmesh-migration-grid' }, [
					E('div', { 'class': 'acmesh-card' }, [
						E('h4', {}, _('Export configuration')),
						E('p', {}, _('Download a .tar.gz migration archive containing ACME state and console configuration.')),
						E('label', { 'class': 'acmesh-checkbox' }, [ includeCertificates, _('Include deployment certificates') ]),
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, exportConfig) }, _('Export configuration'))
					]),
					E('div', { 'class': 'acmesh-card' }, [
						E('h4', {}, _('Import configuration')),
						field(_('Configuration file'), file),
						E('div', { 'class': 'acmesh-actions' }, [
							E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, previewImport) }, _('Preview import')),
							E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, applyImport) }, _('Restore migration archive'))
						]),
						E('h4', {}, _('Imported configuration summary')),
						summary
					])
				])
			]);
		}.bind(this);

		const refreshAuthorizations = function() {
			return acmeshApi.read('authorization_list').then(function(result) {
				authorizationRecords = (result && result.records) || [];
				renderBody();
			});
		};

		const renderAuthorizationRecords = function() {
			const rows = authorizationRecords.map(function(record) {
				return [
					record.operation || '-',
					(record.subjectType || '-') + ': ' + (record.subjectId || '-'),
					record.fingerprint || '-',
					record.grantedAt || '-',
					record.lastUsedAt || '-',
					String(record.useCount == null ? 0 : record.useCount),
					authorization.badge(record.status),
					E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
						return acmeshApi.write('authorization_revoke', { recordId: record.id }).then(refreshAuthorizations);
					}) }, _('Revoke'))
				];
			}, this);
			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Authorization records')),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
						return acmeshApi.write('authorization_revoke_all', {}).then(refreshAuthorizations);
					}) }, _('Revoke all')),
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, refreshAuthorizations) }, _('Refresh'))
				]),
				renderTable([ _('Operation'), _('Subject'), _('Scope'), _('Granted'), _('Last used'), _('Uses'), _('Status'), _('Actions') ], rows, _('No authorization records'))
			]);
		}.bind(this);

		const renderAccountsList = function() {
			const rows = config.accountProfiles.map(function(account) {
				return [
					account.name || account.id,
					account.ca || 'letsencrypt',
					account.accountEmail || _('inherit default'),
					accountEmail(account),
					E('div', { 'class': 'acmesh-row-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return setEdit('account', account.id);
						}) }, _('Edit')),
						E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
							return deleteProfile('account', account.id);
						}) }, _('Delete'))
					])
				];
			}, this);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Account profiles')),
				renderTable([ _('Name'), _('CA'), _('Email overlay'), _('Effective email'), '' ], rows, _('No account profiles')),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						return setEdit('account', 'new');
					}) }, _('Add'))
				])
			]);
		}.bind(this);

		const renderAccountEdit = function() {
			const existing = config.accountProfiles.filter(function(item) { return item.id === editState.id; })[0] || {};
			const name = input(existing.name || '', 'LE Staging');
			const email = input(existing.accountEmail || '', 'inherit default');
			const emailMode = defaultOverlaySelect(overlayEnabled(existing.accountEmail));
			const ca = select(existing.ca || 'letsencrypt_staging', [
				[ 'letsencrypt', 'Let\'s Encrypt' ],
				[ 'letsencrypt_staging', 'Let\'s Encrypt Staging' ],
				[ 'zerossl', 'ZeroSSL' ],
				[ 'google', 'Google Trust Services' ]
			]);
			const effectiveEmail = function() {
				return emailMode.value === 'override' ? email.value.trim() : (config.global.defaultAccountEmail || '');
			};

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Edit account') + ': ' + (existing.name || _('new'))),
				E('div', { 'class': 'acmesh-edit-form acmesh-edit-grid' }, [
					field(_('Name'), name),
					field(_('CA / environment'), ca),
					field(_('Account email source'), emailMode),
					field(_('Account email overlay'), email),
					effectiveSummary([
						[ _('Resolved account email'), effectiveEmail() || '-' ]
					])
				]),
				E('div', { 'class': 'acmesh-form-actions is-sticky' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return setEdit(null);
					}) }, _('Ignore')),
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						const next = {
							id: existing.id || id('acc'),
							name: name.value.trim() || 'Account',
							ca: ca.value,
							accountEmail: emailMode.value === 'override' ? email.value.trim() : ''
						};
						config.accountProfiles = config.accountProfiles.filter(function(item) { return item.id !== next.id; }).concat([ next ]);
						return saveConfig().then(function() { return setEdit(null); }).then(refresh);
					}) }, _('Save account'))
				])
			]);
		}.bind(this);

		const runIssueProfile = function(profile, deployAfterIssue) {
			const resolved = resolveIssueProfile(profile);
			const account = resolved.account;
			const deploy = resolved.deploy;
			const validationError = validateIssueProfile(profile);
			if (validationError) {
				output.textContent = validationError;
				ui.addNotification(null, E('p', {}, validationError), 'danger');
				return Promise.resolve();
			}
			const testMode = resolved.testMode;
			const email = resolved.email;
			if (!testMode && !email) {
				const message = _('Account email is required for real mode');
				output.textContent = message;
				ui.addNotification(null, E('p', {}, message), 'danger');
				return Promise.resolve();
			}
			if (deployAfterIssue) {
				if (!deploy) {
					const message = _('No deploy profile');
					output.textContent = message;
					ui.addNotification(null, E('p', {}, message), 'danger');
					return Promise.resolve();
				}
				const deployPreview = Object.assign({}, deploy);
				if ((deployPreview.certSource || 'managed-acme') === 'managed-acme' && !deployPreview.domain)
					deployPreview.domain = profile.domain;
				deployPreview.keyType = profile.keyType || deployPreview.keyType || 'ec256';
				const deployError = validateDeployProfile(deployPreview);
				if (deployError) {
					output.textContent = deployError;
					ui.addNotification(null, E('p', {}, deployError), 'danger');
					return Promise.resolve();
				}
			}
			output.textContent = _('Creating task') + '...';
			const issueHostKeyOptions = deployAfterIssue && deploy && (deploy.type || 'local') === 'ssh' ? {
				host: deploy.host || '',
				port: deploy.port || 22
			} : {};
			const operation = deployAfterIssue ? 'issue-deploy' : 'issue';
			const rpcMethod = deployAfterIssue ? 'issue_deploy' : operation;
			return authorization.run(rpcMethod, { profileId: profile.id }, issueHostKeyOptions).then(function(res) {
				if (!res.taskId) {
					output.textContent = res.error || _('Unable to create task');
					return null;
				}
				return waitTask(res.taskId);
			});
		};

		const importCredentialsFromRaw = function(dnsApi, modeId, rawVars) {
			const credentials = {};
			const mode = providerMode(dnsApi, modeId);
			const fields = mode ? mode.fields : [];
			fields.forEach(function(field) {
				const value = rawVars[field.env];
				if (!value || value === '***')
					return;
				credentials[field.env] = value;
			});
			return credentials;
		};

		const ensureImportedAccount = function(ca) {
			let account = config.accountProfiles.filter(function(item) {
				return item.ca === ca && !item.accountEmail;
			})[0];
			if (account)
				return account.id;
			account = {
				id: id('acc-import'),
				name: _('Imported') + ' ' + ca,
				ca: ca,
				accountEmail: ''
			};
			config.accountProfiles.push(account);
			return account.id;
		};

		const importHistoryProfiles = function() {
			return acmeshApi.read('status').then(function(status) {
				scannedCertificates = (status && status.certificates) || [];
				let added = 0;
				scannedCertificates.forEach(function(cert) {
					const rawVars = cert.rawVars || {};
					const domain = rawVars.Le_Domain || cert.mainDomain || '';
					if (!domain)
						return;
					const keyType = keyTypeFromAcme(rawVars.Le_Keylength || cert.keyType);
					const exists = config.issueProfiles.some(function(profile) {
						return profile.domain === domain && profile.keyType === keyType;
					});
					if (exists)
						return;
					const webroot = rawVars.Le_Webroot || '';
					const validationMethod = webroot.indexOf('dns_') === 0 ? 'dns' : (webroot === 'no' || !webroot ? 'dns' : 'webroot');
					const dnsApi = validationMethod === 'dns' ? (webroot.indexOf('dns_') === 0 ? webroot : 'dns_cf') : 'dns_cf';
					const credentialMode = importedCredentialMode(dnsApi, rawVars);
					const ca = caFromAcmeApi(rawVars.Le_API || '');
					config.issueProfiles.push({
						id: id('issue-import'),
						name: _('Imported') + ' ' + domain,
						domain: domain,
						accountProfileId: ensureImportedAccount(ca),
						deployProfileId: '',
						keyType: keyType,
						validationMethod: validationMethod,
						testModeOverride: 'force-real-mode',
						dnsApi: dnsApi,
						credentialMode: credentialMode,
						credentials: importCredentialsFromRaw(dnsApi, credentialMode, rawVars)
					});
					added++;
				});
				return saveConfig().then(function() {
					output.textContent = _('Imported issue profiles') + ': ' + added;
					return refresh();
				});
			});
		};

		const renderIssueList = function() {
			const rows = config.issueProfiles.map(function(profile) {
				const resolved = resolveIssueProfile(profile);
				const dnsError = validateIssueProfile(profile);
				const dnsTitle = providerTemplate(profile.dnsApi) ? providerTemplate(profile.dnsApi).title : (profile.dnsApi || 'dns_cf');
				return [
					profile.name || profile.domain || profile.id,
					profile.domain || '-',
					resolved.accountLabel,
					resolved.deploy ? resolved.deployLabel : '-',
					(profile.validationMethod || 'dns') + ' / ' + dnsTitle,
					E('span', { 'class': dnsError ? 'acmesh-warning' : 'acmesh-ok' }, dnsError || testModePolicyLabel(profile)),
					E('div', { 'class': 'acmesh-row-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return runIssueProfile(profile, false);
						}) }, _('Issue')),
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return runIssueProfile(profile, true);
						}) }, _('Issue and deploy')),
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return runDnsTestProfile(profile);
						}) }, _('DNS Test')),
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return setEdit('issue', profile.id);
						}) }, _('Edit')),
						E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
							return deleteProfile('issue', profile.id);
						}) }, _('Delete'))
					])
				];
			}, this);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Issue profiles')),
				renderTable([ _('Name'), _('Domain'), _('Account'), _('Deploy'), _('Validation'), _('Status'), '' ], rows, _('No issue profiles')),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						return setEdit('issue', 'new');
					}) }, _('Add')),
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, importHistoryProfiles) }, _('Import history'))
				])
			]);
		}.bind(this);

		const renderIssueEdit = function() {
			const existing = config.issueProfiles.filter(function(item) { return item.id === editState.id; })[0] || {};
			const accountOptions = config.accountProfiles.length
				? config.accountProfiles.map(function(account) { return [ account.id, account.name || account.id ]; })
				: [[ '', _('No account profile') ]];
			const deployOptions = [[ '', _('No deploy profile') ]].concat(config.deployProfiles.map(function(deploy) { return [ deploy.id, deployProfileLabel(deploy) ]; }));
			const selectedDnsApi = providerTemplate(existing.dnsApi) ? (existing.dnsApi || 'dns_cf') : 'custom';
			const name = input(existing.name || '', 'Gate staging');
			const domain = input(existing.domain || '', 'gate.example.org');
			const sanList = E('textarea', { 'class': 'cbi-input-text', 'rows': 3, 'placeholder': 'www.example.org\napi.example.org' }, (existing.domains || []).slice(1).join('\n'));
			const challengeAlias = input(existing.challengeAlias || '', '');
			const dnsSleep = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': '0', 'value': existing.dnsSleep == null ? 0 : existing.dnsSleep });
			const keyType = select(existing.keyType || 'ec256', [[ 'ec256', 'ECC P-256' ], [ 'ec384', 'ECC P-384' ], [ 'ec521', 'ECC P-521' ], [ 'rsa2048', 'RSA 2048' ], [ 'rsa3072', 'RSA 3072' ], [ 'rsa4096', 'RSA 4096' ], [ 'rsa8192', 'RSA 8192' ]]);
			const account = select(existing.accountProfileId || accountOptions[0][0], accountOptions);
			const deploy = select(existing.deployProfileId || '', deployOptions);
			const validation = select(existing.validationMethod || 'dns', [[ 'dns', 'DNS-01' ], [ 'webroot', 'HTTP-01 Webroot' ], [ 'standalone', 'HTTP-01 Standalone' ], [ 'alpn', 'TLS-ALPN-01' ]]);
			const testPolicy = select(existing.testModeOverride || 'force-real-mode', [[ 'force-test-mode', _('Always Test Mode') ], [ 'force-real-mode', _('Always Real Mode') ]]);
			const dnsApi = select(selectedDnsApi, DNS_PROVIDER_OPTIONS);
			const customDnsApi = input(selectedDnsApi === 'custom' ? (existing.dnsApi || '') : '', 'dns_xxx');
			const customDnsFilter = input('', 'cloudflare / aliyun / dns_cf');
			const customDnsCandidate = select('', [[ '', _('Select official DNS API') ]]);
			const credentialMode = select(existing.credentialMode || 'token', [[ existing.credentialMode || 'token', existing.credentialMode || _('Token') ]]);
			const customCredentialLines = function(credentials) {
				return Object.keys(credentials || {}).sort().map(function(env) {
					const value = credentials[env] || '';
					return env + '=' + (credentialEnvLooksSecret(env) && value ? SECRET_PLACEHOLDER : value);
				}).join('\n');
			};
			const customCredentials = E('textarea', {
				'class': 'cbi-input-text acmesh-custom-credentials',
				'placeholder': 'CF_Token=...\nCF_Zone_ID=...\nCF_Account_ID=...',
				'rows': 7
			}, selectedDnsApi === 'custom' ? customCredentialLines(existing.credentials || {}) : '');
			const customDnsField = field(_('Custom DNS API'), customDnsApi);
			const customDnsFilterField = field(_('Official DNS API filter'), customDnsFilter);
			const customDnsCandidateField = field(_('Official DNS API candidates'), customDnsCandidate);
			const credentialModeField = field(_('Credential mode'), credentialMode);
			const customCredentialsField = field(_('Custom credentials'), customCredentials);
			const credentialBox = E('div', { 'class': 'acmesh-credential-box' });

			const fillOptions = function(node, options, selected) {
				node.innerHTML = '';
				options.forEach(function(option) {
					node.appendChild(E('option', { 'value': option[0], 'selected': option[0] === selected ? 'selected' : null }, option[1]));
				});
			};

			const renderOfficialDnsCandidates = function() {
				const query = customDnsFilter.value.trim().toLowerCase();
				let candidates = OFFICIAL_DNS_API_CANDIDATES.filter(function(item) {
					return !query || item.toLowerCase().indexOf(query) >= 0;
				});
				if (customDnsApi.value && candidates.indexOf(customDnsApi.value) < 0)
					candidates = [ customDnsApi.value ].concat(candidates);
				candidates = candidates.slice(0, 80);
				fillOptions(customDnsCandidate, [[ '', _('Select official DNS API') ]].concat(candidates.map(function(item) {
					return [ item, item ];
				})), customDnsApi.value);
			};

			const renderCredentialFields = function() {
				if (validation.value !== 'dns') {
					customDnsField.style.display = 'none';
					customDnsFilterField.style.display = 'none';
					customDnsCandidateField.style.display = 'none';
					customCredentialsField.style.display = 'none';
					credentialModeField.style.display = 'none';
					credentialBox.style.display = 'none';
					credentialBox.innerHTML = '';
					return;
				}
				const customProvider = dnsApi.value === 'custom';
				const template = providerTemplate(dnsApi.value);
				const selectedMode = template ? providerMode(dnsApi.value, credentialMode.value) : null;
				customDnsField.style.display = customProvider ? '' : 'none';
				customDnsFilterField.style.display = customProvider ? '' : 'none';
				customDnsCandidateField.style.display = customProvider ? '' : 'none';
				customCredentialsField.style.display = customProvider ? '' : 'none';
				credentialModeField.style.display = !customProvider && template && template.modes.length > 1 ? '' : 'none';
				credentialBox.style.display = !customProvider && template ? '' : 'none';
				credentialBox.innerHTML = '';
				if (!template || customProvider)
					return;
				fillOptions(credentialMode, template.modes.map(function(mode) { return [ mode.id, mode.title ]; }), selectedMode.id);
				selectedMode.fields.forEach(function(item) {
					const credentials = existing.credentials || {};
					const savedValue = credentials[item.env] || '';
					const usePlaceholder = item.secret && !!savedValue;
					credentialBox.appendChild(field(item.label, E('input', {
						'class': 'cbi-input-text',
						'type': item.secret ? 'password' : 'text',
						'value': usePlaceholder ? SECRET_PLACEHOLDER : savedValue,
						'placeholder': item.env,
						'data-acmesh-env': item.env,
						'data-acmesh-secret-placeholder': usePlaceholder ? '1' : null
					})));
				});
			};

			const readCredentials = function() {
				const credentials = {};
				if (dnsApi.value === 'custom') {
					customCredentials.value.split(/\r?\n/).forEach(function(line) {
						line = line.trim();
						if (!line || line.charAt(0) === '#')
							return;
						const pos = line.indexOf('=');
						if (pos <= 0)
							return;
						const env = line.slice(0, pos).trim();
						const value = line.slice(pos + 1).trim();
						if (!env || /[^A-Za-z0-9_]/.test(env) || ignoredValue(value))
							return;
						if (credentialEnvLooksSecret(env) && value === SECRET_PLACEHOLDER && existing.credentials && existing.credentials[env])
							credentials[env] = existing.credentials[env];
						else
							credentials[env] = value;
					});
					return credentials;
				}
				Array.prototype.forEach.call(credentialBox.querySelectorAll('[data-acmesh-env]'), function(node) {
					const env = node.getAttribute('data-acmesh-env');
					const value = node.value.trim();
					if (node.getAttribute('data-acmesh-secret-placeholder') === '1' && value === SECRET_PLACEHOLDER && existing.credentials && existing.credentials[env])
						credentials[env] = existing.credentials[env];
					else if (!ignoredValue(value))
						credentials[env] = value;
				});
				return credentials;
			};

			const buildProfile = function() {
				const primary = domain.value.trim().toLowerCase();
				const domains = [ primary ];
				sanList.value.split(/[\s,]+/).forEach(function(item) {
					item = item.trim().toLowerCase();
					if (item && domains.indexOf(item) < 0)
						domains.push(item);
				});
				return {
					id: existing.id || id('issue'),
					name: name.value.trim() || domain.value.trim(),
					domain: primary,
					domains: domains,
					accountProfileId: account.value,
					deployProfileId: deploy.value,
					keyType: keyType.value,
					validationMethod: validation.value,
					testModeOverride: testPolicy.value,
					dnsApi: dnsApi.value === 'custom' ? (customDnsApi.value.trim() || 'dns_cf') : dnsApi.value,
					credentialMode: dnsApi.value === 'custom' ? 'custom' : credentialMode.value,
					challengeAlias: challengeAlias.value.trim(),
					dnsSleep: Math.max(0, parseInt(dnsSleep.value || '0', 10) || 0),
					credentials: readCredentials()
				};
			};

			const resolvedPreview = resolveIssueProfile(buildProfile());

			dnsApi.addEventListener('change', renderCredentialFields);
			customDnsFilter.addEventListener('input', renderOfficialDnsCandidates);
			customDnsApi.addEventListener('input', renderOfficialDnsCandidates);
			customDnsCandidate.addEventListener('change', function() {
				if (customDnsCandidate.value)
					customDnsApi.value = customDnsCandidate.value;
			});
			credentialMode.addEventListener('change', renderCredentialFields);
			validation.addEventListener('change', renderCredentialFields);
			renderOfficialDnsCandidates();
			renderCredentialFields();

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Edit issue profile') + ': ' + (existing.name || existing.domain || _('new'))),
				E('div', { 'class': 'acmesh-edit-form acmesh-edit-grid acmesh-edit-form-wide' }, [
					field(_('Name'), name),
					field(_('Domain'), domain),
					field(_('SAN list'), sanList),
					field(_('Account profile'), account),
					field(_('Deploy profile'), deploy),
					field(_('Key type'), keyType),
					field(_('Validation'), validation),
					field(_('Test mode policy'), testPolicy),
					effectiveSummary([
						[ _('Resolved account email'), resolvedPreview.email || '-' ],
						[ _('Resolved test mode'), resolvedPreview.testModeLabel + ' / ' + resolvedPreview.testModeSource ],
						[ _('Resolved deploy profile'), resolvedPreview.deploy ? resolvedPreview.deployLabel : _('No deploy profile') ]
					]),
					field(_('DNS provider'), dnsApi),
					field(_('DNS challenge alias (optional)'), challengeAlias),
					field(_('DNS propagation delay (seconds)'), dnsSleep),
					customDnsField,
					customDnsFilterField,
					customDnsCandidateField,
					credentialModeField,
					customCredentialsField,
					credentialBox
				]),
				E('div', { 'class': 'acmesh-form-actions is-sticky' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return setEdit(null);
					}) }, _('Ignore')),
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return runDnsTestProfile(buildProfile());
					}) }, _('DNS Test')),
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						const profile = buildProfile();
						const validationError = validateIssueProfile(profile);
						if (!profile.domain) {
							output.textContent = _('Domain is required');
							ui.addNotification(null, E('p', {}, _('Domain is required')), 'danger');
							return Promise.resolve();
						}
						if (validationError) {
							output.textContent = validationError;
							ui.addNotification(null, E('p', {}, validationError), 'danger');
							return Promise.resolve();
						}
						config.issueProfiles = config.issueProfiles.filter(function(item) { return item.id !== profile.id; }).concat([ profile ]);
						return saveConfig().then(function() { return setEdit(null); }).then(refresh);
					}) }, _('Save issue profile'))
				])
			]);
		}.bind(this);

		const renderDeployList = function() {
			const rows = config.deployProfiles.map(function(profile) {
				return [
					profile.name || profile.id,
					profile.type || 'local',
					deploySourceLabel(profile),
					deployTargetLabel(profile),
					profile.reloadcmd || '-',
					E('div', { 'class': 'acmesh-row-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return runDeployProfile(profile, 'deploy-run');
						}) }, _('Deploy')),
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return runDeployProfile(profile);
						}) }, _('Test')),
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return setEdit('deploy', profile.id);
						}) }, _('Edit')),
						E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
							return deleteProfile('deploy', profile.id);
						}) }, _('Delete'))
					])
				];
			}, this);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Deploy profiles')),
				renderTable([ _('Name'), _('Type'), _('Certificate source'), _('Target'), _('Reload command'), '' ], rows, _('No deploy profiles')),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						return setEdit('deploy', 'new');
					}) }, _('Add'))
				])
			]);
		}.bind(this);

		const renderDeployEdit = function() {
			const existing = config.deployProfiles.filter(function(item) { return item.id === editState.id; })[0] || {};
			const name = input(existing.name || '', 'Local nginx');
			const type = select(existing.type || 'local', [[ 'local', _('Local install') ], [ 'ssh', _('Remote SSH') ]]);
			const certSource = select(existing.certSource || 'managed-acme', [
				[ 'managed-acme', _('Use issued certificate') ],
				[ 'local-files', _('Use local certificate files') ],
				[ 'paste-pem', _('Paste PEM content') ]
			]);
			const keyType = select(existing.keyType || 'ec256', [[ 'ec256', 'ECC P-256' ], [ 'ec384', 'ECC P-384' ], [ 'ec521', 'ECC P-521' ], [ 'rsa2048', 'RSA 2048' ], [ 'rsa3072', 'RSA 3072' ], [ 'rsa4096', 'RSA 4096' ], [ 'rsa8192', 'RSA 8192' ]]);
			const domain = input(existing.domain || '', 'gate.example.org');
			const host = input(existing.host || '', '10.0.0.10');
			const user = input(existing.user || 'root', 'root');
			const port = input(existing.port || '22', '22');
			const sshKey = input(existing.sshKey || '/etc/acmesh-console/ssh/id_ed25519', '/etc/acmesh-console/ssh/id_ed25519');
			const sourceKeyFile = input(existing.sourceKeyFile || '', '/etc/acme/gate.example.org_ecc/gate.example.org.key');
			const sourceFullchain = input(existing.sourceFullchainFile || '', '/etc/acme/gate.example.org_ecc/fullchain.cer');
			const keyPem = E('textarea', { 'class': 'cbi-input-text acmesh-pem-input', 'placeholder': '-----BEGIN PRIVATE KEY-----', 'rows': 7 }, existing.keyPem || '');
			const fullchainPem = E('textarea', { 'class': 'cbi-input-text acmesh-pem-input', 'placeholder': '-----BEGIN CERTIFICATE-----', 'rows': 9 }, existing.fullchainPem || '');
			const keyFile = input(existing.keyFile || '', '/etc/ssl/example.key');
			const fullchain = input(existing.fullchainFile || '', '/etc/ssl/example.fullchain.pem');
			const owner = input(existing.owner || '', 'root');
			const group = input(existing.group || '', 'sing-box');
			const mode = input(existing.mode || '', '0640');
			const preserveMetadata = E('input', { 'type': 'checkbox' });
			preserveMetadata.checked = existing.preserveMetadata === true;
			const reloadcmd = input(existing.reloadcmd || '', 'service nginx reload');
			const domainField = field(_('Certificate domain'), domain);
			const keyTypeField = field(_('Certificate key type'), keyType);
			const sourceKeyField = field(_('Source key file'), sourceKeyFile);
			const sourceFullchainField = field(_('Source fullchain file'), sourceFullchain);
			const keyPemField = field(_('Private key PEM'), keyPem);
			const fullchainPemField = field(_('Fullchain PEM'), fullchainPem);
			const hostField = field(_('SSH host'), host);
			const userField = field(_('SSH user'), user);
			const portField = field(_('SSH port'), port);
			const sshKeyField = field(_('SSH private key'), sshKey);
			const keyFileField = field(_('Key file'), keyFile);
			const fullchainField = field(_('Fullchain file'), fullchain);
			const ownerField = field(_('File owner'), owner);
			const groupField = field(_('File group'), group);
			const modeField = field(_('File mode'), mode);
			const preserveMetadataField = E('label', { 'class': 'acmesh-checkbox acmesh-span-all' }, [ preserveMetadata, _('Keep existing owner/group/mode') ]);
			const currentDeployProfile = function() {
				const profile = {
					id: existing.id || id('deploy-preview'),
					name: name.value.trim() || 'Deploy',
					type: type.value,
					certSource: certSource.value,
					keyFile: keyFile.value.trim(),
					fullchainFile: fullchain.value.trim(),
					owner: owner.value.trim(),
					group: group.value.trim(),
					mode: mode.value.trim(),
					preserveMetadata: preserveMetadata.checked,
					reloadcmd: reloadcmd.value.trim()
				};
				if (certSource.value === 'managed-acme') Object.assign(profile, { domain: domain.value.trim(), keyType: keyType.value });
				if (certSource.value === 'local-files') Object.assign(profile, { sourceKeyFile: sourceKeyFile.value.trim(), sourceFullchainFile: sourceFullchain.value.trim() });
				if (certSource.value === 'paste-pem') Object.assign(profile, { keyPem: keyPem.value.trim(), fullchainPem: fullchainPem.value.trim() });
				if (type.value === 'ssh') Object.assign(profile, { host: host.value.trim(), user: user.value.trim() || 'root', port: port.value.trim() || '22', sshKey: sshKey.value.trim() || '/etc/acmesh-console/ssh/id_ed25519' });
				return profile;
			};
			const deploySummary = effectiveSummary([]);
			const refreshDeploySummary = function() {
				const resolvedDeploy = resolveDeployProfile(currentDeployProfile());
				deploySummary.update([
					[ _('Resolved deploy profile'), resolvedDeploy.label ],
					[ _('Resolved target'), resolvedDeploy.target ],
					[ _('Resolved source'), resolvedDeploy.source ],
					[ _('Resolved file metadata'), resolvedDeploy.metadata ],
					[ _('Resolved reload command'), resolvedDeploy.reload ]
				]);
			};
			const renderDeployFields = function() {
				const remote = type.value === 'ssh';
				const sourceMode = certSource.value;
				hostField.style.display = remote ? '' : 'none';
				userField.style.display = remote ? '' : 'none';
				portField.style.display = remote ? '' : 'none';
				sshKeyField.style.display = remote ? '' : 'none';
				domainField.style.display = sourceMode === 'managed-acme' ? '' : 'none';
				keyTypeField.style.display = sourceMode === 'managed-acme' ? '' : 'none';
				sourceKeyField.style.display = sourceMode === 'local-files' ? '' : 'none';
				sourceFullchainField.style.display = sourceMode === 'local-files' ? '' : 'none';
				keyPemField.style.display = sourceMode === 'paste-pem' ? '' : 'none';
				fullchainPemField.style.display = sourceMode === 'paste-pem' ? '' : 'none';
				owner.disabled = preserveMetadata.checked;
				group.disabled = preserveMetadata.checked;
				mode.disabled = preserveMetadata.checked;
				keyFileField.querySelector('span').textContent = remote ? _('Remote key file') : _('Local key file');
				fullchainField.querySelector('span').textContent = remote ? _('Remote fullchain file') : _('Local fullchain file');
				refreshDeploySummary();
			};
			type.addEventListener('change', renderDeployFields);
			certSource.addEventListener('change', renderDeployFields);
			preserveMetadata.addEventListener('change', renderDeployFields);
			renderDeployFields();

			return E('div', { 'class': 'acmesh-section' }, [
				E('h3', {}, _('Edit deploy profile') + ': ' + (existing.name || _('new'))),
				E('div', { 'class': 'acmesh-edit-form acmesh-edit-grid' }, [
					field(_('Name'), name),
					field(_('Type'), type),
					field(_('Certificate source'), certSource),
					domainField,
					keyTypeField,
					sourceKeyField,
					sourceFullchainField,
					keyPemField,
					fullchainPemField,
					hostField,
					userField,
					portField,
					sshKeyField,
					keyFileField,
					fullchainField,
					ownerField,
					groupField,
					modeField,
					preserveMetadataField,
					field(_('Reload command'), reloadcmd),
					deploySummary
				]),
				E('div', { 'class': 'acmesh-form-actions is-sticky' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return setEdit(null);
					}) }, _('Ignore')),
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						const profile = currentDeployProfile();
						profile.id = existing.id || id('deploy');
						config.deployProfiles = config.deployProfiles.filter(function(item) { return item.id !== profile.id; }).concat([ profile ]);
						return saveConfig().then(function() { return setEdit(null); }).then(refresh);
					}) }, _('Save deploy profile'))
				])
			]);
		}.bind(this);

		function renderBody() {
			body.innerHTML = '';
			const content = editState && editState.kind === 'account'
				? renderAccountEdit()
				: editState && editState.kind === 'issue'
					? renderIssueEdit()
						: editState && editState.kind === 'deploy'
							? renderDeployEdit()
				: activeTab === 'accounts'
				? renderAccountsList()
				: activeTab === 'issue'
					? renderIssueList()
					: activeTab === 'migration'
						? renderConfigMigration()
						: activeTab === 'authorizations'
							? renderAuthorizationRecords()
						: renderDeployList();
			body.appendChild(content);
			Array.prototype.forEach.call(document.querySelectorAll('[data-acmesh-tab]'), function(btn) {
				btn.classList.toggle('is-active', btn.getAttribute('data-acmesh-tab') === activeTab);
			});
		}

		const root = E('div', { 'class': 'cbi-map acmesh-ops' }, [
			E('style', {}, `
.acmesh-ops .acmesh-local-tabs { margin:0 0 14px; }
.acmesh-ops .acmesh-tabbar { display:inline-flex; flex-wrap:wrap; gap:0; border:1px solid rgba(127,127,127,.28); border-radius:8px; overflow:hidden; background:rgba(127,127,127,.08); }
.acmesh-ops .acmesh-tabbar button { border:0; border-right:1px solid rgba(127,127,127,.28); border-radius:0; margin:0; min-height:38px; }
.acmesh-ops .acmesh-tabbar button:last-child { border-right:0; }
.acmesh-ops .acmesh-tabbar button.is-active { color:inherit; background:rgba(47,128,237,.18); font-weight:700; }
.acmesh-ops .acmesh-section { margin:0 0 16px; padding:16px 0; border-bottom:1px solid rgba(127,127,127,.24); }
.acmesh-ops .acmesh-grid { display:grid; grid-template-columns:repeat(auto-fit, minmax(230px, 1fr)); gap:14px; }
.acmesh-ops .acmesh-card { border:1px solid rgba(127,127,127,.28); border-radius:8px; padding:12px; background:rgba(127,127,127,.08); }
.acmesh-ops .acmesh-card h4 { margin:0 0 8px; }
.acmesh-ops .acmesh-table { width:100%; border-collapse:collapse; margin-top:12px; }
.acmesh-ops .acmesh-table th { background:rgba(127,127,127,.10); font-weight:700; }
.acmesh-ops .acmesh-table th, .acmesh-ops .acmesh-table td { padding:11px 12px; border-bottom:1px solid rgba(127,127,127,.24); vertical-align:middle; }
.acmesh-ops .acmesh-row-actions { display:flex; justify-content:flex-end; gap:8px; flex-wrap:wrap; min-width:220px; }
.acmesh-ops .acmesh-empty { padding:18px; background:rgba(127,127,127,.08); border:1px solid rgba(127,127,127,.28); border-radius:8px; color:inherit; opacity:.72; }
.acmesh-ops .acmesh-edit-form { max-width:980px; margin:14px 0 12px; display:grid; gap:16px; align-items:start; }
.acmesh-ops .acmesh-edit-grid { grid-template-columns:repeat(auto-fit, minmax(260px, 1fr)); }
.acmesh-ops .acmesh-span-all { grid-column:1 / -1; }
.acmesh-ops .acmesh-form-actions { max-width:980px; display:flex; justify-content:flex-end; gap:10px; padding:12px 0; background:transparent; }
.acmesh-ops .acmesh-form-actions.is-sticky { position:sticky; bottom:0; border-top:1px solid rgba(127,127,127,.24); backdrop-filter:blur(4px); }
.acmesh-ops .acmesh-field span { display:block; font-weight:600; margin-bottom:6px; }
.acmesh-ops .acmesh-field input, .acmesh-ops .acmesh-field select, .acmesh-ops .acmesh-field textarea { width:100%; box-sizing:border-box; }
.acmesh-ops .acmesh-pem-input { font-family:monospace; min-height:140px; resize:vertical; }
.acmesh-ops .acmesh-custom-credentials { font-family:monospace; min-height:130px; resize:vertical; }
.acmesh-ops .acmesh-migration { padding-top:0; }
.acmesh-ops .acmesh-migration-grid { display:grid; grid-template-columns:minmax(240px, .8fr) minmax(320px, 1.2fr); gap:14px; align-items:start; }
.acmesh-ops .acmesh-migration-json { font-family:monospace; min-height:150px; resize:vertical; }
.acmesh-ops .acmesh-migration-summary { min-height:112px; margin:8px 0 0; padding:10px; border:1px solid rgba(127,127,127,.28); border-radius:8px; background:rgba(127,127,127,.08); white-space:pre-wrap; overflow-wrap:anywhere; }
.acmesh-ops .acmesh-credential-box { grid-column:1 / -1; display:grid; grid-template-columns:repeat(auto-fit, minmax(230px, 1fr)); gap:14px; margin-top:0; padding:12px; border:1px solid rgba(127,127,127,.28); border-radius:8px; background:rgba(127,127,127,.08); }
.acmesh-ops .acmesh-warning { color:#a33b00; font-weight:700; }
.acmesh-ops .acmesh-ok { color:#176c43; font-weight:700; }
.acmesh-ops .acmesh-inline { display:flex; gap:8px; align-items:center; min-height:30px; }
.acmesh-ops .acmesh-effective-strip { display:grid; grid-template-columns:max-content 1fr; gap:8px 14px; align-items:center; padding:8px 0; background:transparent; border-top:1px solid rgba(127,127,127,.24); border-bottom:1px solid rgba(127,127,127,.24); }
.acmesh-ops .acmesh-effective-label { margin:0; font-size:13px; font-weight:700; opacity:.82; white-space:nowrap; }
.acmesh-ops .acmesh-effective-strip dl { display:grid; grid-template-columns:repeat(auto-fit, minmax(180px, 1fr)); gap:4px 12px; margin:0; }
.acmesh-ops .acmesh-effective-strip dt { font-weight:700; color:inherit; opacity:.72; }
.acmesh-ops .acmesh-effective-strip dd { margin:1px 0 0; word-break:break-word; }
.acmesh-ops .acmesh-actions { display:flex; flex-wrap:wrap; gap:10px; margin-top:14px; }
.acmesh-ops .acmesh-terminal { min-height:120px; padding:12px; border-radius:8px; background:#101418; color:#d7e1ea; overflow:auto; line-height:1.45; white-space:pre-wrap; overflow-wrap:anywhere; }
@media (max-width: 900px) { .acmesh-ops .acmesh-migration-grid { grid-template-columns:1fr; } }
			`),
			E('div', { 'class': 'acmesh-tabs acmesh-tabbar acmesh-local-tabs' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-neutral is-active', 'data-acmesh-tab': 'accounts', 'click': ui.createHandlerFn(this, function() { return setTab('accounts'); }) }, _('Accounts')),
				E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'data-acmesh-tab': 'issue', 'click': ui.createHandlerFn(this, function() { return setTab('issue'); }) }, _('Issue Profiles')),
				E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'data-acmesh-tab': 'deploy', 'click': ui.createHandlerFn(this, function() { return setTab('deploy'); }) }, _('Deploy Profiles')),
				E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'data-acmesh-tab': 'migration', 'click': ui.createHandlerFn(this, function() { return setTab('migration'); }) }, _('Configuration migration'))
				,E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'data-acmesh-tab': 'authorizations', 'click': ui.createHandlerFn(this, function() { return setTab('authorizations'); }) }, _('Authorization records'))
			]),
			body,
			E('h3', {}, _('Task output')),
			output
		]);

		window.setTimeout(renderBody, 0);
		return root;
	}
});
