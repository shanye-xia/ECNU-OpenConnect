ECNU OpenConnect GUI

简介
- 这是一个面向 Windows 的 ECNU OpenConnect 简洁图形工具。
- 只负责 OpenConnect 登录、退出登录、路由分流和日志查看，不包含其他 VPN 客户端功能。
- OpenConnect 运行环境已放在 internal\openconnect 目录中，用户不需要自己安装 OpenConnect，也不需要配置 PATH。
- 默认不走全局代理/全局 VPN：连接后只让配置的网段走 VPN，普通互联网流量仍走本机原网络。

适用环境
- Windows 10 / Windows 11。
- 需要 PowerShell 5.1 或更高版本；Windows 10/11 通常自带。
- 需要管理员权限运行。OpenConnect 创建虚拟网卡和写入路由表时必须提权。
- 如果电脑从未安装过 OpenConnect/Wintun 相关驱动，首次使用时可能仍需要安装或允许驱动加载。

快速开始
1. 下载或复制整个 ECNU-OpenConnect-GUI 文件夹。
2. 双击 Start-ECNU-OpenConnect-GUI.vbs 启动。
   - 推荐使用这个入口，启动时不会留下蓝色 PowerShell 窗口。
   - 如果需要看启动过程，可以改用 Start-ECNU-OpenConnect-GUI.cmd。
3. 如果 Windows 弹出 UAC 管理员权限确认，请选择“是”。
4. 在窗口中输入账号和密码。
5. 点击“登录”。
6. 登录成功后，主按钮会自动变成红色“退出登录”。
7. 需要断开 VPN 时，点击“退出登录”即可。

界面说明
- 账号：填写 ECNU VPN 账号。
- 密码：填写对应密码。
- 记住密码：勾选后，登录成功才会保存登录信息；登录失败不会覆盖原来的可用密码。
- 登录：未连接时显示，用于发起 OpenConnect 登录。
- 退出登录：已连接时显示，按钮为红色，用于断开当前 OpenConnect 连接。
- 路由列表：显示当前允许走 VPN 的网段。
- 添加路由：输入 CIDR 后添加到列表，例如 202.120.0.0/16。
- 删除路由：选中列表中的路由后删除。
- 打开日志：打开当前 OpenConnect 日志文件。
- 打开日志路径：打开日志所在目录。

托盘行为
- 点击窗口右上角关闭按钮时，程序默认最小化到系统托盘，不会直接退出。
- 托盘图标右键菜单可以执行：
  - 显示窗口
  - 登录或退出登录
  - 打开日志
  - 打开日志路径
  - 退出程序
- 从托盘选择“退出程序”时，程序会先尝试停止本工具启动的 OpenConnect，然后退出 GUI。
- 如果首次关闭窗口时出现托盘提示，可以勾选“不再提示”。
- 如果任务栏图标没有刷新，请先从托盘右键“退出程序”，再重新打开。固定到任务栏时，建议先创建一个指向 Start-ECNU-OpenConnect-GUI.vbs 的快捷方式，并把快捷方式图标设置为 internal\ECNU-OpenConnect.ico，再固定该快捷方式。

路由策略
- 默认路由列表包含 172.0.0.0/8。
- 本工具不会让所有流量默认走 VPN。
- GUI 中添加的 CIDR 会通过 ECNU_SPLIT_ROUTES 传给 internal\openconnect\vpnc-script-win.js。
- vpnc-script-win.js 会把这些网段写为 split-include 路由。
- 支持的格式示例：
  - 172.0.0.0/8
  - 202.120.0.0/16
  - 202.120.80.2/32
- 不要输入普通域名或不带掩码的 IP；请使用 CIDR 格式。

命令行兜底脚本
script 目录里保留了三个可直接运行的命令行脚本，适合 GUI 异常时兜底使用：

- script\Login-OpenConnect.cmd
  - 使用内置 OpenConnect 环境登录。
  - 如果已经保存过登录信息，会尝试读取保存的账号和密码。
  - 如果没有保存信息，会提示输入。

- script\Stop-OpenConnect.cmd
  - 正常停止本工具启动的 OpenConnect。
  - 优先按本工具记录的进程信息退出。

- script\Force-Stop-OpenConnect.cmd
  - 强制停止 openconnect.exe。
  - 仅建议在 GUI 状态异常、无法退出登录、OpenConnect 残留时使用。

账号和密码保存
- config.json 不保存用户名，也不保存密码。
- 登录成功并勾选“记住密码”后，会生成本地登录文件：
  - internal\ECNU-OpenConnect.login.xml
- 这个文件中：
  - 用户名是明文字段。
  - 密码由 Windows DPAPI 加密。
  - 加密密码通常只能由当前 Windows 用户在当前机器上解密。
- 如果取消“记住密码”，程序会删除已保存的登录信息。
- 如果认证失败，程序会清理 GUI 保存的登录信息，避免一直使用错误密码重试。
- internal\ECNU-OpenConnect.login.xml 已写入 .gitignore，不应提交到 GitHub。

