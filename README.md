<div align="center">

# CodexBridger

<img src="CodexBridger.png" alt="CodexBridger" width="128">

**把第三方模型提供商轻松接进 ChatGPT / Codex，从此再也不需要手动编辑配置文件。**

CodexBridger 是一个 macOS 配置管理软件。你在界面里填好「提供商地址 + API Key + 模型列表」，点一下**激活**，它就会把 ChatGPT（Codex）需要读取的所有配置文件写好，之后打开 ChatGPT 就能直接使用这个提供商和它的模型。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org)

[安装](#安装) ·
[使用](#使用) ·
[功能](#功能) ·
[安全设计](#它是怎么保证不弄坏你的配置的)

**简体中文** · [English](./README_EN.md)

</div>

---

<p align="center">
  <a href="ScreenShot2.png"><img src="ScreenShot2.png" alt="CodexBridger 主界面：左侧是提供商列表，右侧是提供商信息、认证方式和模型配置" width="760"></a>
</p>

## 为什么需要它？

想用第三方模型（DeepSeek、Kimi、GLM、OpenRouter……）驱动 ChatGPT，就得手动改配置文件。而配置文件有三个，字段名和取值都有讲究，写错一个键就可能让 ChatGPT 起不来——改之前还得自己先备份。

CodexBridger 把这件事变成「填表 + 点一下按钮」：不用记字段，不用手动备份，换提供商会先问你。

它只做这一件事：**生成并维护 ChatGPT 的配置文件**。不注入、不劫持进程，也不需要 ChatGPT 开着。

## 它写哪三个文件

| 文件 | 位置 | 作用 |
| --- | --- | --- |
| `config.toml` | `~/.codex/config.toml` | 告诉 ChatGPT 用哪个提供商、哪个模型、模型参数文件在哪 |
| `auth.json` | `~/.codex/auth.json` | 存放凭据（详见下方说明） |
| `<提供商>-model-catalog.json` | `~/.codex/model-catalogs/` | 模型参数文件 |

### `auth.json` 是怎么处理的

它**不是**整份覆盖，也**不是**无条件保留：

- **保留**文件里已有的其他内容，例如 ChatGPT 自身的登录 token。
- **替换** `OPENAI_API_KEY`，并写入当前提供商的 `<提供商>_KEY`。
- **清除**其他提供商遗留的 `*_KEY` / `*_API_KEY`，避免已经不再使用的服务凭据继续留在磁盘上。
- Bearer Token 留空时不会写入凭据，只在界面给出提示。

### 备份规则

替换之前，原来的 `config.toml` 和 `auth.json` 会被复制到 `~/.codex/backup/config-backup/`，文件名带上所属的提供商：

- `config-<提供商>-yyyy-mm-dd-hhmm-bak.toml`
- `auth-<提供商>-yyyy-mm-dd-hhmm-bak.json`

同一分钟内连续操作时，后面那份会带上 `-2`、`-3` 后缀，不会覆盖上一份。

> **唯一的例外**：如果被替换的配置**本来就是 CodexBridger 自己生成的**（也就是你在本软件管理的两个提供商之间切换），则跳过备份。别人的配置、或你手动改过的配置，一定会先备份。

## 安装

### 下载（推荐）

从 [Releases](https://github.com/panando/CodexBridger/releases) 下载 `.dmg`，打开后把 CodexBridger 拖进「应用程序」文件夹。

### 首次打开会被系统拦下（当前没有开发者签名）

软件目前使用**临时签名（ad-hoc signature）**，没有用 Apple 开发者证书签名，也没有经过 Apple 公证（notarization）。因此 macOS 的 Gatekeeper 可能弹出下面**两种提示之一**：

> "CodexBridger"已损坏，无法打开。你应该将它移到废纸篓。

> "CodexBridger"无法打开，因为无法验证开发者。

**这通常不代表软件真的损坏了。** 它的含义是：macOS 给一个「从网上下载、又没有经过公证」的 App 打上了隔离标记（quarantine flag）。

#### 方法一：在「系统设置」里放行（推荐，不用命令行）

1. 先双击打开一次 CodexBridger（会被拦下）。
2. 打开 **系统设置 → 隐私与安全性**。
3. 在「安全性」一栏里，会看到刚才关于 CodexBridger 的提示。
4. 点 **仍要打开**。
5. 在弹窗里确认打开。

#### 方法二：用「终端」清除隔离标记

如果「仍要打开」没有出现，或者系统仍然提示「已损坏」，请先把 `CodexBridger.app` 拖进**应用程序**文件夹，然后打开「终端」，执行：

```bash
sudo xattr -dr com.apple.quarantine /Applications/CodexBridger.app
```

输入你的 Mac 登录密码后按回车（**输入时终端不会显示任何字符，这是正常的**），然后再打开 CodexBridger 即可。

如果不确定 App 的完整路径，可以先输入下面这行（**注意末尾有一个空格**）：

```bash
sudo xattr -dr com.apple.quarantine 
```

然后从访达里把 `CodexBridger.app` 拖进终端窗口，再按回车。

> **注意**：只对你信任来源的 App 做这一步。

### 从源码构建

```bash
git clone https://github.com/panando/CodexBridger.git
cd CodexBridger
./scripts/build-app.sh          # 生成 build/CodexBridger.app
open build/CodexBridger.app     # 打开软件
```

需要 macOS 14 以上和 Xcode 命令行工具。**零外部依赖**：整个项目只用系统自带的 Foundation / SwiftUI，断网也能构建。

对外分发请编译成同时支持 Apple 芯片和 Intel 的版本（**只有 arm64 的包在 Intel Mac 上双击没有任何反应**）：

```bash
./scripts/build-app.sh release universal dmg   # 生成 build/CodexBridger-<VERSION>.dmg
```

版本号只有一个来源：仓库根目录的 `VERSION` 文件，改它即可——构建时会写进 App 的「关于」页面。把 `dmg` 换成 `zip` 则产出压缩包（不需要磁盘仲裁权限，适合在 CI 里打包）。

## 使用

<p align="center">
  <a href="ScreenShot1.png"><img src="ScreenShot1.png" alt="CodexBridger 还没有提供商时的欢迎页" width="760"></a>
</p>

还没添加提供商时，界面会列出软件能做什么，并给出一个**新建提供商**按钮。

1. 点左下角**添加**，从预设里选一个服务商（DeepSeek、Moonshot、MiniMax、智谱 GLM、OpenRouter），或者选「自定义」自己填。
2. 填 **Base URL** 和 **API Key**。
3. 在**模型配置**里加上要用的模型（点「添加模型」逐个加，每个模型可以单独设置上下文窗口、推理强度等）。
4. 点右下角**启用**。软件会写文件并显示结果；如果会顶掉正在使用的提供商会先请你确认。
5. 打开 ChatGPT 即可使用。

## 功能

- **提供商管理** — 增删改查，支持多个提供商共存、随时切换。
- **一个提供商多个模型** — 每个模型可以单独设置上下文窗口、最大上下文、推理强度、是否在列表中显示等。
- **内置常见服务商预设** — DeepSeek、Moonshot 月之暗面、MiniMax、智谱 GLM、OpenRouter，也可以完全自定义。
- **三种认证方式** — Bearer Token、环境变量、登录命令，按 ChatGPT 官方文档互斥，选了哪个就只写哪个。
- **模型参数文件生成** — 用本机 ChatGPT 内置的模型目录作为模板，让生成的参数和你的 ChatGPT 版本一致。
- **激活前检查** — `base_url` 为空或指向本机时会常驻提示；要顶掉正在使用的提供商会先弹确认框。
- **备份浏览** — 设置里可以直接看到备份目录里的历史文件。

## 它是怎么保证不弄坏你的配置的

1. **先备份，再写入。** 备份在任何一个字节被修改之前完成（例外见上文「备份规则」）。
2. **原子写入。** 每个文件都是先写临时文件、再整体改名覆盖。中途断电或被杀掉，ChatGPT 看到的要么是旧文件、要么是新文件，不会看到写了一半的文件。
3. **只动自己的键。** 它不重新序列化整个 `config.toml`，只替换自己负责的顶层字段和它管理的那一个 `[model_providers.<id>]` 段落。你的插件、MCP、hooks、skills 配置原样保留。
4. **不写 ChatGPT 不支持的字段。** 所有字段都来自官方配置参考。
5. **顶掉正在用的提供商会先问你。** 激活前会读一次 ChatGPT 当前实际使用的是哪个提供商；如果要换掉的是**另一个**，会先弹确认框，写清「当前使用 X，将切换为 Y」。
6. **配置读不出来时不会假装「没有配置」。** 如果本软件自己的 `config.json` 损坏，界面会明确报错并说明原文件未被改动，而不是显示成「0 个提供商」。

## 已知限制

- 需要 macOS 14 以上；界面用 SwiftUI 写的，没有做 Windows 版本。
- **没有 Apple 开发者签名和公证**，别人从网上下载后第一次打开会被系统拦下。这不是软件损坏，处理方法见[《首次打开会被系统拦下》](#首次打开会被系统拦下当前没有开发者签名)。

## 许可证

本项目采用 [MIT License](LICENSE)。

Copyright (c) 2026 panando
