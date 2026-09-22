# ECNU OpenConnect GUI

面向 Windows 的华东师范大学（ECNU）VPN 图形登录工具。双击即用，内置 OpenConnect 运行环境，**不需要你自己安装 OpenConnect，也不需要配置 PATH**。

![平台](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%2010%20%7C%2011-0078D6?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square)
![许可证](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-green?style=flat-square)

---

## 这个工具能做什么

- **登录 / 退出登录**：输入账号密码，点一下就连上校园 VPN。
- **默认只走校园网段**：不做全局代理，普通上网流量仍然走本机原网络，看视频、打游戏不受影响。
- **路由可控**：界面上直接增删「哪些网段走 VPN」。
- **日志随手看**：连接过程、失败原因都在界面里的日志区，也可以一键打开日志文件。
- **在托盘安静待着**：关掉窗口不会退出程序，随时可以从托盘登录或退出登录。

> [!IMPORTANT]
> 本工具需要**管理员权限**运行。OpenConnect 要创建虚拟网卡并修改 Windows 路由表，UAC 弹窗请选择“是”。

---

## 🚀 快速开始

> [!TIP]
> **三步就能连上：**
> **① 解压整个文件夹 → ② 双击 `Start-ECNU-OpenConnect-GUI.vbs` → ③ UAC 选“是”，输入账号密码点“登录”。**
>
> 登录成功后，右上角状态会显示 `已连接 10.x.x.x`，主按钮会变成红色的 **“退出登录”**。
> 完整操作步骤如下。

### 0. 开始之前，先确认这几条

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 10 / Windows 11 |
| 运行环境 | PowerShell 5.1 或更高（Win10/11 自带，无需安装） |
| 权限 | 管理员权限（每次启动都会弹 UAC） |
| 账号 | 你的 ECNU VPN 账号和密码 |
| 网络 | 能正常上网即可，不要求先连校园网 |

### 1. 下载并解压到本机

- 点击本页右上角 **Code → Download ZIP**，或者直接克隆仓库：

  ```powershell
  git clone https://github.com/shanye-xia/ECNU-OpenConnect.git
  ```

- 把整个 `ECNU-OpenConnect-GUI` 文件夹解压到任意位置，例如 `D:\Tools\ECNU-OpenConnect-GUI`。

> [!WARNING]
> 请先**完整解压**再运行。直接在压缩包预览窗口里双击 `.vbs`，会因为找不到 `internal` 目录而启动失败。

### 2. 双击启动程序

在解压出来的文件夹里双击 **`Start-ECNU-OpenConnect-GUI.vbs`**。

两个启动入口的区别：

| 文件 | 用途 | 说明 |
| --- | --- | --- |
| `Start-ECNU-OpenConnect-GUI.vbs` | **推荐** | 启动时不留下蓝色 PowerShell 窗口，界面更干净 |
| `Start-ECNU-OpenConnect-GUI.cmd` | 备用 | 保留控制台窗口，启动异常时用它更容易看出问题 |

### 3. 允许管理员权限

Windows 会弹出 UAC 提示（来源显示为 `powershell.exe`），选择 **“是”**。

> [!NOTE]
> 选择“否”程序会直接退出，不会出现任何界面。

### 4. 填写账号和密码

主窗口左侧「账号」区域：

1. **用户名**：你的 ECNU VPN 账号。
2. **密码**：对应密码。
3. **保存密码到本机**（可选，默认勾选）：勾选后**登录成功才会**把账号密码保存到本机，下次打开自动填好。登录失败不会覆盖原来可用的密码。

### 5. 点击“登录”并等待

点击蓝色 **“登录”** 按钮，然后看界面右上角的状态徽章：

| 状态 | 含义 |
| --- | --- |
| `未连接` | 当前没有 VPN 连接 |
| `正在登录...` | 已提交登录请求，正在等待服务器响应 |
| `已连接 10.x.x.x` | 连接成功，并拿到了 VPN 分配地址 |
| `连接中 / 已启动` | OpenConnect 进程在运行，但还没拿到地址，可在日志区确认进度 |

