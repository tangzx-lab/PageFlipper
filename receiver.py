#!/usr/bin/env python3
"""翻页笔电脑端接收程序（第一版）

用法：
    python receiver.py [端口]

监听 TCP，收到 'n' 模拟 PageDown（下一页），收到 'p' 模拟 PageUp（上一页）。
只用 Python 标准库 + Windows ctypes，无需安装任何第三方库。

注意：
    手机和电脑必须在同一个 WiFi 下。
    首次运行 Windows 防火墙可能弹窗，选"允许访问"。
"""
import ctypes
import socket
import sys
import threading

PORT = 7777  # 5555 在 Windows 系统保留端口段(5500-5599)内，绑定会报 WinError 10013，故改用 7777

VK_PRIOR = 0x21          # PageUp
VK_NEXT = 0x22           # PageDown
KEYEVENTF_KEYUP = 0x0002

user32 = ctypes.windll.user32


def press(vk):
    """模拟按下再松开一个键。"""
    user32.keybd_event(vk, 0, 0, 0)                 # 按下
    user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)   # 松开


def handle(client, addr):
    print(f"[连接] {addr}")
    try:
        while True:
            data = client.recv(16)
            if not data:
                break
            for b in data:
                c = chr(b)
                if c == "n":
                    press(VK_NEXT)
                    print("[翻页] 下一页 (PageDown)")
                elif c == "p":
                    press(VK_PRIOR)
                    print("[翻页] 上一页 (PageUp)")
                elif c == "h":
                    client.sendall(b"ok")
                    print("[握手] 手机已连接")
    except Exception as e:
        print(f"[错误] {e}")
    finally:
        client.close()
        print(f"[断开] {addr}")


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", port))
    srv.listen(5)
    print(f"翻页笔接收端已启动，监听端口 {port}")
    print("1) 在电脑上打开 ipconfig 查 IPv4 地址（无线局域网那行）")
    print("2) 手机连同一 WiFi，打开“翻页笔”App，填电脑 IP 和端口，点连接")
    print("3) 按手机音量加/减或点按钮翻页。Ctrl+C 退出")
    try:
        while True:
            client, addr = srv.accept()
            threading.Thread(target=handle, args=(client, addr), daemon=True).start()
    except KeyboardInterrupt:
        print("\n已退出")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
