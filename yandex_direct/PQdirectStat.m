// работа по API v5 с сервисом Reports https://yandex.ru/dev/direct/doc/reports/reports-docpage/
// по-умолчанию работает с отчетом CUSTOM_REPORT. Подробнее про типы отчетов https://yandex.ru/dev/direct/doc/reports/type-docpage/
// если хотите работать с другими отчетами, настройте переменную Reports
let
    stat = (
        optional beginDate as date, // дата начала интервала
        optional endDate as date, // дата окончания интервала
        optional fields as any, // список полей в виде списка или строки с разделителями
        optional reportName as text, // название отчета
        optional clientLogin as text, // логин клиента (обязателен для агентских аккаунтов)
        optional tokenYandexMetrika as text // токен доступа к Яндекс можно получить по ссылке https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d
    ) =>

let

    tokenYandexMetrika = 
        if tokenYandexMetrika <> null 
        then tokenYandexMetrika 
        else "", // укажите здесь свой токен в виде строки, чтобы использовать его постоянно
        //else token_parameter,// либо вставьте ссылку на внешний параметр, в котором записан токен
	
    fields = 
        if fields = null // если поля не заданы - использовать поля из списка
        then { //снимайте комментарии с ненужных полей и добавляйте комментарии к нужным
            //"AdFormat", //Формат объявления
            //"AdGroupId", //ID группы объявлений
            //"AdGroupName", //Название группы объявлений
            //"AdId", //ID объявления
            //"AdNetworkType", //Тип площадки (поиск, сети) не работает с SEARCH_QUERY_PERFORMANCE_REPORT
            "Age", //Возрастная группа
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
            "CampaignType", //Тип кампании
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
            "Gender", //Пол
            //"GoalsRoi", //ROI
            //"ImpressionReach", //Кол-во уникальных пользователей
            "Impressions", //Кол-во показов
            //"ImpressionShare", //Доля выигранных аукционов
            //"Keyword", //Текст ключевой фразы
            //"LocationOfPresenceId", //ID региона местонахождения
            "LocationOfPresenceName", //Название региона местонахождения
            //"MatchedKeyword", //Подобранная фраза
            //"MatchType", //Тип соответствия фразе
            "MobilePlatform", //Тип мобильной платформы
            //"Month", //Месяц
            "Placement", //Название площадки
            //"Profit", //Прибыль
            //"Quarter", //Квартал
            //"Query", //Запрос
            //"Revenue", //Доход
            //"RlAdjustmentId", //ID условия корректировки ставок
            "Sessions", //Кол-во визитов
            //"Slot", //Блок показа
            //"SmartBannerFilterId", //ID фильтра смарт-баннеров
            //"TargetingLocationId", //ID региона таргетинга
            //"TargetingLocationName", //Название региона таргетинга
            //"Week", //Неделя
            //"WeightedCtr", //Взвешенные CTR
            //"WeightedImpressions", //Взвешенные показы
            //"Year", //Год
            "Cost" //Стоимость кликов  
        } // если поля не заданы, беру из списка
        else if Value.Is(fields, type list) 
        then fields // если тип данных - список, то беру его в неизменном виде
        else List.Select(Text.SplitAny(fields,"#(tab) ,;.|"), each _ <> ""), // предполагаю, что это строка, и нарезаю в список по разделителям: табуляция, пробел, запятая, точка с запятой, точка, пайп - добавьте любые другие

    endDate = if endDate = null then Date.From(DateTime.LocalNow()) else endDate,//#date(2020,1,1),
    beginDate = if beginDate = null then Date.AddDays(endDate,-30) else beginDate,//#date(2020,1,20),
    
    header = [
        #"Authorization" = "Bearer " & tokenYandexMetrika,
        #"Accept-Language" = "ru",
		#"returnMoneyInMicros" = "true", // передавать деньги в микрорублях
        #"skipReportHeader" = "true", // не выводить название отчета и диапазон дат
        #"skipReportSummary" = "true", // не выводить статистику
        #"processingMode" = "offline"
	] 
    & ( if clientLogin = null then [] else [ #"Client-Login" = clientLogin ]),

    ResponseStatuses = [
        #"200" = "200: Отчет успешно сформирован в режиме онлайн",
        #"201" = "201: Отчет успешно поставлен в очередь на формирование в режиме офлайн",
        #"202" = "202: Отчет формируется в режиме офлайн",
        #"400" = "400: Ошибка в запросе или превышен лимит запросов в очереди",
        #"500" = "500: Ошибка при формировании отчета на сервере",
        #"502" = "502: Время обработки запроса превысило серверное ограничение"
    ],
    
    Reports = [
		FieldNames = List.Sort(fields), //Text.Split(Text.Replace(fields, " ", ""),","),
		/*OrderBy = {[  
            Field = "Date"
        ]},*/
		SelectionCriteria = [
			DateFrom = Date.ToText(beginDate,"yyyy-MM-dd"),//"2020-01-04",
			DateTo = Date.ToText(endDate,"yyyy-MM-dd")//"2020-01-10"
		],
		//ReportName = reportname,
   	    ReportType = "CUSTOM_REPORT",
		//ReportType = "SEARCH_QUERY_PERFORMANCE_REPORT",
   	    DateRangeType = "CUSTOM_DATE",
   	    Format = "TSV", // CSV, разделенный табуляцией
   	    IncludeVAT = "YES", // учитывать НДС
        IncludeDiscount = "YES" // учитывать скидки
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
				ManualStatusHandling = {400,500,502}
            ]
        )
    in
		Source,

	//с этого момента генерация отчета
	report_record_field = 
        Reports & [ 
            ReportName = ( if reportName = null then "" else reportName )// добавляю диапазон дат к названию отчета, на случай если название не указано
            & Reports[SelectionCriteria][DateFrom] 
            & " - " 
            & Reports[SelectionCriteria][DateTo]
        ],

	test = DirectAPI2(header, report_record_field, true),
	metadata = Value.Metadata(test),

    report3 = 
        if metadata[Response.Status] = 200 then
            //распаковываю отчет, если ошибки не было
			Table.PromoteHeaders(
				Csv.Document(
					test,
					List.Count(report_record_field[FieldNames]),
					"#(tab)"
				), 
				[PromoteAllScalars=true]
			) 
        else if metadata[Response.Status] >= 400 then //если была ошибка, сразу возвращаю ошибку
			Json.Document(test)[error]
		else Record.Field(ResponseStatuses,Text.From(metadata[Response.Status]))
    
in
	report3 meta metadata,
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
        optional fields as (type any
            meta [
                Documentation.FieldCaption = "Поля отчета в списке или строкой через запятую:",
                Documentation.FieldDescription = "Выберите допустимые поля для отчета CUSTOM_REPORT https://yandex.ru/dev/direct/doc/reports/fields-list-docpage/ #(cr)Можно передавать в виде списка или в строку с разделителями, например, через запятую"
            ]
        ),
        optional reportName as (type text 
            meta [
                Documentation.FieldCaption = "Название отчета:",
                Documentation.FieldDescription = "Придумайте название отчёта, чтобы потом загрузить его по имени, при этом диапазон дат и запрашиваемые поля также должны совпадать",
                Documentation.SampleValues = {"Василий"}
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
    ) as text
in
    Value.ReplaceType(stat, fnType)
