package com.flipper.local;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;

/**
 * 翻页笔（第一版）：通过 WiFi 用 TCP Socket 给电脑发送翻页指令。
 * 电脑端运行 receiver.py，收到 'n' 模拟 PageDown（下一页），收到 'p' 模拟 PageUp（上一页）。
 */
public final class MainActivity extends Activity {

    private final Handler handler = new Handler(Looper.getMainLooper());

    private EditText etIp;
    private EditText etPort;
    private Button btnConnect;
    private TextView tvStatus;
    private Button btnPrev;
    private Button btnNext;

    // 网络对象用 volatile 修饰，保证多个线程之间可见
    private volatile Socket socket;
    private volatile boolean connecting;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        // 演示时保持屏幕常亮，免得翻页翻着屏幕灭了
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        etIp = findViewById(R.id.et_ip);
        etPort = findViewById(R.id.et_port);
        btnConnect = findViewById(R.id.btn_connect);
        tvStatus = findViewById(R.id.tv_status);
        btnPrev = findViewById(R.id.btn_prev);
        btnNext = findViewById(R.id.btn_next);

        btnConnect.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (socket != null && socket.isConnected()) {
                    disconnect();
                } else {
                    connect();
                }
            }
        });

        btnPrev.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                send('p');
            }
        });

        btnNext.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                send('n');
            }
        });
    }

    /** 连接电脑。网络操作必须放子线程，Android 不允许主线程做网络。 */
    private void connect() {
        if (connecting) {
            return;
        }
        final String ip = etIp.getText().toString().trim();
        final int port;
        try {
            port = Integer.parseInt(etPort.getText().toString().trim());
        } catch (NumberFormatException e) {
            Toast.makeText(this, "端口格式不对", Toast.LENGTH_SHORT).show();
            return;
        }
        if (ip.length() == 0) {
            Toast.makeText(this, "请填写电脑 IP", Toast.LENGTH_SHORT).show();
            return;
        }

        connecting = true;
        setStatus("正在连接 " + ip + ":" + port + " ...");
        new Thread(new Runnable() {
            @Override
            public void run() {
                Socket s = null;
                try {
                    s = new Socket();
                    s.connect(new InetSocketAddress(ip, port), 4000); // 4 秒连接超时
                    socket = s;
                    // 连接成功：发一个握手字节，电脑端回 ok
                    writeByte(s, 'h');
                    handler.post(new Runnable() {
                        @Override
                        public void run() {
                            setStatus("已连接 " + ip);
                            btnConnect.setText(R.string.disconnect);
                        }
                    });
                } catch (final Exception e) {
                    if (s != null) {
                        try {
                            s.close();
                        } catch (IOException ignored) {
                        }
                    }
                    socket = null;
                    handler.post(new Runnable() {
                        @Override
                        public void run() {
                            setStatus("连接失败：" + e.getMessage());
                        }
                    });
                } finally {
                    connecting = false;
                }
            }
        }, "connect-thread").start();
    }

    /** 断开连接 */
    private void disconnect() {
        final Socket s = socket;
        socket = null;
        if (s != null) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        s.close();
                    } catch (IOException ignored) {
                    }
                }
            }, "close-thread").start();
        }
        setStatus("未连接");
        btnConnect.setText(R.string.connect);
    }

    /**
     * 发送一个字节指令。
     * 每次按键开一个短线程发送（按键频率低，这样最简单直观）。
     */
    private void send(final char cmd) {
        final Socket s = socket;
        if (s == null || !s.isConnected()) {
            Toast.makeText(this, "还没连接电脑", Toast.LENGTH_SHORT).show();
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    writeByte(s, cmd);
                } catch (IOException e) {
                    // 发送失败：连接可能断了，通知 UI
                    socket = null;
                    handler.post(new Runnable() {
                        @Override
                        public void run() {
                            setStatus("连接已断开");
                            btnConnect.setText(R.string.connect);
                        }
                    });
                }
            }
        }, "send-thread").start();
    }

    /** 写一个字节。synchronized 保证同一时刻只有一个线程在写，防止两个按键挤在一起。 */
    private void writeByte(Socket s, char cmd) throws IOException {
        synchronized (s) {
            OutputStream out = s.getOutputStream();
            out.write(cmd);
            out.flush();
        }
    }

    /**
     * 音量键翻页（核心功能）：
     * 返回 true 表示"这个按键被我消费掉了"，系统就不会再弹音量条。
     * 注意：只有本 App 在前台时才会拦截，这是第一版的安全设计。
     */
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            send('n');      // 音量加 = 下一页
            return true;
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            send('p');      // 音量减 = 上一页
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        disconnect();
    }

    private void setStatus(String text) {
        tvStatus.setText(text);
    }
}