默认等待上限是 **50 秒**（`LoginTimeoutSeconds`）。登录过程中界面会短暂不可点击，这是正常的，请不要重复点按钮。

### 6. 需要断开时点“退出登录”

连接成功后，主按钮会变成红色 **“退出登录”**。点击它就会断开 VPN 并清理路由，随后按钮变回蓝色“登录”。

### 第一次使用时可能会遇到

- **首次启动稍慢**：第一次运行需要准备网卡环境，界面出现可能要等几秒。
- **驱动确认**：如果这台电脑从没装过 OpenConnect / Wintun 相关驱动，Windows 可能提示安装或加载驱动，选择允许即可。
- **安全软件拦截**：部分安全软件会拦截 `.vbs` 或 PowerShell 脚本，放行该文件夹即可。
- **重复启动**：程序是单实例的，重复双击会提示“ECNU OpenConnect 已经在运行，请在托盘图标中操作。”

---

## 怎么判断已经连上

满足下面任意两条，基本可以确定连接成功：

1. 右上角状态徽章显示 `已连接 10.x.x.x`。
2. 主按钮变成红色“退出登录”。
3. 日志区最后出现 `Connected as` / `Configured as` 之类的成功标记。
4. 访问校内网站（例如 `https://www.ecnu.edu.cn`）正常。

---

## 界面说明

### 账号区（左侧）

| 控件 | 说明 |
| --- | --- |
| 用户名 | 填写 ECNU VPN 账号 |
| 密码 | 填写对应密码；连接状态下会置灰 |
| 保存密码到本机 | 勾选后，**登录成功**才保存；取消勾选并成功登录一次会删除已保存的信息 |
| 登录 / 退出登录 | 同一个按钮，随连接状态变色：蓝色 = 登录，红色 = 退出登录 |

### 右侧区域

| 控件 | 说明 |
| --- | --- |
| 走 VPN 的路由 | 当前会被路由进 VPN 的网段列表，默认 `172.0.0.0/8`、`202.120.0.0/16` |
| 添加 | 在输入框里填 CIDR（例如 `202.120.0.0/16`）后点“添加”，立即写入配置 |
| 删除选中 | 选中列表里的一条路由后删除 |
| 日志 | 实时显示最近 80 行 OpenConnect 日志 |
| 打开日志 | 用默认编辑器打开 `internal\ECNU-OpenConnect.log` |
| 打开目录 | 打开日志所在目录 |

### 托盘与关闭行为

- 点击窗口右上角 **×**，程序默认**最小化到系统托盘**，不会退出，VPN 也不会断开。
- 托盘图标右键菜单：`显示窗口`、`登录` / `退出登录`、`打开日志`、`打开日志目录`、`退出程序`。
- 选择托盘里的 **“退出程序”** 时，程序会先尝试停掉本工具启动的 OpenConnect，再退出 GUI。
- 首次关闭窗口会出现“最小化到托盘”的提示，可以勾选“不再提示”。

> [!TIP]
> 想把程序固定到任务栏：先创建一个指向 `Start-ECNU-OpenConnect-GUI.vbs` 的快捷方式，把快捷方式图标改成 `internal\ECNU-OpenConnect.ico`，再固定这个快捷方式。直接固定运行中的窗口，图标经常会变成 PowerShell 图标。

---

## 路由与分流策略

**默认不做全局 VPN。** 只有路由列表里的网段会被送进隧道，其余流量走本机原网络。

默认路由：

| 网段 | 用途 |
| --- | --- |
| `172.0.0.0/8` | 校内常规网段 |
| `202.120.0.0/16` | 校园网出口网段 |

工作方式：

1. GUI 把列表里的 CIDR 通过 `ECNU_SPLIT_ROUTES` 传给 `internal\openconnect\vpnc-script-win.js`。
2. 该脚本把这些网段写成 split-include 路由。
3. GUI 在连接后还会持续核对路由，网络切换或 IP 变化时自动补回。

支持的写法（必须是 CIDR 格式）：

