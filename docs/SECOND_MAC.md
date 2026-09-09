# 第二台 Mac 的最少接入步骤

## 首次接入

1. 安装 Git、Node.js 22.18+（22.x）或 24.11+与 npm。为自己的 GitHub 账号配置写入权限（SSH 或系统凭据管理）；不要把 token 放入 remote URL、命令记录或仓库文件。不需要复制第一台电脑的 credentials.env 或记忆档案。
2. 选择自己的代码目录，首次克隆：

   ```sh
   git clone https://github.com/tqytx666-create/life-ledger.git
   cd life-ledger
   git fetch origin
   git switch --track origin/docs/multi-mac-pilot
   ```

   此试点说明尚在独立分支；合并后新接入者留在 main 即可。若已有本地仓库，先检查未提交改动、确认远端确实是本仓库，再按协作规范接手，不要覆盖原目录。
3. 在 Codex 中打开刚克隆的本地目录，让任务先阅读 AGENTS.md、README.md 和 docs/STATUS.md。两台设备各自打开本地副本，项目说明经 Git 同步。
4. 验证无需真实数据的构建：

   ```sh
   cd app
   npm ci
   npm run build
   cd ..
   git status --short
   ```

5. 验证成功后，由当前负责人交接或各建任务分支。可以先创建 `docs/imac-onboarding` 分支，只在 STATUS.md 填写设备代号、版本、构建结果，提交并推送后开草稿 PR。不得直接修改/推送 gh-pages，不运行 deploy.sh。

## 可直接交给新任务的说明

> 这是人生账本仓库 tqytx666-create/life-ledger。先读 AGENTS.md、README.md、docs/STATUS.md 与 docs/COLLABORATION.md，检查工作区并 fetch。先完成本机依赖安装与构建验证，再用独立分支记录接入结果并提交草稿 PR。不改功能、不操作真实财务数据、不上线。不把本机其他财务系统视为本项目。

## 接入验收

只有第二台 Mac 实际完成克隆、构建、独立分支推送，且第一台 fetch 后能够看到该提交，才记为跨设备代码交接验证完成。该验收不包含真实账户、数据库或生产发布验证。
