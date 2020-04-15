// Документация и новые версии функции: https://github.com/meta110/powerbi/tree/master/vk
// https://vk.com/dev/ads
let
	VK_ADS = (
		optional access_token as text, // токен доступа
		optional account_id as number, // идентификатор аккаунта
		optional client_id as number, // идентификатор клиента для рекламных агентств
		optional level as text, // уровень детализации отчета: аккаунт, клиент, кампания, объявления,
		optional period as text, // период группировки: за все время, по месяцам, по дням
		optional date_from as date, // дата начала диапазона. 0 - день или месяц создания
		optional date_to as date, // дата окончания диапазона. 0 - сегодня или текущий месяц
		optional method as text, // метод API
		optional ids as list, // список идентифиаторов
		optional q as record // параметры запроса для метода method (остальные игнорируются)
	) => 
	let

	// настройки
	API_version = "5.103", // смотрите действующие версии API здесь https://vk.com/dev/versions
	delay = 1, // задержка в секундах между последовательными запросами к API, чтобы не получить флуд в функции answer
	depth = 100, // оптимизация производительности: ограничивает кол-во записей, из которых будут извлечены названия полей в функции getRecordFieldNames

	renameFields = {
		{"id", "ID"}, // в Posts Reach и demographics - ID объекта
		{"reach_subscribers", "Охват подписчиков"},
		{"reach_total", "Суммарный охват"},
		{"links", "Переходы по ссылке"},
		{"to_group", "Переходы в сообщество"},
		{"join_group", "Вступления в сообщество"},
		{"report", "Жалоб на запись"},
		{"hide", "Скрытий записи"},
		{"unsubscribe", "Отписавшихся участников"},
		{"video_views_start", "Стартов просмотра видео"},
		{"video_views_3s", "Досмотров видео до 3 сек."},
		{"video_views_25p", "Досмотров видео до 25%"},
		{"video_views_50p", "Досмотров видео до 50%"},
		{"video_views_75p", "Досмотров видео до 75%"},
		{"video_views_100p", "Досмотров видео до 100%"},
		{"type", "Объект"},
		{"day", "Дата"},
		{"demographics", "Демография"},
		{"impressions_rate", "Доля показов"},
		{"clicks_rate", "Доля кликов"},
		{"value", "Значение"},
		{"name", "Название"},
		{"month", "Месяц"},
		{"spent", "Бюджет"},
		{"impressions", "Показы"},
		{"clicks", "Клики"},
		{"reach", "Охват"},
		{"join_rate", "Доля вступлений"},
		{"lead_form_sends", "Лиды"},
		{"goals", "Цели"},
		{"views_times", "Частота показов"},
		{"day_from", "Дата начала"},
		{"day_to", "Дата окончания"},
		{"overall", "За всё время"},
		{"status", "Статус"},
		{"day_limit", "Дневной лимит"},
		{"all_limit", "Общий лимит"},
		{"views_limit", "Лимит показов"},
		{"start_time", "Дата начала"},
		{"stop_time", "Дата окончания"},
		{"create_time", "Дата создания"},
		{"update_time", "Дата обновления"},
		{"campaign_id", "ID кампании"},
		{"approved", "Модерация"}, //0 — объявление не проходило модерацию; 1 — объявление ожидает модерации; 2 — объявление одобрено; 3 — объявление отклонено
		{"goal_type", "Тип цели"}, //1 — показы; 2 — переходы; 3 — отправка заявок; 5 — вступления в сообщество
		{"cost_type", "Тип оплаты"}, //0 — оплата за переходы; 1 — оплата за показы; 3 — оптимизированная оплата за показы
		{"category1_id", "Тематика 1"},
		{"category2_id", "Тематика 2"},
		{"age_restriction", "Возрастн. ограничение"},
		{"events_retargeting_groups", "События групп ретаргетинга"}, // https://vk.com/dev/ads.getAds
		{"ad_format", "Формат объявления"}, //1 — изображение и текст; 2 — большое изображение; 3 — эксклюзивный формат; 4 — продвижение сообществ или приложений, квадратное изображение; 5 — приложение в новостной ленте (устаревший); 6 — мобильное приложение; 9 — запись в сообществе; 11 — адаптивный формат; 12 — истории.
		{"cpc", "CPC"},
		{"ad_platform", "Площадка"}, // https://vk.com/dev/ads.getAds
		{"cpm", "CPM"},
		{"impressions_limit", "Лимит показов на пользователя"}
	},

	renameValues = #table(
		type table [Field = text, Code = text, Value = text],
		{{"ad_format", "1", "изображение и текст"},
		{"ad_format", "2", "большое изображение"},
		{"ad_format", "3", "эксклюзивный формат"},
		{"ad_format", "4", "квадр. изображение (сообщество или приложение)"},
		{"ad_format", "5", "приложение в новостной ленте"},
		{"ad_format", "6", "мобильное приложение"},
		{"ad_format", "9", "запись в сообществе"},
		{"ad_format", "11", "адаптивный формат"},
		{"ad_format", "12", "истории"},
		{"cost_type", "0", "переходы"},
		{"cost_type", "1", "показы"},
		{"cost_type", "3", "оптимиз. показы"},
		{"goal_type", "1", "показы"},
		{"goal_type", "2", "переходы"},
		{"goal_type", "3", "заявки"},
		{"goal_type", "5", "вступления"},
		{"ad_platform", "0", "ВК и партнеры"},
		{"ad_platform", "1", "только ВК"},
		{"ad_platform", "all", "все площадки"},
		{"ad_platform", "desktop", "полная версия сайта"},
		{"ad_platform", "mobile", "мобильный сайт и приложения"},
		{"status", "0", "остановлено"},
		{"status", "1", "запущено"},
		{"status", "2", "удалено"},
		{"approved", "0", "не проходило"},
		{"approved", "1", "ожидает"},
		{"approved", "2", "одобрено"},
		{"approved", "3", "отклонено"},
		{"demographics", "sex", "Пол"},
		{"demographics", "age", "Возраст"},
		{"demographics", "sex_age", "Пол и возраст"},
		{"demographics", "cities", "Город"},
		{"value", "f", "женщины"},
		{"value", "m", "мужчины"},
		{"value", "f;12-18", "жен. 12-18"},
		{"value", "f;18-21", "жен. 18-21"},
		{"value", "f;21-24", "жен. 21-24"},
		{"value", "f;24-27", "жен. 24-27"},
		{"value", "f;27-30", "жен. 27-30"},
		{"value", "f;30-35", "жен. 30-35"},
		{"value", "f;35-45", "жен. 35-45"},
		{"value", "f;45-100", "жен. 45-100"},
		{"value", "m;12-18", "муж. 12-18"},
		{"value", "m;18-21", "муж. 18-21"},
		{"value", "m;21-24", "муж. 21-24"},
		{"value", "m;24-27", "муж. 24-27"},
		{"value", "m;27-30", "муж. 27-30"},
		{"value", "m;30-35", "муж. 30-35"},
		{"value", "m;35-45", "муж. 35-45"},
		{"value", "m;45-100", "муж. 45-100"},
		{"value", "other", "другой"},
		{"type", "ad", "объявление"},
		{"type", "campaign", "кампания"}}
	),

	transformValues = {
		{"spent", each Text.Replace(_,".",",")},
		{"start_time", each if _ = "0"  then "0" else fromUnix(_)},
		{"stop_time", each if _ = "0"  then "0" else fromUnix(_)},
		{"create_time", each fromUnix(_)},
		{"update_time", each fromUnix(_)}
	},

	// проверяю ошибки в параметрах
	err = try 
		if access_token = null then
			error Error.Record(
				"Не задан access_token", 
				"Укажите токен доступа или получите новый на странице:", 
				"https://meta110.github.io/services/vkauth/"
			)
		else if level <> null and not List.Contains({"ad","campaign","client","office", "adlist"}, level) then 
			error Error.Record(
				"Неверное значение level", // в оригинале ids_type см. https://vk.com/dev/ads.getStatistics
				level, 
				"Допустимые значения (для получения статистики):" &
					"#(cr)""office"" — по кабинету,"&
					"#(cr)""client"" — по клиенту," &
					"#(cr)""campaign"" — по кампаниям," &
					"#(cr)""ad"" — по объявлениям или ""adlist"" — список объявлений"
			)
		else if not List.Contains({"day","month","overall"}, period) then 
			error Error.Record(
				"Неверное значение period", 
				period,
				"Допустимые значения:" &
					"#(cr)""day"" — статистика по дням;" &
					"#(cr)""month"" — статистика по месяцам;" &
					"#(cr)""overall"" или null — статистика за всё время."
			)
		else if ( method = "postsreach" or method = "demographics" ) 
				and not List.Contains({"ad","campaign"}, level) and account_id = null then 
			error Error.Record(
				"Не указаны все необходимые параметры для метода", 
				method,
					"#(cr)Идентификатор аккаунта не должен быть пустым." &
					"#(cr)Допустимые значения level:" &
					"#(cr)""ad"" — статистика по объявлениям;" &
					"#(cr)""campaign"" — статистика по кампаниям." &
					"#(cr)Перечислите в ids список идентификаторов (не более 100), соответствующих level."
			)
		else null,

	errs = [
		vals = {"One of the parameters specified was missing or invalid: account_id is invalid",
			"One of the parameters specified was missing or invalid: client_id is invalid"},
		keys = {"Указан неверный ID аккаунта",
		"Указан неверный ID клиента"}
	],


	common = [
		access_token = access_token, 
		v = API_version,
		lang = "ru"
	], // доступы

	// обертка к Web Contents с задержкой между запросами
	answer = (rp as text, optional q as record) =>
		Function.InvokeAfter(
			()=>Web.Contents(
				"https://api.vk.com/method/", [
					RelativePath = rp,
					Query = if q = null then common else q & common
				]), 
			#duration(0,0,0,delay) // задержка, чтобы не засчитали флуд
		),
	
	// распаковка ответа
	unwrap = (a) =>
	let 
		doc = Json.Document(a),
		response = doc[response],
		tab = 
			if Value.Type(response) = type list 
			then Table.FromRecords(response,getRecordFieldNames(doc[response]),MissingField.UseNull)
			else response
	in
		if Record.HasFields(doc,"response") then tab else doc,

	// извлекает уникальные названия полей из начала списка записей
	getRecordFieldNames = (r as list) =>
	let
		first = List.FirstN(List.RemoveNulls(r), depth),
		names = List.Transform(first, Record.FieldNames),
		unique = List.Distinct(List.Combine(names))
	in unique,

	// ответ и распаковка
	res = (m as text, optional p as record) => unwrap(answer(m, p)),

	// собираю параметры запроса 
	params = 
		(if q = null then [] else q) 
		& (if account_id = null then [] else [ account_id = Text.From(account_id) ])
		& (if client_id = null or client_id = 0 then [] else [ client_id = Text.From(client_id) ]),

	// выбираю подходящий список статистик
	r1 = 
		if account_id = null then // неизвестен ID рекламного кабинета
			res("ads.getAccounts")
		else if client_id = null then
			res("ads.getClients", params)
		else if level = "campaign" or level = null then
			res("ads.getCampaigns", params)
		else if level = "ad" or level = "adlist" then
			res("ads.getAds", params)
		else null,

	numbers2text = (l as list) => Text.Combine(List.Transform(l, Text.From),","),
	
	//all_ids = Table.Column(r1,"id"),
	
	fix_ids = if level = "office" then Text.From(account_id)
			else if level = "client" then Text.From(client_id) 
			else if ids = null then numbers2text(r1[id])
			else numbers2text(ids),
	
	// параметры запроса статистики
	Query = [
		ids_type = level,
		ids = fix_ids,
		period = period,
		date_from = if date_from = null then "0" else formatDate(date_from),
		date_to = if date_to = null then "0" else formatDate(date_to) 
	] & (if List.Contains({"ad","campaign"}, level) then [ stats_fields = "views_times"] else []),

	period = if period = null then "overall" else period,
	
	// форматирование даты по условию
	formatDate = (d) => 
		if period = "day" then Date.ToText(d, "yyyy-MM-dd")
		else if period = "month" then Date.ToText(d, "yyyy-MM")
		else "0",

	// распаковка статистики
	expandStats = (stat as table) =>
	let
		#"Expanded stats" = Table.ExpandListColumn(stat, "stats"),
		#"Expanded stats1" = Table.ExpandRecordColumn(#"Expanded stats", "stats", getRecordFieldNames(#"Expanded stats"[stats]))
	in #"Expanded stats1",

	expandDemographics = (tal as table) => let
		unpivot = Table.Unpivot(
				expandStats(tal), 
				{"sex","age","sex_age","cities"}, "demographics", "stats"),
		add = Table.AddColumn(expandStats(unpivot), "Custom", each if [name] = null then [value] else [name]),
		remove = Table.RemoveColumns(add,{"name","value"}),
		return = Table.RenameColumns(remove,{"Custom","value"})
	in return,
	
	//запрос статистики
	allStatistics = 
		if method = null then res("ads.getStatistics", Query & params) 
		else if method = "demographics" then 
			//res("ads.getDemographics", Query & params)
			expandDemographics(res("ads.getDemographics", Query & params))
		else if method = "postsreach" then
			res("ads.getPostsReach", params & [ids_type = level, ids = fix_ids])
		else null, //res(method, Query & params),

	// разбираю ошибки
	check4err = (val) => let
		err = if Record.HasFields(val,"error") then List.PositionOf(errs[vals], val[error][error_msg]) else -1,
		result = if err >= 0 then errs[keys]{err} else val
	in 
		if Value.Is(val, type record)
		then result 
		else formatTable(val),
	// 
	fromUnix = (tm) => #datetime(1970, 1, 1, 3, 0, 0) + #duration(0, 0, 0, Number.From(tm)),

	Table.ReplaceValues = (tab as table, replacements as table) as table => let
		names = Table.ColumnNames(replacements),
		Field = List.PositionOf(names,"Field"), // колонка
		Code = List.PositionOf(names,"Code"), // старое значение
		Value = List.PositionOf(names,"Value"), // новое значение
		leave_only_exsisting = Table.SelectRows(replacements, each List.Contains(Table.ColumnNames(tab),[Field])), // оставляю в таблице замен данные только по тем колонкам, которые есть в основной таблице
		all_text = Table.TransformColumnTypes(tab,List.Transform(List.Distinct(leave_only_exsisting[Field]),each {_,type text})), // все колонки с заменами делаю текстовыми
		buffer = List.Buffer(Table.ToRows(leave_only_exsisting)),
		return = List.Accumulate(
				buffer,
				Table.Buffer(all_text),
				(t,r)=>Table.ReplaceValue(t,r{Code},r{Value},Replacer.ReplaceValue,{r{Field}})
			)
	in return,
	
	// форматирую данные в таблице и перевожу столбцы на русский
	formatTable = (tab as table) => let
		transform = Table.TransformColumns(tab,transformValues, null, MissingField.Ignore),
		replace = Table.ReplaceValues(transform, renameValues),
		rename = Table.RenameColumns(replace,renameFields,MissingField.Ignore)
	in rename, 
	
	// результат
	result = 
		if method <> null and allStatistics = null
		then res(method,params)
		else if level <> null and level <> "adlist"
		then try expandStats(allStatistics) otherwise allStatistics
		else r1,
	return = if err[HasError] then err[Error] else check4err(result)
	in
		return,
		//errs[keys]{List.PositionOf(errs[vals], return[error][error_msg])}
		//r1,
		//res("ads.getPostsReach", params & [ids_type = level, ids = fix_ids])
