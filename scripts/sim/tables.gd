## 静态数据表：地点、职业原型、性格特征。M1 先放在脚本里，M2 迁到 JSON。
extends RefCounted

## 地点类型。en 是英文正文里的写法，plate_en 是地图名牌和地点标题上的短名。kind 用于事件模板的 requires；archive 表示这里有可查的档案；night 表示晚上有人。
const LOCATIONS := [
	{"id": "office", "plate_en": "Office", "en": "the newspaper office", "name": "报社", "kind": "office"},
	{"id": "mill", "plate_en": "Sawmill", "en": "the sawmill", "name": "锯木厂", "kind": "mill", "ads": true},
	{"id": "church", "plate_en": "Church", "en": "the church", "name": "教堂", "kind": "church", "sunday": true},
	{"id": "tavern", "plate_en": "Tavern", "en": "the tavern", "name": "酒馆", "kind": "tavern", "night": true, "ads": true},
	{"id": "store", "plate_en": "Store", "en": "the general store", "name": "杂货店", "kind": "store", "ads": true, "archive": true},
	{"id": "post", "plate_en": "Post Office", "en": "the post office", "name": "邮局", "kind": "post", "archive": true},
	{"id": "hall", "plate_en": "Town Hall", "en": "the town hall", "name": "镇公所", "kind": "hall", "archive": true},
	{"id": "clinic", "plate_en": "Clinic", "en": "the clinic", "name": "诊所", "kind": "clinic", "archive": true},
	{"id": "station", "plate_en": "Station", "en": "the railway station", "name": "火车站", "kind": "station"},
	{"id": "school", "plate_en": "School", "en": "the schoolhouse", "name": "学校", "kind": "school"},
	{"id": "farm_a", "plate_en": "North Farm", "en": "the north farm", "name": "北边农场", "kind": "farm"},
	{"id": "farm_b", "plate_en": "Bend Farm", "en": "the river-bend farm", "name": "河湾农场", "kind": "farm"},
	{"id": "river", "plate_en": "Riverbank", "en": "the riverbank", "name": "河边", "kind": "river", "outdoor": true},
	{"id": "bridge", "plate_en": "Bridge", "en": "the bridge", "name": "桥头", "kind": "bridge", "outdoor": true},
	{"id": "woods", "plate_en": "Woods", "en": "the woods", "name": "树林", "kind": "woods", "outdoor": true},
]

## 职业原型。
## count: [min,max] 每局人数；work: 工作地点 id；power: 0 平民 1 有点地位 2 有权势；
## wealth: 0 穷 1 普通 2 富；female: 女性概率；literate: 识字概率；keeper: 看管哪处档案
const OCCUPATIONS := [
	{"id": "mayor", "en": "mayor", "name": "镇长", "count": [1, 1], "work": "hall", "power": 2, "wealth": 2, "female": 0.0, "literate": 1.0},
	{"id": "priest", "en": "priest", "name": "牧师", "count": [1, 1], "work": "church", "power": 2, "wealth": 1, "female": 0.0, "literate": 1.0},
	{"id": "owner", "en": "mill owner", "name": "厂主", "count": [1, 1], "work": "mill", "power": 2, "wealth": 2, "female": 0.0, "literate": 1.0, "advertiser": true},
	{"id": "foreman", "en": "foreman", "name": "工头", "count": [1, 1], "work": "mill", "power": 1, "wealth": 1, "female": 0.0, "literate": 0.7},
	{"id": "worker", "en": "mill hand", "name": "工人", "count": [10, 14], "work": "mill", "power": 0, "wealth": 0, "female": 0.1, "literate": 0.4},
	{"id": "doctor", "en": "doctor", "name": "医生", "count": [1, 1], "work": "clinic", "power": 1, "wealth": 2, "female": 0.1, "literate": 1.0, "keeper": "clinic"},
	{"id": "nurse", "en": "nurse", "name": "护士", "count": [1, 1], "work": "clinic", "power": 0, "wealth": 1, "female": 0.9, "literate": 1.0},
	{"id": "teacher", "en": "schoolteacher", "name": "教师", "count": [1, 2], "work": "school", "power": 1, "wealth": 1, "female": 0.6, "literate": 1.0},
	{"id": "grocer", "en": "grocer", "name": "店主", "count": [1, 1], "work": "store", "power": 1, "wealth": 1, "female": 0.3, "literate": 0.9, "advertiser": true, "keeper": "store"},
	{"id": "postman", "en": "postman", "name": "邮差", "count": [1, 1], "work": "post", "power": 0, "wealth": 1, "female": 0.1, "literate": 1.0, "keeper": "post"},
	{"id": "sheriff", "en": "sheriff", "name": "警长", "count": [1, 1], "work": "hall", "power": 2, "wealth": 1, "female": 0.0, "literate": 0.9},
	{"id": "clerk", "en": "town clerk", "name": "书记员", "count": [1, 1], "work": "hall", "power": 1, "wealth": 1, "female": 0.4, "literate": 1.0, "keeper": "hall"},
	{"id": "barkeep", "en": "tavern keeper", "name": "酒馆老板", "count": [1, 1], "work": "tavern", "power": 1, "wealth": 1, "female": 0.3, "literate": 0.7, "advertiser": true},
	{"id": "stationmaster", "en": "stationmaster", "name": "站长", "count": [1, 1], "work": "station", "power": 1, "wealth": 1, "female": 0.0, "literate": 1.0},
	{"id": "widow", "en": "widow", "name": "寡妇", "count": [2, 3], "work": "home", "power": 0, "wealth": 1, "female": 1.0, "literate": 0.6},
	{"id": "farmer", "en": "farmer", "name": "农户", "count": [4, 6], "work": "farm", "power": 0, "wealth": 0, "female": 0.4, "literate": 0.4},
	{"id": "drifter", "en": "drifter", "name": "流浪汉", "count": [1, 2], "work": "station", "power": 0, "wealth": 0, "female": 0.1, "literate": 0.3, "informer": true},
	{"id": "newcomer", "en": "newcomer", "name": "新来的", "count": [1, 2], "work": "tavern", "power": 0, "wealth": 1, "female": 0.5, "literate": 0.8},
	{"id": "tailor", "en": "tailor", "name": "裁缝", "count": [1, 1], "work": "store", "power": 0, "wealth": 1, "female": 0.7, "literate": 0.7},
	{"id": "smith", "en": "blacksmith", "name": "铁匠", "count": [1, 1], "work": "mill", "power": 0, "wealth": 1, "female": 0.0, "literate": 0.5},
	{"id": "fisher", "en": "fisherman", "name": "渔夫", "count": [2, 3], "work": "river", "power": 0, "wealth": 0, "female": 0.1, "literate": 0.3},
	{"id": "maid", "en": "housemaid", "name": "女佣", "count": [2, 3], "work": "home", "power": 0, "wealth": 0, "female": 1.0, "literate": 0.5, "informer": true},
	{"id": "apprentice", "en": "apprentice", "name": "学徒", "count": [1, 2], "work": "store", "power": 0, "wealth": 0, "female": 0.2, "literate": 0.6, "informer": true},
	{"id": "veteran", "en": "old soldier", "name": "退伍兵", "count": [1, 2], "work": "tavern", "power": 0, "wealth": 0, "female": 0.0, "literate": 0.6},
]

