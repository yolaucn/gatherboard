# 归拢 · Gatherboard 官网

归拢（Gatherboard）的静态官网。产品类别为本地项目看板，包含产品介绍、交互式界面预览和 macOS 安装包下载。

线上官网：<https://w5gxsw7rv5.coze.site>。

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
- `dist/downloads/归拢-1.1.1-universal.dmg`：macOS 通用安装包（当前版本）
- `dist/downloads/归拢-1.1.1-universal.dmg.sha256`：安装包校验文件
- `dist/downloads/归拢-1.1.1-发版说明.md`：发版说明
- `dist/downloads/归拢-1.0.0-universal.dmg`：保留的旧版安装包

1.1.1 安装包 SHA-256：`22c70f38ee2d2c80206b58e6dbe330e7c8b0854cbb2691c01e4d8b9bdee26f2e`

本目录用于官网部署，下载链接对应 1.1.1。GitHub 版本发布地址：<https://github.com/yolaucn/gatherboard/releases/tag/v1.1.1>；线上官网部署独立进行。