配置文件
internal\config.json 保存通用配置：
- Host：VPN 服务器，默认 vpn-ct.ecnu.edu.cn。
- AuthGroup：认证组，默认 ECNU。
- RememberPassword：是否默认勾选记住密码。
- AllowedRoutes：默认走 VPN 的 CIDR 路由列表。
- LoginTimeoutSeconds：登录等待时间。
- UserAgent / VersionString / Os：OpenConnect 兼容参数，沿用现有脚本策略。
- CloseToTrayTipShown：是否已经显示过关闭到托盘提示。

一般不需要手动修改 config.json。需要改默认路由时，优先在 GUI 里添加或删除。

文件说明
- Start-ECNU-OpenConnect-GUI.vbs：推荐启动入口，无控制台窗口。
- Start-ECNU-OpenConnect-GUI.cmd：备用启动入口，适合排查启动问题。
- LICENSE：本项目原创 GUI 代码的 MIT 协议，不覆盖第三方组件。
- THIRD_PARTY_NOTICES.md：OpenConnect、vpnc-script-win.js 等第三方组件的来源和协议说明。
- licenses\COPYING.LGPL-2.1-openconnect.txt：OpenConnect 的 LGPL v2.1 协议文本。
- licenses\COPYING.GPL-vpnc-scripts.txt：vpnc-scripts 的 GPL 协议文本。
- script\Login-OpenConnect.cmd：命令行保底登录入口。
- script\Stop-OpenConnect.cmd：命令行保底停止入口。
- script\Force-Stop-OpenConnect.cmd：命令行强制停止入口。
- internal\ECNU-OpenConnect-GUI.ps1：主程序。
- internal\config.json：服务器、路由列表等通用配置。
- internal\ECNU-OpenConnect.login.xml：本机保存的登录信息，发布时不要提交。
- internal\ECNU-OpenConnect.log：OpenConnect 日志。
- internal\openconnect：工具自带的 OpenConnect 运行环境。
- internal\openconnect\vpnc-script-win.js：已修改为 ECNU 分流策略的 Windows 路由脚本。

常见问题
1. 为什么需要管理员权限？
   OpenConnect 需要创建 VPN 网络接口并修改 Windows 路由表，这些操作需要管理员权限。

2. 为什么关闭窗口后程序还在？
   关闭窗口默认只是隐藏到托盘。要完全退出，请右键托盘图标，选择“退出程序”。

3. 登录成功了，但按钮没有变成“退出登录”怎么办？
   先打开日志确认 OpenConnect 是否还在运行。如果 GUI 状态异常，可以使用 script\Stop-OpenConnect.cmd；仍无法停止时再使用 script\Force-Stop-OpenConnect.cmd。

4. 登录失败提示密码错误怎么办？
   重新输入正确密码再登录。认证失败后，程序会清理 GUI 保存的登录信息，避免继续使用旧密码。

5. 为什么发布到 GitHub 后不应该有我的账号？
   账号密码保存在 internal\ECNU-OpenConnect.login.xml，这个文件已被 .gitignore 排除。发布前仍建议检查 Git 变更列表，确认没有提交 login.xml、日志、PID、状态文件。

6. 为什么任务栏图标还是不对？
   先彻底退出旧进程，再重新打开。固定任务栏时，建议创建一个指向 Start-ECNU-OpenConnect-GUI.vbs 的快捷方式，把图标改为 internal\ECNU-OpenConnect.ico，然后固定这个快捷方式。

7. 为什么普通网页没有走 VPN？
   这是预期行为。本工具默认分流，不走全局 VPN。只有路由列表里的网段会走 VPN。

发布前检查
- 确认不要提交以下本机运行态文件：
  - internal\ECNU-OpenConnect.login.xml
  - internal\ECNU-OpenConnect.log
  - internal\*.pid
  - internal\*.pid.json
  - internal\*.stop
  - internal\*-state.json
  - internal\*-backup.json
- 确认保留以下协议文件：
  - LICENSE
  - THIRD_PARTY_NOTICES.md
  - licenses\COPYING.LGPL-2.1-openconnect.txt
  - licenses\COPYING.GPL-vpnc-scripts.txt
- 如果发布包含 internal\openconnect 的二进制包，请保留第三方声明和许可证文本。

开源协议和发布说明
- 本项目原创 GUI 代码采用 MIT License，见 LICENSE。
- 本项目打包的 OpenConnect 运行时位于 internal\openconnect，当前检测到的版本为 OpenConnect v9.21。OpenConnect 使用 GNU LGPL v2.1 only，见 licenses\COPYING.LGPL-2.1-openconnect.txt。
- internal\openconnect\vpnc-script-win.js 基于 OpenConnect vpnc-scripts 项目的 Windows 脚本修改，用于 ECNU 分流策略。vpnc-scripts 相关文件按其上游 GPL 协议处理，见 licenses\COPYING.GPL-vpnc-scripts.txt。
- THIRD_PARTY_NOTICES.md 记录第三方组件来源、协议和发布注意事项。发布源码或二进制包时，请保留 LICENSE、THIRD_PARTY_NOTICES.md 和 licenses 目录。
- internal\openconnect 目录里的 DLL 依赖属于第三方运行时组件，仍遵循各自上游许可证。正式发布二进制包前，建议核对所使用 OpenConnect Windows 运行时包附带的完整第三方依赖声明。
- 不要提交本机运行态文件，例如 internal\ECNU-OpenConnect.login.xml、日志、PID、状态文件等；这些已经写入 .gitignore。
