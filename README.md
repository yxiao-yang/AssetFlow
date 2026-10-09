# AssetFlow · 资产流

个人资产管理与记账 iOS App。支持收支记账、快捷指令支付截图识别，以及人民币资产管理。

## 运行

用 Xcode 打开 `AssetFlow.xcodeproj`，选择 iPhone 模拟器，按 Command + R。
最低 iOS 17。真机运行时，在 Signing & Capabilities 中选择自己的开发团队。

## 日常账本

- 明细：月度支出、收入、结余和笔数；切换月份；按天分组；商户、分类、扣款方式和时间；搜索与收支筛选。
- 图表：分类环形图、每日收支柱状图、分类排行及占比。点击排行进入对应月份、分类和收支类型的明细。
- 日历：每天的收入和支出，点击日期查看当天流水。
- 可手动录入和编辑收入、支出。待确认截图独立展示，排除在全部统计之外。
- 明细页的眼睛按钮隐藏金额；金额隐藏时图表也隐藏。
- 以上为 AssetFlow 当前功能，不代表完整实现 iCost 的账户、预算、退款等功能。

## 一次性配置截图记账

可在 App 右上角「设置 → 截图记账快捷指令」查看完整引导，并跳转到系统快捷指令编辑器。创建动作和轻点背面绑定仍需在系统界面完成。

先将 App 安装到 iPhone 并打开一次。在「快捷指令」中创建「截图记账」：

1. 添加系统动作「截屏」（Take Screenshot）。
2. 添加 AssetFlow 动作「识别支付截图并记账」。将「支付截图」参数设为上一步的截屏结果。「分类」留空，运行时弹出选择；填写分类则每次使用固定分类。
3. 如需查看结果，追加「显示结果」，使用上一步结果。此步骤可能产生额外确认交互，可按喜好省略。
4. 在「设置 → 辅助功能 → 触控 → 轻点背面」绑定这个快捷指令，或在支持的 iPhone 上绑定操作按钮。
5. 停留在微信／支付宝的账单详情页，触发快捷指令，识别后在系统弹窗中选择分类再入账；取消选择不保存。无需手动选照片，也不需要自己打开 App 导入。

系统第一次可能要求确认权限。模拟器不能完整验证背部轻点、操作按钮和其他支付 App，需要真机测试。iOS 27 的截图事件自动化是可选入口，当前实现不依赖该版本，也未实现通知记账。

## 识别和确认

- 用 Apple Vision 在本机识别中文、英文，无需外部 AI 或 API Key。
- 提取明确的金额、商户、支付渠道、扣款方式、交易时间和交易单号。分类按商户关键词推荐。
- 仅当金额唯一、必要字段完整、状态明确、文字可信度足够时自动保存为支出。
- 缺少时间、商户、扣款方式，或出现多个金额、退款、转账、收入、外币、疑似重复时，保存到「待确认」，不计入合计。
- 重复提交已确认的相同截图不会新增；相同截图仍待确认时会重新识别并更新原记录；同交易单号或近时间同商户同金额记录进入待确认。
- 在记录详情里查看原始截图、识别原文；可编辑支出、确认待处理记录，或删除非消费记录。
- 已支持明确金额标签及带人民币符号的金额。页面布局、OCR 质量和字段差异可能导致待确认。尚未承诺覆盖所有支付页面。
- 原图和识别文字保存在本机，删除记录时一并删除。截图中明确的银行卡尾号、微信零钱、支付宝余额或余额宝可匹配已创建的人民币账户；匹配不唯一时不自动关联，可在记录编辑页选择账户。
- 支付成功页和交易详情页提供的信息不同。商品数量、单价只能在源页面存在时进一步开发，当前版本没有商品明细解析。

## 数据

SwiftUI + SwiftData；金额以整数分保存。新增字段使用默认值或可选值，以支持旧记录的轻量迁移；已通过旧版账本到新增资产模型的本地迁移检查，迁移与快捷指令完整流程仍需真机验证。尚未实现备份或云同步。

## 解析规则检查

在仓库根目录执行：

```sh
xcrun swiftc AssetFlow/PaymentParser.swift Tests/PaymentParserChecks.swift -o /tmp/assetflow-parser-checks
/tmp/assetflow-parser-checks
```

检查金额精度、多金额歧义、折扣排除、退款、转账和外币处理。OCR 及快捷指令还需真实账单截图验证。


## 统计检查

```sh
xcrun swiftc AssetFlow/LedgerAnalytics.swift Tests/LedgerAnalyticsChecks.swift -o /tmp/assetflow-analytics-checks
/tmp/assetflow-analytics-checks
```

