# 归拢 · Gatherboard 官网

归拢（Gatherboard）的静态官网。产品类别为本地项目看板，包含产品介绍、交互式界面预览和 macOS 安装包下载。

## 本地预览

在本目录运行：

```bash
python3 -m http.server 8765 --directory dist
```

然后访问 `http://127.0.0.1:8765/`。

## 发布内容

- `dist/index.html`：网站页面
- `dist/styles.css`：响应式视觉样式
- `dist/app.js`：标签切换、滚动进入和校验值复制
- `dist/downloads/归拢-1.0.0-universal.dmg`：macOS 通用安装包

安装包 SHA-256：`0493d53afcc949041c143086b313ecf7eabbdfef869bc7fe15d9dcc3c48cd79e`