```text
172.0.0.0/8          # 一大段内网
202.120.0.0/16       # 校园网段
202.120.80.2/32      # 单个 IP
```

> [!WARNING]
> 不要填写普通域名，也不要填写不带掩码的裸 IP。需要走 VPN 的其他校内网段，请自己在界面上“添加”。

---

## 账号与密码是怎么保存的

- `config.json` **不保存**用户名和密码。
- 勾选“保存密码到本机”并**登录成功**后，生成 `internal\ECNU-OpenConnect.login.xml`：
  - 用户名是明文；
  - 密码用 Windows DPAPI 加密，通常只有**当前 Windows 用户 + 当前机器**能解密。
- 取消勾选后成功登录一次，程序会删除已保存的信息。
- 认证失败时，程序会主动清除 GUI 保存的登录信息，避免一直用错密码重试。
- `internal\ECNU-OpenConnect.login.xml` 已写入 `.gitignore`，不会被提交。

---

## GUI 出问题时的命令行兜底

`script` 目录里保留了三个可以直接双击运行的脚本：

| 脚本 | 作用 |
| --- | --- |
| `script\Login-OpenConnect.cmd` | 命令行登录。有已保存的凭据就直接用，没有会提示输入 |
| `script\Stop-OpenConnect.cmd` | 正常停止本工具启动的 OpenConnect（优先按记录的进程信息退出） |
| `script\Force-Stop-OpenConnect.cmd` | 强制结束 `openconnect.exe`，仅在 GUI 状态异常、无法退出登录、进程残留时使用 |

---

## 配置文件

`internal\config.json` 保存通用配置，一般**不需要手动改**（要改默认路由，请直接在界面上增删）。

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `Host` | `vpn-ct.ecnu.edu.cn` | VPN 服务器 |
| `AuthGroup` | `ECNU` | 认证组 |
| `RememberPassword` | `true` | 是否默认勾选“保存密码到本机” |
| `AllowedRoutes` | `172.0.0.0/8`、`202.120.0.0/16` | 走 VPN 的网段 |
| `LoginTimeoutSeconds` | `50` | 登录等待上限（秒） |
| `UserAgent` / `VersionString` / `Os` | AnyConnect 兼容参数 | 沿用现有策略，用于兼容 ECNU 服务端 |
| `CloseToTrayTipShown` | `false` | 是否已提示过“关闭到托盘” |

---

## 目录结构

```text
ECNU-OpenConnect-GUI/
├─ Start-ECNU-OpenConnect-GUI.vbs   # 推荐启动入口（无控制台窗口）
├─ Start-ECNU-OpenConnect-GUI.cmd   # 备用启动入口（排查启动问题时用）
├─ internal/
│  ├─ ECNU-OpenConnect-GUI.ps1      # 主程序
│  ├─ config.json                   # 服务器、认证组、默认路由等配置
│  ├─ ECNU-OpenConnect.ico          # 程序图标
│  ├─ ECNU-OpenConnect.log          # 运行日志（本机生成）
│  ├─ ECNU-OpenConnect.login.xml    # 保存的登录信息（本机生成，请勿提交）
│  └─ openconnect/                  # 内置 OpenConnect 运行环境（含 DLL）
│     └─ vpnc-script-win.js         # 已改造成 ECNU 分流策略的路由脚本
├─ script/                          # 命令行兜底脚本
├─ licenses/                        # 第三方许可证原文
├─ LICENSE                          # 本项目原创代码的 MIT 许可证
└─ THIRD_PARTY_NOTICES.md           # 第三方组件来源与协议说明
```

---

## 常见问题

<details>
<summary><b>为什么一定要管理员权限？</b></summary>

OpenConnect 需要创建 VPN 虚拟网卡并修改 Windows 路由表，这两件事在 Windows 上都要求管理员权限。程序启动时会自动提权，所以每次都会弹 UAC。

</details>

<details>
<summary><b>点了关闭，为什么程序还在运行？</b></summary>