//in
	//get,
	fnType = type function(
		optional access_token as (type text
			meta [
				Documentation.FieldCaption = "Токен авторизации",
				Documentation.FieldDescription = "Для получения ключа следуйте инструкциям https://meta110.github.io/services/vkauth/",
                Documentation.SampleValues = {"d2d0811bbf257fa285c29603377171f1a50b05988f8b047afdaf7950d6d89c11fa99de415d273bb419"}
            ]
        ), // токен доступа
		optional account_id as (type number
			meta [
				Documentation.FieldCaption = "ID аккаунта",
				Documentation.FieldDescription = "Укажите идентификатор нужного аккаунта",
                Documentation.SampleValues = {12}
            ]
        ), // идентификатор аккаунта
		optional client_id as (type number
			meta [
				Documentation.FieldCaption = "ID клиента",
				Documentation.FieldDescription = "Укажите идентификатор клиента (для агентств)",
                Documentation.SampleValues = {null}
            ]
        ), // идентификатор клиента для рекламных агентств
		optional level as (type text
			meta [
				Documentation.FieldCaption = "Детализация статистики",
				Documentation.FieldDescription = "Допустимые значения:" &
					"#(cr)""office"" — по кабинету,"&
					"#(cr)""client"" — по клиенту," &
					"#(cr)""campaign"" — по кампаниям," &
					"#(cr)""ad"" — по объявлениям или ""adist"" — список объявлений",
                Documentation.AllowedValues = {"ad","campaign","client","office", "adlist"}
            ]
        ), // уровень детализации отчета: аккаунт, клиент, кампания, объявления,
		optional period as (type text
			meta [
				Documentation.FieldCaption = "Детализация периода",
				Documentation.FieldDescription = "Допустимые значения:" &
					"#(cr)""day"" — статистика по дням;" &
					"#(cr)""month"" — статистика по месяцам;" &
					"#(cr)""overall"" или null — статистика за всё время.",
				Documentation.AllowedValues = {"day","month","overall"}
			]
		), // период группировки: за все время, по месяцам, по дням
		optional date_from as (type date
			meta [
				Documentation.FieldCaption = "Дата начала",
				Documentation.FieldDescription = "Укажите дату или null (автоподстановка даты создания)",
				Documentation.SampleValues = {null}
			]
		), // дата начала диапазона. 0 - день или месяц создания
		optional date_to as (type date
			meta [
				Documentation.FieldCaption = "Дата окончания",
				Documentation.FieldDescription = "Укажите дату или null (автоподстановка текущей даты)",
				Documentation.SampleValues = {null}
			]
		), // дата окончания диапазона. 0 - сегодня или текущий месяц
		optional method as (type text
			meta [
				Documentation.FieldCaption = "Метод",
				Documentation.FieldDescription = "Метод из списка https://vk.com/dev/ads.getCategories или" &
					"#(cr)Встроенные методы:" &
					"#(cr)""demographics"" — демографические данные;" &
					"#(cr)""postsreach"" — охват рекламных записей",
				Documentation.SampleValues = {null}
			]
		), // метод API
		optional ids as (type list
			meta [
				Documentation.FieldCaption = "IDs",
				Documentation.FieldDescription = "Список идентификаторов" &
					"#(cr)для получения статистики только по ним",
				Documentation.SampleValues = {null}
			]
		), // список идентифиаторов
		optional q as record // параметры запроса для метода method (остальные игнорируются)
	) as any 
		meta [
			Documentation.Name = "Статистика рекламного кабинета Вконтакте",
			Documentation.LongDescription = "Неофициальный коннектор (интерфейс) для работы с рекламным кабинетом Вконтакте по API. Документация к API Вконтакте: https://vk.com/dev/ads",
			Documentation.Examples = {
				[
					Description = "Как получить токен доступа",
					Code = "VK_ADS()",
					Result = "Не задан access_token" & 
					"#(cr)Укажите токен доступа или получите новый на странице:" & 
					"#(cr)https://meta110.github.io/services/vkauth/" &
					"#(cr)#(cr)Создайте параметр token и запишите в него свой токен"
                ],
				[
					Description = "Получить список рекламных кабиентов, к которым предоставлен доступ для токена ",
					Code = "VK_ADS(token)",
					Result = "Таблица со списком рекламных кабинетов. #(cr)Больше примеров работы с коннектором на сайте https://github.com/meta110/powerbi/tree/master/vk"
				]
			}
		]
in Value.ReplaceType(VK_ADS, fnType)
