extends RefCounted
## Stable mission IDs are persisted; descriptions and rewards are content data.
const CONTENT_VERSION="missions_1"
const DEFINITIONS=[
 {"id":"collect_medical","title":"补齐急救物资","description":"从封锁区带回医疗物资，在营地上交 2 件。救济物资不可用于交付。","kind":"collect","target":"loot_medical","required":2,"reward_currency":400},
 {"id":"survey_depot","title":"恢复前哨联络","description":"到达信号站完成勘察，并成功撤离后回营地领取奖励。","kind":"visit","target":"signal_station","required":1,"reward_currency":500},
 {"id":"eliminate_officer","title":"清除仓区指挥官","description":"击败仓区指挥官，并成功撤离后回营地领取奖励。","kind":"kill","target":"guard_06","required":1,"reward_currency":700},
]

func definitions() -> Array:
 return DEFINITIONS.duplicate(true)

func get_definition(id: String) -> Dictionary:
 for definition in DEFINITIONS:
  if definition.id==id: return definition.duplicate(true)
 return {}

func new_state() -> Dictionary:
 var result={}
 for definition in DEFINITIONS: result[definition.id]={"status":"available","progress":0}
 return result
