# 两台 Mac 的任务分工与交接

## 开始任务

先读取 AGENTS.md 与 STATUS.md，确认路径、仓库及任务归属。设备使用自选代号，例如 Mac-A / Mac-B，不填写个人资料。通过草稿 PR 的描述声明负责人、范围与验收标准；创建 PR 前先在当前沟通中协调，避免两边同时认领。Git 不提供文件锁，发生重叠先协调再编辑。

```sh
git status --short
git fetch origin
git switch -c task/<任务号>-<短名> origin/main
```

工作目录有未提交改动时，不执行切换；在已 fetch 后另建目录：

```sh
git worktree add -b task/<任务号>-<短名> ../life-ledger-<任务号> origin/main
```

命令中的尖括号是占位符，需要替换。不同项目各用自己的仓库；同一项目的并行任务各用分支与目录。不要用云盘同步 `.git`、node_modules 或凭据。

## 提交和交接

```sh
git diff --stat
git diff -- <本次文件>
git add -- <本次文件>
git diff --cached --check
git diff --cached
git commit -m "docs: describe the change"
git push -u origin HEAD
```

创建或更新草稿 PR，使用下面的交接模板。完成时更新 STATUS.md。不要把没有提交/推送的本地结果写成已交付。记录中避免真实金额、账户标识与私人路径。

```text
任务号 / 状态（进行中、待审、阻塞、已合并）：
负责人 / 设备代号：
分支 / PR：
目标与验收标准：
文件范围 / 与其他任务的依赖：
实际完成：
验证命令与结果：
未完成项 / 风险：
接手步骤：
发布状态 / 是否获得该次发布确认：
```

## 另一台电脑续接同一任务

原负责人先提交、推送并交接，暂停该分支的写入。接手者 fetch 后，新本地分支使用 `git switch --track origin/<任务分支>`；若已存在该分支，先确认工作区干净，再 `git switch <任务分支>` 和 `git pull --ff-only`。出现分叉立即停止 pull 并协调，不强推覆盖。两台机器同时工作时仍应使用不同任务分支。

## 合并前

指定一位集成人负责合并。工作区干净后执行 `git fetch origin` 和 `git merge origin/main`，解决冲突时保留双方意图；共享分支不随意 rebase/强推。重新构建并运行与改动相关的验证，检查 PR 完整 diff 中没有无关改动或私人内容，再推送更新。只有实际通过的验证才记为通过。

PR 中明确哪些验收尚未完成，按用户授权范围合并。合并不会代替上线确认。合并后各设备 fetch 并 `git switch main && git pull --ff-only`；旧任务分支确认无遗漏后再清理。
