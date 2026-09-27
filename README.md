# dDostalker.github.io

个人博客，文章在本地 Obsidian利刃库里写作，会把一些精选的内容丢上来。

## 常用命令


| 命令                       | 作用                                                        |
| ------------------------ | --------------------------------------------------------- |
| `.\publish.ps1 -Preview` | 本地预览 http://127.0.0.1:1111                                |
| `.\publish.ps1 -Build`   | 构建到 `C:\Users\dDostalker\zola-build\ddostalker.github.io` |
| `.\publish.ps1 -Deploy`  | 构建 + git 提交推送，触发 GitHub Actions 自动部署                      |
| `.\publish.ps1`          | 仅同步 posts/ → content/                                     |

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

- Zola 0.20.0：`C:\Users\dDostalker\bin\zola.exe
