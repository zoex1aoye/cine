# 01 域名发现模块（OSS / DoH / 日期盐）
- 状态： [x] 完成
- PRD：PRD-20261001-01
- 依赖：无
- 栈位：api
- 须装载：cine-flutter-dev

## 交付什么

新增 `lib/api/jp_domain_discovery.dart`：按官包顺序发现可用 API **根域**，测活规则含随机子域与 `japi.zxfmj.com` 特例。

## 验收

- [x] 导出可被 `JpApi` 调用的发现 API（如 resolve / probe）
- [x] 流水线顺序：缓存候选 ∪ `japi.zxfmj.com` → OSS `domain.txt` → DoH TXT `pyvemnlu.cc` → 日期盐 `*.com`
- [x] 测活：`GET {base}/v2/settings/appAuthConfig`，业务 code==1；非 japi 使用 `https://{rand6}.{root}/api`
- [x] 劣质根域常量含 `api.ipixiv.com`、`release.ipixiv.com`（供接入层作废）
- [x] `dart analyze` 无 error（`flutter analyze`/`test` 本机因 SDK pub 拉 git 挂起，未完整跑通）

## 笔记

官包常量对照：OSS `https://jdomain.oss-accelerate.aliyuncs.com/domain.txt`；DoH alidns / doh.pub / 1.1.1.1；盐五枚；MD5(date+salt).substring(9,19)+".com"。
非 japi 根域测活最多 3 次随机重试。
