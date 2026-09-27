# dDostalker.github.io

Zola 博客，文章在 Obsidian「利刃」库里写作。

## 写作

文章放在 `posts/` 下，和利刃普通笔记完全一样：

```
posts/文章名.md              ← Obsidian 里直接写
posts/文章名.assets/图片.png  ← Obsidian 粘贴图片自动生成
```

- 文件名即 URL：`posts/my-post.md` → `https://ddostalker.github.io/my-post/`（想要英文 URL 就用英文文件名，标题写在 front matter 里）
- front matter 用 YAML，必需 `title` 和 `date`，可选 `tags` / `categories` / `description` / `draft`
- 不要用 `![[图片]]` 双链语法，Zola 不支持（普通 `![]()` 语法 Obsidian 粘贴时自动生成）

## 常用命令

在 `blog/` 目录下：

| 命令 | 作用 |
| ---- | ---- |
| `.\publish.ps1 -Preview` | 本地预览 http://127.0.0.1:1111 |
| `.\publish.ps1 -Build` | 构建到 `C:\Users\dDostalker\zola-build\ddostalker.github.io` |
| `.\publish.ps1 -Deploy` | 构建 + git 提交推送，触发 GitHub Actions 自动部署 |
| `.\publish.ps1` | 仅同步 posts/ → content/（一般不用单独跑） |

## 原理

`publish.ps1` 把平铺文章转换成 Zola 需要的结构再构建：

```
posts/my-post.md              →  content/my-post/index.md   (YAML → TOML)
posts/my-post.assets/*.png    →  content/my-post/my-post.assets/*.png
```

Zola 对 `index.md` 页面启用「资源同位」（assets colocation），旁边所有非 md 文件
会一起发布，所以 `![](my-post.assets/xx.png)` 这种相对路径本地（Obsidian）和网页
显示完全一致——和 mdBook 读利刃笔记是同一套机制。

## 部署

推送后 GitHub Actions（`.github/workflows/deploy.yml`）自动构建并发布到
GitHub Pages。首次使用需在仓库 **Settings → Pages → Build and deployment →
Source** 选择 **GitHub Actions**。

## 依赖

- Zola 0.20.0：`C:\Users\dDostalker\bin\zola.exe`（已加入用户 PATH）
- Obsidian 插件 custom-attachment-location，配置 `./${filename}.assets`
