# 翻页笔（PageFlipper）

用安卓手机通过 WiFi 控制电脑上的 PPT / PDF 翻页的小工具。手机端按音量键或界面按钮即可上一页 / 下一页。

- 手机端：Android App（Java，手工构建，不依赖 Gradle）
- 电脑端：Python 脚本（标准库 + ctypes 模拟按键，无需第三方依赖）
- 通信：TCP Socket（局域网，单字节指令）

## 使用

### 1. 电脑端

```bash
python receiver.py
```

默认监听 **7777** 端口。手机与电脑必须在同一 WiFi 下。

> 说明：5555 位于 Windows 系统保留端口段（5500-5599）内，绑定会报 `WinError 10013`，因此本项目使用 7777。

### 2. 手机端

1. 安装 APK（可用 Android Studio 打开本仓库构建，或按下方"手工构建"打包）
2. 打开 App，填写电脑 IP（Windows 下 `ipconfig` 查看 IPv4 地址）与端口 7777
3. 点"连接"，状态显示"已连接"即为成功
4. 电脑上打开 PPT（按 F5 放映）或 PDF，手机 **音量加 = 下一页，音量减 = 上一页**

## 通信协议

手机 → 电脑，TCP 单字节指令：

| 字节 | 含义 | 电脑端动作 |
|---|---|---|
| `h` | 握手 | 回复 `ok` |
| `n` | 下一页 | 模拟 PageDown |
| `p` | 上一页 | 模拟 PageUp |

## 手工构建 APK（无需 Gradle）

前提：JDK 8+、Android SDK（platform-tools / build-tools / platforms）、Python。

```powershell
.\build.ps1            # 构建，输出 dist\PageFlipper-v1.0.apk
.\build.ps1 -Install   # 构建并安装到已连接的手机
```

> 注意：Windows PowerShell 5.1 下 `build.ps1` 必须以 **UTF-8 with BOM** 保存，否则中文注释会导致解析失败。

签名：首次构建会自动生成 `keys\local-debug.keystore`（仅本地测试用，请勿提交到仓库）。

## 文件结构

```
PageFlipper/
├── app/src/main/          # 安卓源码（Java + XML 资源）
├── build.ps1              # 手工构建脚本（aapt2 + javac + d8 + zipalign + apksigner）
├── receiver.py            # 电脑端接收程序
├── tools/package_apk.py   # 把 classes.dex 写入资源 APK
├── keys/                  # 本地签名证书（不提交）
└── dist/                  # 构建产物（不提交）
```

## 已知限制

- 音量键仅在 App 处于前台时生效；息屏 / 后台无法拦截（需要无障碍服务方案）
- 长连接无心跳，WiFi 空闲时可能被系统断开，断开后需手动重连
- 目前仅有翻页指令，无开始 / 结束放映（F5 / ESC）功能
