# 光合作用要点 - DeepSeek

> 来源: https://chat.deepseek.com/a/chat/s/abc123
> 导出时间: 2026-09-22 17:40

---

帮我把光合作用的核心要点整理一下，顺便给一段计算光反应 ATP 产量的示例代码。

### 光合作用核心要点

光合作用可拆成两个阶段，分别在**类囊体薄膜**和*叶绿体基质*中进行。

- 光反应：水的光解产生 O₂、NADPH 和 ATP
- 暗反应：CO₂ 被固定为三碳糖，消耗 ATP 与 NADPH
- 总反应式：6CO₂ + 12H₂O → C₆H₁₂O₆ + 6O₂ + 6H₂O

示例代码：

```python
def atp_yield(photons):
    """每 8 个光子约产生 3 个 ATP"""
    return photons // 8 * 3

print(atp_yield(64))  # 24
```

更严谨的推导可以参考 [这份综述](https://example.com/photosynthesis)，里面有完整的化学计量说明。

| 阶段 | 场所 | 产物 |
| --- | --- | --- |
| 光反应 | 类囊体薄膜 | ATP、NADPH、O₂ |
| 暗反应 | 叶绿体基质 | 三碳糖 |

> 注意：暗反应并不需要黑暗，只是不直接依赖光照。