关闭窗口默认只把程序**最小化到托盘**，VPN 保持连接。要彻底退出，请右键托盘图标，选择“退出程序”。

</details>

<details>
<summary><b>登录看着成功了，按钮却没变成“退出登录”？</b></summary>

先打开日志确认 OpenConnect 是否还在运行。如果 GUI 状态异常：

1. 先跑 `script\Stop-OpenConnect.cmd`；
2. 仍然无效再跑 `script\Force-Stop-OpenConnect.cmd`；
3. 然后重新启动 GUI。

</details>

<details>
<summary><b>提示密码错误怎么办？</b></summary>

重新输入正确密码再登录。认证失败后程序会清除本机保存的登录信息，不会继续用旧密码重试。

</details>

<details>
<summary><b>普通网页没有走 VPN，是不是坏了？</b></summary>

这是**设计如此**。本工具默认分流，不做全局 VPN，只有“走 VPN 的路由”列表里的网段会进隧道。

</details>

<details>
<summary><b>连上了，但某个校内地址打不开？</b></summary>

多半是这个地址所在的网段不在路由列表里。在界面输入对应的 CIDR（例如 `202.120.0.0/16` 或更小的 `/24`）后点“添加”，再重新登录一次。

</details>

<details>
<summary><b>重复双击提示“已经在运行”？</b></summary>

程序是单实例的。点击托盘图标右键 → “显示窗口”即可，或先“退出程序”再重新打开。

</details>

<details>
<summary><b>任务栏图标显示不对（变成 PowerShell 图标）？</b></summary>

先彻底退出旧进程再打开。固定到任务栏时，建议先创建指向 `Start-ECNU-OpenConnect-GUI.vbs` 的快捷方式，把图标设为 `internal\ECNU-OpenConnect.ico`，再固定这个快捷方式。

</details>

<details>
<summary><b>我要干净地卸载 / 清理这个工具</b></summary>

1. 托盘右键“退出程序”；
2. 不放心时可再跑一次 `script\Force-Stop-OpenConnect.cmd`；
3. 删除整个 `ECNU-OpenConnect-GUI` 文件夹即可。登录信息、日志、PID 文件都在这个文件夹内部，不会写到系统其他位置。

</details>

---

## 发布前检查（维护者）

**不要提交**以下本机运行态文件（已在 `.gitignore` 中）：

```text
internal/ECNU-OpenConnect.login.xml
internal/ECNU-OpenConnect.username.txt
internal/ECNU-OpenConnect.password.xml
internal/ECNU-OpenConnect.log
internal/*.pid
internal/*.pid.json
internal/*.stop
internal/*-state.json
internal/*-backup.json
```

**必须保留**以下协议与说明文件：

```text
LICENSE
THIRD_PARTY_NOTICES.md
licenses/COPYING.LGPL-2.1-openconnect.txt
licenses/COPYING.GPL-vpnc-scripts.txt
```

提交前建议先执行 `git status`，确认变更列表里没有账号、日志和状态文件。

---

## 开源协议

- 本项目**原创 GUI 代码**采用 MIT License，见 [LICENSE](LICENSE)。
- 内置的 OpenConnect 运行时位于 `internal\openconnect`，当前版本为 **OpenConnect v9.21**，遵循 GNU LGPL v2.1 only，见 `licenses\COPYING.LGPL-2.1-openconnect.txt`。
- `internal\openconnect\vpnc-script-win.js` 基于 OpenConnect vpnc-scripts 项目的 Windows 脚本修改，用于 ECNU 分流策略，按其上游 GPL 协议处理，见 `licenses\COPYING.GPL-vpnc-scripts.txt`。
- 第三方组件的来源与发布注意事项见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- `internal\openconnect` 中的 DLL 依赖（GnuTLS、libxml2、nettle、iconv、zlib 等）属于第三方运行时组件，遵循各自上游许可证；正式发布二进制包前，建议核对所用运行时包附带的完整声明。

分发源码或二进制包时，请一并保留 `LICENSE`、`THIRD_PARTY_NOTICES.md` 与 `licenses` 目录。
