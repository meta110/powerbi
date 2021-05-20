// работа по API v5 с сервисом Reports https://yandex.ru/dev/direct/doc/reports/reports-docpage/
// по-умолчанию работает с отчетом CUSTOM_REPORT. Подробнее про типы отчетов https://yandex.ru/dev/direct/doc/reports/type-docpage/
// если хотите работать с другими отчетами, настройте переменную Reports и внимательно следите за списком запрашиваемых полей
// совместимость полей проверяется на стороне сервера, поэтому внимательно читайте сообщения об ошибках
///*
let 
    //Source = 1,
    stat = (
        optional beginDate as date, // дата начала интервала
        optional endDate as date, // дата окончания интервала
        optional fields as any, // список полей в виде списка или строки с разделителями
        optional reportName as text, // название отчета
        optional clientLogin as text, // логин клиента (обязателен для агентских аккаунтов)
        optional tokenYandexMetrika as text // токен доступа к Яндекс можно получить по ссылке https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d
    ) =>//*/
let

    ////////////////////////////////
    // Настройки параметров отчёта//
    ////////////////////////////////
    
    tokenYandexMetrika = 
        if tokenYandexMetrika <> null 
        then tokenYandexMetrika 
        else "", // укажите здесь свой токен в виде строки, чтобы использовать его постоянно

    // по-умолчанию дата окончания отчета - СЕГОДНЯ
    endDate = if endDate <> null then endDate else 
        Date.From(DateTime.LocalNow()),
    // по-умолчанию дата начала отчета - 30 дней назад
    beginDate = if beginDate <> null then beginDate else 
        Date.AddDays(endDate,-30),

    Reports = [
		FieldNames = fields,
		SelectionCriteria = [
			DateFrom = Date.ToText(beginDate,"yyyy-MM-dd"),
			DateTo = Date.ToText(endDate,"yyyy-MM-dd")
		],
   	    ReportType = "CUSTOM_REPORT",
		//ReportType = "SEARCH_QUERY_PERFORMANCE_REPORT",
   	    DateRangeType = "CUSTOM_DATE",
   	    Format = "TSV", // CSV, разделенный табуляцией
   	    IncludeVAT = "YES", // учитывать НДС
        IncludeDiscount = "YES" // учитывать скидки
	],

    fields = ///*
        if fields <> null // если поля не заданы - использовать поля из списка
        then //перевожу список выбранных полей с русского на английский
            Table.SelectRows( DataFormat, each List.Contains( fields, [rus] ))[eng]
        else //*/
        { //снимайте комментарии с ненужных полей и добавляйте комментарии к нужным
            //"AdFormat", //Формат объявления
            //"AdGroupId", //ID группы объявлений
            //"AdGroupName", //Название группы объявлений
            //"AdId", //ID объявления
            //"AdNetworkType", //Тип площадки
            //"Age", //Возрастная группа
            //"AudienceTargetId", //ID условия нацеливания на аудиторию
            //"AvgClickPosition", //Средняя позиция клика
            //"AvgCpc", //Средняя стоимость клика
            //"AvgCpm", //Средняя стоимость тыс. показов
            //"AvgImpressionFrequency", //Средняя частота показов одному пользователю
            //"AvgImpressionPosition", //Средняя позиция показа
            //"AvgPageviews", //Средняя глубина просмотра
            //"AvgTrafficVolume", //Средний объем трафика
            //"BounceRate", //Доля отказов
            "Bounces", //Кол-во отказов
            "CampaignId", //ID кампании
            "CampaignName", //Название Кампании
            //"CampaignType", //Тип кампании
            //"CarrierType", //Тип связи
            "Clicks", //Кол-во кликов
            //"ClickType", //Место клика
            //"ConversionRate", //Конверсия в целевой визит
            "Conversions", //Кол-во целевых визитов
            //"CostPerConversion", //CPC
            //"Criteria", //Условие показа (авто)
            //"CriteriaId", //ID условия показа (авто)
            //"CriteriaType", //Тип условия показа (авто)
            //"Criterion", //Назв. условия показа
            //"CriterionId", //ID условия показа
            //"CriterionType", //Тип условия показа
            //"Ctr", //CTR
            "Date", //Дата
            //"Device", //Тип устройства
            //"DynamicTextAdTargetId", //ID нацеливания динамического объявления
            //"ExternalNetworkName", //Название внешней сети
            //"Gender", //Пол
            //"GoalsRoi", //ROI
            //"ImpressionReach", //Кол-во уникальных пользователей
            "Impressions", //Кол-во показов
            //"ImpressionShare", //Доля выигранных аукционов
            //"Keyword", //Текст ключевой фразы
            //"LocationOfPresenceId", //ID региона местонахождения
            //"LocationOfPresenceName", //Название региона местонахождения
            //"MatchedKeyword", //Подобранная фраза
            //"MatchType", //Тип соответствия фразе
            //"MobilePlatform", //Тип мобильной платформы
            //"Month", //Месяц
            //"Placement", //Название площадки
            //"Profit", //Прибыль
            //"Quarter", //Квартал
            //"Query", //Запрос
            //"Revenue", //Доход
            //"RlAdjustmentId", //ID условия корректировки ставок
            //"Sessions", //Кол-во визитов
            //"Slot", //Блок показа
            //"SmartBannerFilterId", //ID фильтра смарт-баннеров
            //"TargetingLocationId", //ID региона таргетинга
            //"TargetingLocationName", //Название региона таргетинга
            //"Week", //Неделя
            //"WeightedCtr", //Взвешенные CTR
            //"WeightedImpressions", //Взвешенные показы
            //"Year", //Год
            "Cost" //Стоимость кликов  
        }, // если поля не заданы, беру из списка
    
    header = [
        #"Authorization" = "Bearer " & tokenYandexMetrika,
        #"Accept-Language" = "ru",
		#"returnMoneyInMicros" = "true", // передавать деньги в микрорублях чтобы не было округления
        #"skipReportHeader" = "true", // не выводить название отчета и диапазон дат
        #"skipReportSummary" = "true", // не выводить статистику
        #"processingMode" = "offline"
	] & ( if clientLogin = null then [] else [ #"Client-Login" = clientLogin ])
    ,

    ResponseStatuses = [
        #"200" = "200: Отчет успешно сформирован в режиме онлайн",
        #"201" = "201: Отчет успешно поставлен в очередь на формирование в режиме офлайн. Обновите данные через некоторое время.",
        #"202" = "202: Отчет формируется в режиме офлайн. Обновите данные через некоторое время.",
        #"400" = "400: Ошибка в запросе или превышен лимит запросов в очереди",
        #"500" = "500: Ошибка при формировании отчета на сервере",
        #"502" = "502: Время обработки запроса превысило серверное ограничение. Попробуйте уменьшить период или кол-во полей."
    ],
 
    //основная функция, которая получает ответ от сервера
    DirectAPI2 = (headers as record, fields as record, IsRetry as logical) =>
    let
        Source = Web.Contents(
            "https://api.direct.yandex.com/json/v5/", [
                Content=Json.FromValue([params = fields]),
                Headers = headers,
                RelativePath = "reports",
                IsRetry = IsRetry,
				ManualStatusHandling = { 400, 500, 502 }
            ]
        )
    in
		Source,

	//с этого момента генерация отчета
	report_record_field = 
        Reports & [ 
            ReportName = /*( if reportName = null then "" else reportName )// добавляю диапазон дат к названию отчета, на случай если название не указано
            & */
			Reports[SelectionCriteria][DateFrom] 
            & " - " 
            & Reports[SelectionCriteria][DateTo]
        ],

	test = DirectAPI2(header, report_record_field, true),
	
	// метаданные
	metadata = Value.Metadata(test),
	
	
	// распаковываю "нормальный" ответ
	response = 
		Table.PromoteHeaders(
			Csv.Document(
				test,
				List.Count(report_record_field[FieldNames]),
				"#(tab)"
			), 
			[PromoteAllScalars=true]
		),

	
	ErrorCase = #table(
		type table [ eng = text, rus = text, type = type ], { 
			{ "request_id",	"Индентификатор запроса", Int64.Type },
			{ "error_detail",	"Описание ошибки", Text.Type },
			{ "error_string",	"Ошибка", Text.Type },
			{ "error_code",	"Код ошибки", Int32.Type }		
		}
	),


    //////////////////////////////////////////////////////
    // Замена значений в полях ответа на "человеческие" //
    //////////////////////////////////////////////////////
    
    
    // оставляю только те поля, которые есть отчете
    ReplaceOnly = Table.SelectRows( ReplaceValues, each List.Contains( fields, [ field ])), 
    // список уникальных полей, в которых буду производить замены
    FieldsToReplace = List.Distinct(ReplaceOnly[field]), 
    
    // эта функция генерирует список замен для нужного поля
    ReplacesList = ( field as text ) => 
        Table.ToRows(
            Table.SelectColumns( 
                Table.SelectRows( ReplaceOnly, each [field] = field ), 
                { "value", "rus" }
            )
        ),
    
    // здесь непосредственно заменяются значения
    makeReplace = 
        List.Transform( 
            FieldsToReplace , // перебираю все колонки, в которых нужны замены
            each List.ReplaceMatchingItems ( Table.Column( response, _ ), ReplacesList ( _ ))
        ),

    combineWithReplaced = // убираю из старой таблицы колонки, в которых производил замену и добавляю замененные значения
        Table.FromColumns( 
            Table.ToColumns( Table.RemoveColumns( response, FieldsToReplace ) ) & makeReplace, 
            List.Difference( fields, FieldsToReplace ) & FieldsToReplace 
        ),


    //////////////////////////////////////////////////////
    // Дополнительные трансформации значений в колонках //
    //////////////////////////////////////////////////////

    // можно сделать список трансформаций как с заменой значений, но пока исправляю значения только в одном поле
    // перевожу цену из микрорублей в рубли
    makeTransform = if List.Contains( fields, "Cost" ) 
        then Table.TransformColumns( combineWithReplaced, {{"Cost", each Number.From( _ )/1000000}} )
        else combineWithReplaced,


    ///////////////////////////////////////
    // Присваиваю типы значений колонкам //
    ///////////////////////////////////////

    // выбираю только те поля, которые есть в отчете
    DataType = Table.SelectRows(DataFormat[[eng],[type]], each List.Contains(fields, [eng])),

	// меняю типы значений в колонках
	retype = Table.TransformColumnTypes( makeTransform, Table.ToRows(DataType) ),


    ////////////////////////////
    // Переименовываю колонки //
    ////////////////////////////

    rename = Table.RenameColumns( retype, Table.ToRows( DataFormat[[eng],[rus]] ), MissingField.Ignore ),


    //////////////////////////////
    // Обработка ошибок сервера //
    //////////////////////////////

	report3 = 
        if metadata[Response.Status] = 200 then
            //распаковываю отчет, если ошибки не было
			rename
        else if metadata[Response.Status] = 400 then //если была ошибка, сразу возвращаю ошибку
			let response = Table.FromRecords( { Json.Document(test)[error] } )
			in	Table.RenameColumns( 
                    Table.TransformColumnTypes( response, Table.ToRows( ErrorCase[ [eng], [type] ] ) ), 
                    Table.ToRows( ErrorCase[[eng],[rus]] ) 
                )
		else #table( // генерирую таблицу со статусом отчета
            type table [ #"Статус отчета" = text ], 
			{ { Record.Field( ResponseStatuses, Text.From( metadata[ Response.Status ] ) ) } }
        )

in
	report3 ///*
    meta metadata,
    
    // документация к фукнции
    fnType = type function(
        optional beginDate as (type date 
            meta [
                Documentation.FieldCaption = "Дата начала интервала:",
                Documentation.FieldDescription = "Дата начала интервала не может быть позднее чем сегодня",
                Documentation.SampleValues = {DateTime.Date(DateTime.LocalNow() - 1)}
            ]
        ),
        optional endDate as (type date 
            meta [
                Documentation.FieldCaption = "Дата окончания интервала:",
                Documentation.FieldDescription = "Дата окончания должна совпадать с датой начала интервала или быть раньше нее",
                Documentation.SampleValues = {DateTime.Date(DateTime.LocalNow() - 1)}
            ]
        ),
        optional fields as (type {text}
            meta [
                Documentation.FieldCaption = "Поля отчета в списке или строкой через запятую:",
                Documentation.FieldDescription = "Выберите допустимые поля для отчета CUSTOM_REPORT https://yandex.ru/dev/direct/doc/reports/fields-list-docpage/ #(cr)Можно передавать в виде списка или в строку с разделителями, например, через запятую",
                Documentation.AllowedValues = List.Sort( DataFormat[ rus ] )
            ]
        ),
        optional reportName as (type text 
            meta [
                Documentation.FieldCaption = "Название отчета:",
                Documentation.FieldDescription = "Придумайте название отчёта, чтобы потом загрузить его по имени, при этом диапазон дат и запрашиваемые поля также должны совпадать",
                Documentation.SampleValues = {"Платон Щукин"}
            ]
        ),
        optional clientLogin as (type text 
            meta [
                Documentation.FieldCaption = "Логин аккаунта клиента (для агентств):",
                Documentation.FieldDescription = "Если вы не агентство - оставьте пустым",
                Documentation.SampleValues = {"client.login"}
            ]
        ),
        optional token as (type text 
            meta [
                Documentation.FieldCaption = "Авторизационный токен:",
                Documentation.FieldDescription = "Получите токен по ссылке https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d",
                Documentation.SampleValues = {"05dd3dd84ff948fdae2bc4fb91f13e22bb1f289ceef0037"}
            ]
        )
    ) as text,

    // таблица описывает данные отчета и состоит из 3-х полей:
    // 1. англоязычное название, которое передается в отчет - менять их нельзя, 
    // 2. перевод названий на русский (так будут называться колонки в отчете и в вызове функции - можно переименовать как угодно
    // 3. колонка будет преобразована к этому типу - если ставите тип отличный от Text.Type, то будьте осторожней

	DataFormat = #table(
		type table [ eng = text, rus = text, type = type ], {
			{ "AdFormat", "Формат объявления", Text.Type },
			{ "AdGroupId", "ID группы объявлений", Int64.Type },
			{ "AdGroupName", "Название группы объявлений", Text.Type},
			{ "AdId", "ID объявления", Int64.Type },
			{ "AdNetworkType", "Тип площадки", Text.Type },
			{ "Age", "Возрастная группа", Text.Type },
			{ "AudienceTargetId", "ID условия нацеливания на аудиторию", Text.Type },
			{ "AvgClickPosition", "Средняя позиция клика", Text.Type },
			{ "AvgCpc", "Средняя стоимость клика", Text.Type },
			{ "AvgCpm", "Средняя стоимость тыс. показов", Text.Type },
			{ "AvgImpressionFrequency", "Средняя частота показов одному пользователю", Text.Type },
			{ "AvgImpressionPosition", "Средняя позиция показа", Text.Type },
			{ "AvgPageviews", "Средняя глубина просмотра", Text.Type },
			{ "AvgTrafficVolume", "Средний объем трафика", Text.Type },
			{ "BounceRate", "Доля отказов", Text.Type },
			{ "Bounces", "Кол-во отказов", Int64.Type },
			{ "CampaignId", "ID кампании", Int64.Type },
			{ "CampaignName", "Название Кампании", Text.Type },
			{ "CampaignType", "Тип кампании", Text.Type },
			{ "CarrierType", "Тип связи", Text.Type },
			{ "Clicks", "Кол-во кликов", Int64.Type },
			{ "ClickType", "Место клика", Text.Type },
			{ "ConversionRate", "Конверсия в целевой визит", Text.Type },
			{ "Conversions", "Кол-во целевых визитов", Int64.Type },
			{ "CostPerConversion", "Цена конверсии", Text.Type },
			{ "Criteria", "Условие показа (авто)", Text.Type },
			{ "CriteriaId", "ID условия показа (авто)", Text.Type },
			{ "CriteriaType", "Тип условия показа (авто)", Text.Type },
			{ "Criterion", "Назв. условия показа", Text.Type },
			{ "CriterionId", "ID условия показа", Text.Type },
			{ "CriterionType", "Тип условия показа", Text.Type },
			{ "Ctr", "CTR", Text.Type },
			{ "Date", "Дата", Date.Type },
			{ "Device", "Тип устройства", Text.Type },
			{ "DynamicTextAdTargetId", "ID нацеливания динамического объявления", Text.Type },
			{ "ExternalNetworkName", "Название внешней сети", Text.Type },
			{ "Gender", "Пол", Text.Type },
			{ "GoalsRoi", "ROI", Text.Type },
			{ "ImpressionReach", "Кол-во уникальных пользователей", Text.Type },
			{ "Impressions", "Кол-во показов", Int64.Type },
			{ "ImpressionShare", "Доля выигранных аукционов", Text.Type },
			{ "Keyword", "Текст ключевой фразы", Text.Type },
			{ "LocationOfPresenceId", "ID региона местонахождения", Text.Type },
			{ "LocationOfPresenceName", "Название региона местонахождения", Text.Type },
			{ "MatchedKeyword", "Подобранная фраза", Text.Type },
			{ "MatchType", "Тип соответствия фразе", Text.Type },
			{ "MobilePlatform", "Тип мобильной платформы", Text.Type },
			{ "Month", "Месяц", Text.Type },
			{ "Placement", "Название площадки", Text.Type },
			{ "Profit", "Прибыль", Text.Type },
			{ "Quarter", "Квартал", Text.Type },
			{ "Query", "Запрос", Text.Type },
			{ "Revenue", "Доход", Text.Type },
			{ "RlAdjustmentId", "ID условия корректировки ставок", Text.Type },
			{ "Sessions", "Кол-во визитов", Text.Type },
			{ "Slot", "Блок показа", Text.Type },
			{ "SmartBannerFilterId", "ID фильтра смарт-баннеров", Text.Type },
			{ "TargetingLocationId", "ID региона таргетинга", Text.Type },
			{ "TargetingLocationName", "Название региона таргетинга", Text.Type },
			{ "Week", "Неделя", Text.Type },
			{ "WeightedCtr", "Взвешенные CTR", Text.Type },
			{ "WeightedImpressions", "Взвешенные показы", Text.Type },
			{ "Year", "Год", Text.Type },
			{ "Cost", "Рекламный бюджет", Number.Type }
		}
	),


    // таблица замен значений в колонках - практически словарь по переводу с английского на русский:
    // 1. название колонки, в которой будет производится замена - не меняйте
    // 2. значение, которое будет заменяться - не меняйте
    // 3. значение, на которое будет заменяться - можно менять
    ReplaceValues = #table (
        type table [ field = text, value = text, rus = text ], {
        	{ "AdFormat",	"IMAGE",	"графический" },
            { "AdFormat",	"TEXT",	"текстовый" },
            { "AdFormat",	"VIDEO",	"видео" },
            { "AdFormat",	"SMART_MULTIPLE",	"смарт-баннер" },
            { "AdFormat",	"SMART_SINGLE",	"смарт-объявление" },
            { "AdFormat",	"ADAPTIVE_IMAGE",	"адаптивный графический" },
            { "AdFormat",	"SMART_TILE",	"смарт-плитка" },
            { "AdNetworkType",	"SEARCH",	"поиск" },
            { "AdNetworkType",	"AD_NETWORK",	"сети" },
            { "Age",	"AGE_0_17",	"до 18 лет" },
            { "Age",	"AGE_18_24",	"18 - 24 года" },
            { "Age",	"AGE_25_34",	"25 - 34 года" },
            { "Age",	"AGE_35_44",	"35 - 44 года" },
            { "Age",	"AGE_45",	"старше 45 лет" },
            { "Age",	"AGE_45_54",	"45 - 54 года" },
            { "Age",	"AGE_55",	"старше 55 лет" },
            { "Age",	"UNKNOWN",	"неизвестно" },
            { "CampaignType",	"TEXT_CAMPAIGN",	"Текстово-графические объявления" },
            { "CampaignType",	"MOBILE_APP_CAMPAIGN",	"Реклама мобильных приложений" },
            { "CampaignType",	"DYNAMIC_TEXT_CAMPAIGN",	"Динамические объявления" },
            { "CampaignType",	"SMART_CAMPAIGN",	"Смарт-баннеры" },
            { "CampaignType",	"MCBANNER_CAMPAIGN",	"Баннер на поиске" },
            { "CampaignType",	"CPM_BANNER_CAMPAIGN",	"Медийная кампания" },
            { "CampaignType",	"CPM_DEALS_CAMPAIGN",	"Медийная кампания со сделками" },
            { "CampaignType",	"CPM_FRONTPAGE_CAMPAIGN",	"Медийная кампания на Главной" },
            { "CarrierType",	"CELLULAR",	"мобильная связь" },
            { "CarrierType",	"STATIONARY",	"wi-fi или проводной интернет" },
            { "CarrierType",	"UNKNOWN",	"определить не удалось" },
            { "ClickType",	"TITLE ",	"заголовок объявления" },
            { "ClickType",	"SITELINK1",	"быстрая ссылка 1" },
            { "ClickType",	"SITELINK2",	"быстрая ссылка 2" },
            { "ClickType",	"SITELINK3",	"быстрая ссылка 3" },
            { "ClickType",	"SITELINK4",	"быстрая ссылка 4" },
            { "ClickType",	"SITELINK5",	"быстрая ссылка 5" },
            { "ClickType",	"SITELINK6",	"быстрая ссылка 6" },
            { "ClickType",	"SITELINK7",	"быстрая ссылка 7" },
            { "ClickType",	"SITELINK8",	"быстрая ссылка 8" },
            { "ClickType",	"VCARD ",	"визитка" },
            { "ClickType",	"CHAT ",	"чат с оператором" },
            { "ClickType",	"PHONE ",	"номер телефона" },
            { "ClickType",	"MOBILE_APP_ICON ",	"иконка приложения" },
            { "ClickType",	"BUTTON",	"кнопка загрузки / установки" },
            { "ClickType",	"UNKNOWN",	"неизвестно" },
            { "CriteriaType",	"KEYWORD",	"ключевая фраза" },
            { "CriteriaType",	"AUTOTARGETING",	"автотаргетинг" },
            { "CriteriaType",	"AUDIENCE_TARGET",	"условие нацеливания на аудиторию" },
            { "CriteriaType",	"DYNAMIC_TEXT_AD_TARGET",	"условие нацеливания для динамических объявлений или фильтр для динамических объявлений" },
            { "CriteriaType",	"SMART_BANNER_FILTER",	"фильтр для смарт-баннеров" },
            { "CriterionType",	"KEYWORD",	"ключевая фраза" },
            { "CriterionType",	"AUTOTARGETING",	"автотаргетинг" },
            { "CriterionType",	"RETARGETING",	"условие нацеливания на аудиторию по условию ретаргетинга и подбора аудитории" },
            { "CriterionType",	"INTERESTS_AND_DEMOGRAPHICS",	"условие нацеливания на аудиторию по профилю пользователей" },
            { "CriterionType",	"MOBILE_APP_CATEGORY",	"условие нацеливания на аудиторию по интересу к категории мобильных приложений" },
            { "CriterionType",	"WEBPAGE_FILTER",	"условие нацеливания для динамических объявлений, генерируемых на основе страниц сайта" },
            { "CriterionType",	"FEED_FILTER",	"фильтр для динамических объявлений, генерируемых на основе фида, или фильтр для смарт-баннеров" },
            { "Device",	"DESKTOP",	"десктоп" },
            { "Device",	"MOBILE",	"смартфон" },
            { "Device",	"TABLET",	"планшет" },
            { "Gender",	"GENDER_MALE",	"мужской" },
            { "Gender",	"GENDER_FEMALE",	"женский" },
            { "Gender",	"UNKNOWN",	"неизвестно" },
            { "MatchType",	"RELATED_KEYWORD",	"дополнительная релевантная фраза" },
            { "MatchType",	"SYNONYM",	"семантический синоним" },
            { "MatchType",	"KEYWORD",	"ключевая фраза" },
            { "MatchType",	"NONE",	"неизвестно" },
            { "MobilePlatform",	"ANDROID",	"Android" },
            { "MobilePlatform",	"IOS",	"iOS" },
            { "MobilePlatform",	"OTHER ",	"другая" },
            { "MobilePlatform",	"UNKNOWN",	"неизвестно" },
            { "Slot",	"PREMIUMBLOCK",	"спецразмещение" },
            { "Slot",	"OTHER",	"другие блоки" },
            { "Conversions", "--", "0" }
        }
    ),

    Source = Value.ReplaceType(stat, fnType)
in 
	Source//*/