包含收入、支出、结余、分类排行、月份边界、不同月份天数和待确认记录排除。
Debug 编译开启 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` 后，可通过启动参数 `--demo-ledger` 使用独立内存示例；附加 `--demo-charts` 或 `--demo-calendar` 打开对应页面。示例不写入真实账本，正式构建不包含示例逻辑。

## 资产管理

「资产」页展示折合人民币总资产、原币账户余额、类型占比和可选择 7 天、30 天、90 天、1 年（365 天）、全部的资产趋势。示例数据只在 Debug 的独立内存模式中出现，不会进入个人账本。

- 账户类型简化为「资金账户、投资账户、现金、其他资产」，账户名称始终自定义。
- 储蓄卡、存折、微信零钱、支付宝余额和余额宝统一按资金账户展示；旧记录的细分类在存储中保留，名称、余额和关联收支不变。
- 资金账户可填写机构、尾号和备注，在折叠的「存款／收益信息」中选填收益率参考及到期日。
- 投资账户：现金和股票市值分开，合计计入资产；逐只股票手动记录名称、代码、数量、成交均价／成本价和当前参考价，展示市值、成本、浮动盈亏与盈亏率。
- 列表、详情、编辑资料及余额核对页面显示「上次更新时间」。编辑账户资料、核对余额和更新持仓时保存新时间，并保留「前次更新时间」；收支和转账不会覆盖手动更新时间。旧账户从已有余额快照或创建时间恢复显示，不能据此认为外部余额已实时同步。
- 所有新账户、股票价格和转账金额均以人民币记录，不再提供币种选择或汇率换算。旧外币账户、持仓及汇率数据留存在本地，仅用于兼容已有数据，不参与资产展示、账户选择或人民币统计，不自动将原币金额改成人民币。
- 在账户详情右上角或底部点击「删除账户」，确认后删除账户、持仓和余额核对记录。账本收支保留并解除账户关联；涉及该账户的转账保留在其他账户中，避免改变其他账户的余额，对方显示「已删除账户」。删除后的账户不再参与当前或历史资产统计。
- 股票价格当前手动核对，明确标记来源和价格时间。初版采用全手动录入，暂不接入行情服务。单笔买入填成交价，多笔买入填平均成本价；当前参考价用于估算市值和浮动盈亏。

### 录入和日常使用

先为每个账户填写**当前余额**。证券账户创建时只填现金，随后添加股票持仓；不要把含股票市值的总额填成现金。

收支可关联人民币非证券账户。只有最近一次余额核对之后的已确认收支会改变余额，避免已包含在当前余额中的历史账单再次扣款。待确认记录不改变余额。未关联的记录继续参与账本统计，资产页列出这些记录以便补充关联。

自己账户之间移动资金请使用「账户转账」，不会计为收入或支出。人民币账户间转账保持总资产不变；证券转出只能使用记录的可用现金。手续费可单独记录支出。

「核对当前余额」保存新的余额快照，不作为收入。持仓核对保存新的证券估值并保留此前历史，不会自动执行买卖或调整现金；数量变化后需核对券商现金。历史趋势从首次录入开始，不补造更早的余额；变化包含新增账户、删除账户和核对，不能等同投资收益。

目前不包含负债管理、券商交易流水、分红自动同步、银行直连或自动同步余额。

### 资产检查与预览

```sh
xcrun swiftc AssetFlow/AssetMath.swift Tests/AssetMathChecks.swift -o /tmp/assetflow-asset-math
/tmp/assetflow-asset-math
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift Tests/AssetIntegrationChecks.swift -o /tmp/assetflow-asset-integration
/tmp/assetflow-asset-integration
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift Tests/AccountUpdateChecks.swift -o /tmp/assetflow-account-updates
/tmp/assetflow-account-updates
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift Tests/CNYAccountDeletionChecks.swift -o /tmp/assetflow-account-deletion
/tmp/assetflow-account-deletion
```

覆盖金额与估值精度、余额快照边界、待确认收支排除、转账、截图账户匹配、旧外币排除和证券现金。Debug 启动参数 `--demo-ledger --demo-assets` 打开独立内存示例资产页面。

## 同一存折里的多笔定期

创建或编辑「资金账户」，开启「管理多笔定期存款」。先核对**账户总余额＝活期余额＋所有未取出的定期本金**，然后在账户详情逐笔添加本金、存入日、到期日、年利率和备注。录入已有定期只拆分账户余额，不额外增加资产。录入金额不能超过可拆分的活期余额；若总额漏录，需要先核对总余额。

- 账户详情分开显示活期余额、定期本金和预计到期利息，存款按到期日排列，已结清记录保留。
- 预计利息按「本金 × 年利率 × 实际天数 ÷ 365」估算并四舍五入到分，不计入资产和收入，不代表银行实际结算规则。
- 到期后显示「已到期 · 未取出」，不会自动增加收入或自动转存。本版不包含到期提醒。
- 「取出」支持整笔转入本账户活期或另一个人民币非证券账户。本金仅作为内部调整／账户间转账，实际到账利息单独记录为理财收入。提前取出也须填写银行实际利息，不能直接使用预计值。
- 「转存」保留原记录并标为已转存，创建同一账户的新定期。实际利息先入账；新本金可以包含利息，也可以仅转存原本金，剩余资金留在活期。记录中保留前一笔存款的关联。
- 「删除录入记录」用于纠正误录，仅删除未结清明细，总余额不变，本金归回活期；真实取出请使用「取出」。已结清记录只读，避免重复结算。
- 普通账户转账只允许使用活期／可用现金。定期本金需先取出；核对总余额不能低于未取出的定期本金。关联账单造成活期余额为负时显示核对提示。
- 删除账户时同步清理定期明细，账本收支及其他账户的转账记录仍保留。

```sh
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift AssetFlow/TermDepositRepository.swift Tests/TermDepositChecks.swift -o /tmp/assetflow-term-checks
/tmp/assetflow-term-checks
```

Debug 启动参数 `--demo-ledger --demo-term-deposits` 可查看独立内存中的多笔定期示例，不写入个人账本。

资产趋势时间范围检查：

```bash
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift Tests/AssetHistoryRangeChecks.swift -o /tmp/assetflow-history-checks
/tmp/assetflow-history-checks
```

覆盖五档范围、历史起点、人民币账户过滤、当日收支和空数据。快捷指令创建跳转、轻点背面与真实支付截图识别仍需真机验证。


截图识别补充：按文字位置将两列账单字段还原为同一行，支持「对方账户」「创建时间」「自动扣款成功」及全角括号。金额／日期识别分数偏低时才追加可信度核对，不用状态栏和页面底部文字的最低分数否决整张账单。按本项目的个人记账口径，支付宝小荷包「自动攒」成功扣款记为消费；其他账户存取、转账、充值仍需核对。

OCR 排版检查与原图验证（可选传入本地截图路径，不上传）：

```bash
xcrun swiftc AssetFlow/PaymentParser.swift AssetFlow/PaymentOCRText.swift Tests/PaymentOCRChecks.swift -o /tmp/assetflow-ocr-checks
/tmp/assetflow-ocr-checks
# 对小荷包自动攒截图额外验证：
/tmp/assetflow-ocr-checks /path/to/pocket-screenshot.png
```

原有待确认记录不会在升级时自动重算；再次提交完全相同的截图会重新解析该条记录，已确认记录仍去重。


常见支付宝账单识别：

- 顶部交易名称与「收款方全称」分开解析；店铺显示名优先用于流水商户名称。
- 「余额宝＋收益发放」识别为收入／理财收益，支持没有正负号的收益金额，入账账户匹配余额宝。普通退款、转账、充值仍进入核对。
- Vision 的 0.5 识别分数在这些原图中对应有效金额和日期，不等于 50% 的入账准确率；数值字段低于 0.5 才追加低可信度原因，同时仍验证完整日期、金额歧义、交易状态与特殊交易。
- 本机已用四张用户原图验证小荷包消费、余额宝收益、商店消费和个人收款码消费；这不是对所有账单准确率的估计。

余额宝原图检查参数：`/tmp/assetflow-ocr-checks /path/to/screenshot.png --yuebao-income`；零食店与板面原图分别使用 `--shop` 和 `--noodle`。


微信账单补充：支持「2026年10月7日 15:01:51」格式、「商户全称」和跨行商品描述；分类使用商品说明与商户名共同判断，商品说明保存在备注中，不能确定的分类保留「其他」。类别是否确定不会单独阻止已完整识别的账单入账。

已保存的待确认记录可在详情点击「重新识别原图」，原图仍在本机处理；更新该条记录，不新增一笔。已确认记录保持去重。当前未接入云端 AI，也未将截图发送到远端。

识别入账与原图重试检查：

```bash
xcrun swiftc AssetFlow/Expense.swift AssetFlow/AssetMath.swift AssetFlow/TermDepositMath.swift AssetFlow/AssetModels.swift AssetFlow/AssetHistoryRange.swift AssetFlow/AssetRepository.swift AssetFlow/PaymentParser.swift AssetFlow/ScreenshotLedgerService.swift Tests/ScreenshotLedgerChecks.swift -o /tmp/assetflow-screenshot-ledger
/tmp/assetflow-screenshot-ledger
```

微信原图检查参数：`/tmp/assetflow-ocr-checks /path/to/screenshot.png --wechat`。真实原图检查均在本机进行，测试仓库不保存用户截图。

截图分类选择：快捷指令动作按收入／支出提供对应分类，识别建议的分类排在前面，最终分类以用户选择为准。选择分类不会消除金额、日期或交易状态的核对原因，有疑问的截图仍进入待确认。弹窗只在运行截图记账快捷指令时出现，普通截屏不会自行触发。已有快捷指令升级后可保持分类参数为空；若系统缓存旧动作，可删除并重新添加记账动作。系统弹窗交互与取消流程需要在 iPhone 上验证。
