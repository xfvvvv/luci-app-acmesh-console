# luci-app-acmesh-console

[![Build release packages](https://github.com/chelal233/luci-app-acmesh-console/actions/workflows/build-packages.yml/badge.svg)](https://github.com/chelal233/luci-app-acmesh-console/actions/workflows/build-packages.yml)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-LuCI-00B5E2.svg)](https://openwrt.org/)
[![acme.sh](https://img.shields.io/badge/ACME-acme.sh-green.svg)](https://github.com/acmesh-official/acme.sh)

**Languages:** [English](#english) | [简体中文](#简体中文) | [日本語](#日本語)

> **Powered by Codex**
>
> Initiated, specified and maintained by **chelal233**. Core architecture, primary implementation, security review, automated testing and release engineering were created in collaboration with **Codex (OpenAI)**.
>
> 本项目由 **chelal233** 发起、定义需求并维护；核心架构、主要实现、安全复审、自动化测试与发布工程由 **Codex（OpenAI）** 协作完成。

<a id="english"></a>

## English

### About

`luci-app-acmesh-console` is a security-first LuCI console for operating the official `acme.sh` client on OpenWrt and ImmortalWrt. It manages ACME accounts, certificate issuance and renewal, local or SSH deployment, task logs, core upgrades and configuration migration without turning high-impact operations into opaque one-click actions.

The browser submits an operation intent, while the router backend reloads the saved profile, resolves the effective parameters, creates a private task snapshot and generates the exact authorization summary. Browser-provided free-form JSON is never treated as an authorized production operation.

### Highlights

- ACME account, issuance and deployment profiles;
- wildcard and multi-domain certificates through official DNS API integrations;
- certificate discovery, renewal, revocation and removal;
- local deployment and remote SSH deployment with backup and rollback;
- SSH host-key fingerprint display, pinning and hard failure on identity changes;
- explicit one-time or remembered risk authorization bound to exact operation material;
- protected secrets, redacted logs and router-local trust state;
- auditable background tasks with atomic status, stages and exit codes;
- official `acme.sh` core installation and upgrades;
- English source UI plus Simplified Chinese, Traditional Chinese, Japanese and Korean catalogs;
- multi-architecture IPK and APK builds through GitHub Actions.

### Security model

Real issuance, renewal, deployment, core installation or upgrade, temporary SSH key conversion and sensitive configuration export require explicit authorization. Revocation, certificate removal, profile deletion and overwrite imports always require a one-time decision.

The issue profile table exposes two explicit choices: **Issue** authorizes certificate issuance only, while **Issue and deploy** creates one combined authorization and one task whose risk summary covers both issuance and the linked deployment. The installed `acmesh-console-ssh` hook is used by later `acme.sh` renewals and never bypasses deploy authorization.

There is no global test mode, debug bypass, `--yes`, `--force-all` or disable-confirmations switch. Test mode performs command validation without ACME requests, DNS changes, file deployment, service reloads or remembered authorization. Let's Encrypt Staging remains a real remote ACME service and is not treated as test mode.

Private state is stored under `/etc/acmesh-console` using `0700` directories and `0600` private files. Remembered authorization and pinned SSH identities stay local to the router and are deliberately excluded from configuration migration.

### Compatibility and installation

| Target | Format | Package manager |
| --- | --- | --- |
| OpenWrt 24.10 | `.ipk` | `opkg` |
| OpenWrt SNAPSHOT | `.apk` | `apk` |
| ImmortalWrt 25.12.1 | `.apk` | `apk` |

Download the main package and the required language package from [Releases](https://github.com/chelal233/luci-app-acmesh-console/releases), verify `SHA256SUMS`, then install them with the matching package manager. Translation packages use the suffixes `zh-cn`, `zh-tw`, `ja` and `ko`. This project is not an Entware package and does not publish `.opk` aliases.

After installation, open **LuCI → Services → acme.sh Console**. See the [Simplified Chinese documentation](#简体中文) below for complete installation, operation, CLI, build and verification instructions.

[`acmesh-official/acme.sh`](https://github.com/acmesh-official/acme.sh) is the sole authority for ACME client behavior. This console is independent and does not fork, replace or reinterpret the official client.

<a id="日本語"></a>

## 日本語

### 概要

`luci-app-acmesh-console` は、OpenWrt / ImmortalWrt 上で公式 `acme.sh` クライアントを安全に運用するための LuCI コンソールです。ACME アカウント、証明書の発行・更新、ローカルまたは SSH 配備、タスクログ、コア更新、設定移行を一元管理します。

ブラウザーは操作の意図だけを送信します。最終的なパラメーター、リスク確認内容、タスク専用スナップショットはルーター側のバックエンドが保存済みプロファイルから再生成するため、ブラウザーが送信した自由形式 JSON がそのまま本番操作として承認されることはありません。

### 主な機能

- ACME アカウント、発行、配備プロファイルの管理；
- DNS API を利用したワイルドカードおよび複数ドメイン証明書；
- 証明書の検出、更新、失効、削除；
- バックアップとロールバックを備えたローカル/SSH 配備；
- SSH ホスト鍵の SHA-256 指紋確認、固定、変更時の強制停止；
- 操作内容に厳密に結び付いた一回限り、または記憶可能なリスク承認；
- 秘密情報の保護、ログのマスキング、監査可能なバックグラウンドタスク；
- 英語の標準 UI と、簡体字中国語・繁体字中国語・日本語・韓国語の翻訳；
- GitHub Actions による複数アーキテクチャ向け IPK / APK ビルド。

### セキュリティと対応環境

グローバルなテストモード、デバッグ回避、`--yes`、`--force-all`、全確認無効化オプションはありません。秘密データは `/etc/acmesh-console` に保存され、ディレクトリは `0700`、秘密ファイルは `0600` です。

OpenWrt 24.10 向けに IPK、OpenWrt SNAPSHOT と ImmortalWrt 25.12.1 向けに APK を提供します。パッケージは [Releases](https://github.com/chelal233/luci-app-acmesh-console/releases) から取得し、`SHA256SUMS` を確認してからインストールしてください。詳細な手順は下記の[簡体字中国語ドキュメント](#简体中文)を参照してください。

公式 [`acmesh-official/acme.sh`](https://github.com/acmesh-official/acme.sh) が ACME 動作の唯一の正規情報源です。本プロジェクトは公式クライアントを置換、フォーク、再解釈しません。

<a id="简体中文"></a>

## 简体中文

一个面向 OpenWrt / ImmortalWrt 的安全优先 `acme.sh` LuCI 控制台，用于管理 ACME 账户、证书签发、续期、部署、任务日志和远程 SSH 目标。

### 项目简介

`luci-app-acmesh-console` 将 `acme.sh` 的常用运维能力整合进 LuCI，同时避免把高风险操作简化成一次不透明的按钮点击。

项目不仅提供证书管理界面，还为真实签发、DNS 修改、私钥部署、远程文件覆盖、服务重载、证书吊销和核心升级建立了明确的安全边界。浏览器只负责提交操作意图；最终参数、授权摘要和任务快照均由路由器后端重新生成。

适合以下场景：

- 在 OpenWrt / ImmortalWrt 主路由上集中管理 HTTPS 证书；
- 使用 DNS API 签发通配符或多域名证书；
- 将证书部署到路由器本机或远程 Linux/OpenWrt 主机；
- 需要可审计任务记录、私钥保护、SSH 主机身份固定和部署失败回滚；
- 希望通过 LuCI 完成日常操作，同时保留明确的风险确认。

### 核心能力

- ACME 账户配置：管理 CA、账户邮箱和实际生效参数；
- 签发配置：主域名、SAN、密钥类型、验证方式和 DNS 服务商凭据；
- 证书管理：发现、查看、续期、吊销和移除已有证书；
- 部署配置：支持本机部署和 SSH 远程部署；
- 部署事务：替换前备份，失败时回滚，并在成功后执行重载命令；
- SSH 安全：首次连接显示算法与 SHA-256 指纹，固定后拒绝主机密钥变化；
- 后台任务：原子化任务状态、阶段、退出码、摘要和脱敏日志；
- 核心管理：安装或升级选定版本的官方 `acme.sh`；
- 配置迁移：导入和导出配置，同时排除路由器本地信任状态；
- 风险授权：支持仅本次执行，以及在允许的操作上记住精确授权；
- 英文默认界面，以及简体中文、繁体中文、日语和韩语本地化；
- GitHub Actions 多架构 IPK / APK 构建和 Release 发布。

### 安全设计

### 后端决定最终操作

生产签发和部署只接受配置档案 ID。后端会重新读取已保存配置，解析最终参数，生成任务私有快照和授权摘要。前端提交的自由 JSON 不能直接成为已授权的生产操作。

### 显式风险授权

以下真实操作需要匹配的路由器本地授权，或由用户明确确认：

- 签发与续期证书；
- 本机或 SSH 部署证书；
- 安装或升级 `acme.sh` 核心；
- 临时转换 SSH 私钥；
- 导出包含敏感资料的配置。

证书吊销/移除、配置档案删除和覆盖导入始终要求一次性确认。授权仅接受界面中展示的具体业务后果，不会关闭密钥保护、日志脱敏、ACL 隔离、SSH 主机验证、路径验证、任务原子性或部署回滚。

已记住的授权仅保存在当前路由器，可以从 **操作 → 授权记录** 单独撤销或全部撤销。操作参数发生实质变化后，旧授权自动失效。

### 私密状态与权限

私密状态保存在：

```text
/etc/acmesh-console
```

目录权限为 `0700`，私密文件为 `0600`。DNS 凭据、密码、PEM、私钥、任务私有文件和迁移导出内容不会写入公开日志。

### 没有全局绕过开关

项目不存在全局测试模式、全局调试绕过、`--yes`、`--force-all` 或禁用全部确认的选项。测试行为必须在对应操作或配置档案上明确选择。

### 与官方 acme.sh 的关系

[`acmesh-official/acme.sh`](https://github.com/acmesh-official/acme.sh) 是本项目唯一的 ACME 行为权威来源。

本项目是独立的 LuCI 控制台，不替代、不分叉、也不重新定义 `acme.sh`。命令构造、CA 行为、DNS API 和证书目录语义必须保持与官方客户端兼容。

### 兼容性与包格式

| 构建目标 | 包格式 | 包管理器 | 说明 |
| --- | --- | --- | --- |
| OpenWrt 24.10 | `.ipk` | `opkg` | GitHub Actions 发布目标 |
| OpenWrt SNAPSHOT | `.apk` | `apk` | GitHub Actions 发布目标 |
| ImmortalWrt 25.12.1 | `.apk` | `apk` | 已完成 x86-64 SDK 实际构建验证 |

本项目不是 Entware 软件包，因此不会生成容易造成误解的 `.opk` 别名。

运行依赖以 [`Makefile`](Makefile) 为准，当前包括 LuCI、rpcd、BusyBox、`jsonfilter`、OpenSSL、curl、tar、Dropbear 密钥转换工具和 OpenSSH 客户端工具。

### 安装

从 [Releases](https://github.com/chelal233/luci-app-acmesh-console/releases) 下载与系统包管理器匹配的主包和所需语言包，并先核对 Release 中的 `SHA256SUMS`。

### OpenWrt 24.10 / opkg

```sh
opkg install ./luci-app-acmesh-console_*.ipk
opkg install ./luci-i18n-acmesh-console-LANGUAGE_*.ipk
```

### OpenWrt SNAPSHOT 或 ImmortalWrt 25.12 / apk

对于本地下载且已核对 SHA-256 的未签名 Release 包：

```sh
apk add --allow-untrusted ./luci-app-acmesh-console-*.apk
apk add --allow-untrusted ./luci-i18n-acmesh-console-LANGUAGE-*.apk
```

将 `LANGUAGE` 替换为所需语言：`zh-cn`（简体中文）、`zh-tw`（繁体中文）、`ja`（日语）或 `ko`（韩语）。英文为 LuCI 源文本，无需额外语言包。

安装完成后进入：

```text
LuCI → 服务 → acme.sh Console
```

### 快速开始

1. 在 **核心与默认值** 中选择并安装官方 `acme.sh` 版本；
2. 创建账户配置，填写真实账户邮箱并选择 CA；
3. 创建签发配置，填写域名、SAN、密钥类型和验证方式；
4. 如果使用 DNS 验证，配置对应的官方 DNS API 凭据；
5. 可选：创建本机或 SSH 部署配置；
6. 先运行测试操作检查最终命令和参数；
7. 核对风险摘要后选择 **签发**，或选择 **签发并部署**（后者只确认一次，授权摘要同时覆盖签发和关联部署）；
8. 在任务页面查看阶段、结果和脱敏日志。

如果签发配置关联了部署配置，控制台会在对应的 `acmeHome/deploy/` 中自动注册
`acmesh-console-ssh` hook（同时保留 `acmesh_console_ssh` 兼容入口），因此不需要手动复制 hook 文件。
操作页中的 **签发** 只执行证书签发；**签发并部署** 会在一次风险授权下顺序完成签发和关联部署，不会在签发成功后再次弹出部署授权。后续 `acme.sh` 续期才由该 hook 触发部署，且始终要求匹配的部署授权。

### 测试模式与 Let's Encrypt Staging

测试模式是完全不产生外部变更的命令验证路径。它不得发送 ACME 请求、修改 DNS、部署文件、重载服务、消耗挑战或创建可记忆授权。

Let's Encrypt Staging 是真实的远程 ACME 服务，仍可能执行 DNS 验证。选择 Staging 不等同于测试模式，真实 Staging 操作仍需正常的风险授权。

### SSH 主机身份与临时密钥转换

首次连接未知 SSH 主机时，控制台会单独展示：

- 目标主机与端口；
- 主机密钥算法；
- SHA-256 指纹。

确认后，身份会固定在控制台自己的私密 `known_hosts` 中。主机密钥发生变化属于硬失败，必须先通过独立渠道核验目标，再更新固定身份。

如果 Dropbear 需要转换 OpenSSH 私钥，转换操作需要独立授权，只生成本次部署使用的私密临时文件，并在任务结束后清理。

### 配置迁移边界

导出的配置可能包含 DNS 凭据和证书资料，必须视为敏感文件。

迁移数据不会包含：

- 路由器实例身份；
- 已记住的风险授权；
- 固定的 SSH 主机身份；
- 控制台自身 SSH 私钥；
- 任务、日志和待确认挑战。

因此，把配置导入另一台路由器不会同时导入原路由器的信任关系。

### CLI 风险确认

CLI 调用通过标准输入接收敏感 JSON，避免把秘密放入进程参数：

```sh
printf '%s\n' '{"profileId":"example"}' | \
  /usr/libexec/acmesh-console/acmeshctl issue --request-stdin
```

真实调用返回 `authorizationRequired` 后，可以执行一次或记住允许记忆的授权：

```sh
/usr/libexec/acmesh-console/acmeshctl --acknowledge-risk CHALLENGE_ID
/usr/libexec/acmesh-console/acmeshctl --remember-authorization CHALLENGE_ID
```

### 构建与发布

仓库中的 [GitHub Actions workflow](.github/workflows/build-packages.yml) 会为十种常见架构构建：

- OpenWrt 24.10 IPK；
- OpenWrt SNAPSHOT APK。

在 Actions 中手动运行 **Build release packages** 可以下载构建产物。项目版本仅由 `PKG_VERSION` 表示；每次代码发布都递增 `PKG_VERSION`，并推送完全匹配的标签，例如 `PKG_VERSION:=0.1.1` 对应 `v0.1.1`；该标签会自动创建或更新 GitHub Release，并附加所有包和 SHA-256 校验文件。

Windows + WSL2、ImmortalWrt SDK、完整源码、ImageBuilder、x86-64/ext4 镜像和路由器验收流程参见：

- [ImmortalWrt 编译、打包与升级工作流](docs/IMMORTALWRT_BUILD_WORKFLOW.md)

### 测试与发布门槛

在安装了测试源码的路由器上执行：

```sh
sh /usr/libexec/acmesh-console/tests/run_host_tests.sh
```

完整测试必须以以下内容结束：

```text
all host tests passed
```

同时检查关键权限与 LuCI 入口：

```sh
busybox stat -c '%a %n' \
  /etc/acmesh-console \
  /etc/acmesh-console/authorizations.json \
  /var/run/acmesh-console/requests \
  /var/run/acmesh-console/authorization-challenges

ls /www/luci-static/resources/view/acmesh/operations*.js
```

私密目录/文件必须保持 `700/600`，并且只能安装当前的 `operations_v2.js`。

### 安全问题报告

请勿在公开 Issue 中提交 DNS Token、密码、PEM、私钥、任务私有文件或完整迁移配置。

报告安全问题时，请提供受影响版本、操作类型和已脱敏的复现步骤，并通过私密渠道联系项目维护者。

### 作者与致谢

- 项目发起、需求定义与维护：**chelal233**；
- 主要工程作者：**Codex（OpenAI）**；
- ACME 客户端与协议行为来源：[`acmesh-official/acme.sh`](https://github.com/acmesh-official/acme.sh)；
- Web 管理框架：OpenWrt LuCI。

**Powered by Codex — built with care, reviewed for safety, and shared as open source.**

### License

本项目采用 [GPL-3.0-or-later](LICENSE) 许可证。
