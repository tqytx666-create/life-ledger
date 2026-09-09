# 人生账本

Vue 3 + Vite 的个人/家庭账本前端，后端使用 Supabase。此仓库是两台 Mac 协作试点的共同代码与交接来源。

## 项目地图

| 路径 | 用途 |
| --- | --- |
| app/src/pages、components | 页面与组件 |
| app/src/lib | 数据访问、格式化及业务辅助逻辑 |
| migrations | 数据库迁移；执行会改变数据库 |
| functions | 后端函数 |
| scripts | 数据库及行情维护工具，不属于普通构建步骤 |
| deploy.sh | 现有生产发布脚本，使用前必读发布说明 |

## 本地构建

新设备使用 Node.js 22.18+（22.x）或 24.11+ 及 npm，以满足锁定依赖的 engines 要求。当前机器为 Node 22.14 / npm 10.9，安装时出现 Babel 的版本要求警告，不能将该版本当作新设备推荐版本。依赖由 app/package-lock.json 固定。

```sh
cd app
npm ci
npm run build
```

产物在 `app/dist`。`npm run dev` 可启动本地前端，但本地运行并不自动隔离后端；先确认测试数据和后端配置，再进行交互。普通构建无需提供 GitHub token 或数据库管理密钥。

## 协作入口

- [任务与交接规范](docs/COLLABORATION.md)
- [第二台 Mac 接入](docs/SECOND_MAC.md)
- [当前进度](docs/STATUS.md)
- [上线与回滚](docs/RELEASE.md)

这是公开仓库，只保存可公开的代码、项目说明和脱敏进度。不要把私人移交资料、本地记忆、真实账单或凭据同步到这里。另一台设备上的其他财务系统需单独确认项目归属。