## 性格特征。bucket 决定反应表那一列；其余是模拟里用到的倾向。
## 每人抽三条，互斥组内不同时出现。
const TRAITS := [
	{"id": "timid", "en": "timid", "name": "怯懦", "bucket": "timid", "excl": "temper"},
	{"id": "practical", "en": "practical", "name": "务实", "bucket": "practical", "excl": "temper"},
	{"id": "hot", "en": "hot-tempered", "name": "暴躁", "bucket": "hot", "excl": "temper"},
	{"id": "vain", "en": "vain", "name": "虚荣", "excl": "pride"},
	{"id": "pious", "en": "pious", "name": "虔诚"},
	{"id": "greedy", "en": "greedy", "name": "贪财", "excl": "money"},
	{"id": "gossip", "en": "gossipy", "name": "多嘴", "excl": "mouth"},
	{"id": "tight", "en": "tight-lipped", "name": "守口如瓶", "excl": "mouth"},
	{"id": "grudge", "en": "grudging", "name": "记仇", "excl": "heart"},
	{"id": "kind", "en": "kind", "name": "宽厚", "excl": "heart"},
	{"id": "drinker", "en": "a drinker", "name": "好酒"},
	{"id": "ambitious", "en": "ambitious", "name": "野心", "excl": "pride"},
	{"id": "suspicious", "en": "suspicious", "name": "多疑", "excl": "faith"},
	{"id": "gullible", "en": "gullible", "name": "轻信", "excl": "faith"},
	{"id": "honest", "en": "honest", "name": "正直", "excl": "truth"},
	{"id": "sly", "en": "sly", "name": "狡猾", "excl": "truth"},
]

## 版位曝光倍率
const SLOT_MULT := {"head": 3.0, "second": 2.0, "third": 1.0, "small": 0.3}
const SLOT_NAME := {"head": "头条", "second": "二条", "third": "三条", "small": "小栏"}
const SLOT_NAME_EN := {"head": "Front page", "second": "Second story", "third": "Third story", "small": "Notices"}
## 语气
const TONE_MULT := {"calm": 0.8, "neutral": 1.0, "hot": 1.4}
const TONE_NAME := {"calm": "克制", "neutral": "中立", "hot": "煽动"}
const TONE_CIRC := {"calm": 0.02, "neutral": 0.04, "hot": 0.09}
## 街头零售的倍数：煽动的标题在柜台边最好卖，点名的比化名、匿名的好卖
const TONE_RETAIL := {"calm": 0.8, "neutral": 1.0, "hot": 1.3}
const NAMING_RETAIL := {"named": 1.0, "alias": 0.7, "anon": 0.45}
## 署名方式
const NAMING_MULT := {"named": 1.0, "alias": 0.6, "anon": 0.3}
const NAMING_NAME := {"named": "点名", "alias": "化名", "anon": "匿名"}

## 取料来源的玩家可见可信度
const SOURCE_CRED := {"interview": 0.6, "eavesdrop": 0.4, "archive": 0.9, "informer": 0.7, "letter": 0.3, "witness": 1.0, "visitor": 0.5, "public": 0.8}
const SOURCE_NAME := {"interview": "采访", "eavesdrop": "偷听", "archive": "档案", "informer": "线人", "letter": "匿名信", "witness": "亲眼所见", "visitor": "来访", "public": "众所周知"}


static func location_by_id(id: String) -> Dictionary:
	for l in LOCATIONS:
		if l.id == id:
			return l
	return {}


static func occupation_by_id(id: String) -> Dictionary:
	for o in OCCUPATIONS:
		if o.id == id:
			return o
	return {}


## 职业名：家眷、赋闲这类不在表里的职业另给。
const EXTRA_OCC_EN := {"homemaker": "homemaker", "retired": "retired resident"}


static func occ_en(occ_id: String) -> String:
	var o := occupation_by_id(occ_id)
	if not o.is_empty():
		return o.en
	return EXTRA_OCC_EN.get(occ_id, occ_id)


static func trait_by_id(id: String) -> Dictionary:
	for t in TRAITS:
		if t.id == id:
			return t
	return {}
