#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PO_ZH_HANS="$ROOT/po/zh_Hans/acmesh-console.po"
PO_ZH_HANT="$ROOT/po/zh_Hant/acmesh-console.po"
PO_JA="$ROOT/po/ja/acmesh-console.po"
PO_KO="$ROOT/po/ko/acmesh-console.po"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"

cleanup() {
	rm -f \
		"$ROOT/tests/.tmp/acmesh-console.zh_Hans.lmo" \
		"$ROOT/tests/.tmp/acmesh-console.zh_Hant.lmo" \
		"$ROOT/tests/.tmp/acmesh-console.ja.lmo" \
		"$ROOT/tests/.tmp/acmesh-console.ko.lmo"
}

trap cleanup EXIT HUP INT TERM
mkdir -p "$ROOT/tests/.tmp"

require_file_text() {
	file="$1"
	needle="$2"
	if ! grep -Fq -- "$needle" "$file"; then
		echo "missing i18n marker: $needle"
		exit 1
	fi
}

[ -f "$PO_ZH_HANS" ] || { echo "missing Simplified Chinese i18n catalog"; exit 1; }
[ -f "$PO_ZH_HANT" ] || { echo "missing Traditional Chinese i18n catalog"; exit 1; }
[ -f "$PO_JA" ] || { echo "missing Japanese i18n catalog"; exit 1; }
[ -f "$PO_KO" ] || { echo "missing Korean i18n catalog"; exit 1; }

require_file_text "$PO_ZH_HANS" 'Language: zh_Hans'
require_file_text "$PO_ZH_HANT" 'Language: zh_Hant'
require_file_text "$PO_JA" 'Language: ja'
require_file_text "$PO_KO" 'Language: ko'

require_file_text "$PO_ZH_HANS" 'msgid "Operations"'
require_file_text "$PO_ZH_HANS" 'msgstr "操作"'
require_file_text "$PO_ZH_HANS" 'msgid "Certificates"'
require_file_text "$PO_ZH_HANS" 'msgstr "证书"'
require_file_text "$PO_ZH_HANS" 'msgid "Core & Defaults"'
require_file_text "$PO_ZH_HANS" 'msgstr "核心与默认值"'
require_file_text "$PO_ZH_HANS" 'msgid "Deploy Profiles"'
require_file_text "$PO_ZH_HANS" 'msgstr "部署配置"'
require_file_text "$PO_ZH_HANS" 'msgid "DNS Test"'
require_file_text "$PO_ZH_HANS" 'msgstr "DNS 测试"'
require_file_text "$PO_ZH_HANS" 'msgid "Issue"'
require_file_text "$PO_ZH_HANS" 'msgstr "签发"'
require_file_text "$PO_ZH_HANS" 'msgid "Issue and deploy"'
require_file_text "$PO_ZH_HANS" 'msgstr "签发并部署"'
require_file_text "$PO_ZH_HANS" 'msgid "Issue succeeded; starting deploy profile"'
require_file_text "$PO_ZH_HANS" 'msgstr "证书签发成功，开始执行部署配置"'
require_file_text "$PO_ZH_HANS" 'msgid "Imported issue profiles"'
require_file_text "$PO_ZH_HANS" 'msgstr "已导入签发配置"'
require_file_text "$PO_ZH_HANS" 'msgid "Summary"'
require_file_text "$PO_ZH_HANS" 'msgstr "摘要"'
require_file_text "$PO_ZH_HANS" 'msgid "The DNS provider rejected the TXT record. Check that the domain belongs to this DNS account and that the selected DNS API credentials match the provider."'
require_file_text "$PO_ZH_HANS" 'msgid "Cloudflare API Token"'
require_file_text "$PO_ZH_HANS" 'msgstr "Cloudflare API 令牌"'
require_file_text "$PO_ZH_HANS" 'msgid "Paste PEM content"'
require_file_text "$PO_ZH_HANS" 'msgstr "粘贴 PEM 内容"'

require_file_text "$OPS" "label: _('Cloudflare API Token')"
require_file_text "$OPS" "title: _('Cloudflare')"
require_file_text "$OPS" "label: _('Aliyun AccessKey ID')"

command -v node >/dev/null || { echo "node is not available; skipping po2lmo generation check"; exit 0; }
node "$ROOT/tools/check_i18n_coverage.js"

for locale in zh_Hans zh_Hant ja ko; do
	po="$ROOT/po/$locale/acmesh-console.po"
	lmo="$ROOT/tests/.tmp/acmesh-console.$locale.lmo"
	node "$ROOT/tools/po2lmo.js" "$po" "$lmo"

	[ -s "$lmo" ] || { echo "generated $locale lmo is empty"; exit 1; }

	node - "$lmo" "$locale" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const locale = process.argv[3];
const data = fs.readFileSync(file);
if (data.length < 20) {
	console.error(`generated ${locale} lmo is too small`);
	process.exit(1);
}
const offset = data.readUInt32BE(data.length - 4);
const entries = (data.length - offset - 4) / 16;
if (offset <= 0 || offset >= data.length || entries < 10 || entries % 1 !== 0) {
	console.error(`invalid ${locale} lmo index: offset=${offset} entries=${entries}`);
	process.exit(1);
}
NODE
done

for text in '操作' '部署配置' 'Cloudflare API 令牌'; do
	if ! grep -Fq -- "$text" "$ROOT/tests/.tmp/acmesh-console.zh_Hans.lmo"; then
		echo "missing generated Simplified Chinese lmo text: $text"
		exit 1
	fi
done

echo "test_i18n_support: ok"
