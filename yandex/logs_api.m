///*
(
    optional token as text,
    optional counter_id as number,
    optional request_id as any, // поставить на 3 позицию
    optional method as text,
    optional date_from as date,
    optional date_to as date,
    optional source as text,
    optional fields as any,
    optional attribution as text
    
) =>
//*/
let
/*
    token = ya_token,
    method = null,//"create",
    date_from = null, //#date(2020, 4, 26), //#date(2020, 4, 28),
    date_to = date_from, //date_from,
    source = null, //"visits",
    fields = "ym:s:dateTime,ym:s:isNewUser,ym:s:startURL,ym:s:endURL,ym:s:pageViews,ym:s:visitDuration,ym:s:bounce,ym:s:regionCountry,ym:s:regionCountryID,ym:s:regionCityID,ym:s:clientID,ym:s:goalsID,ym:s:<attribution>TrafficSource,ym:s:<attribution>AdvEngine,ym:s:<attribution>ReferalSource,ym:s:<attribution>SearchEngine,ym:s:<attribution>SocialNetwork,ym:s:<attribution>SocialNetworkProfile,ym:s:referer,ym:s:<attribution>DirectClickOrder,ym:s:<attribution>DirectBannerGroup,ym:s:<attribution>DirectPlatformType,ym:s:<attribution>DirectPlatform,ym:s:UTMCampaign,ym:s:UTMContent,ym:s:UTMMedium,ym:s:UTMSource,ym:s:UTMTerm,ym:s:hasGCLID,ym:s:deviceCategory,ym:s:mobilePhoneModel,ym:s:operatingSystem,ym:s:browser,ym:s:screenWidth,ym:s:screenHeight",
    attribution = null, //"lastsign",
    request_id = null,//84854590,
    counter_id = 55130254,
//*/
    
    
    raw_params = [
		token = token,
		counter_id = counter_id,
		request_id = request_id,
        method = method,
		date1 = date_from,
		date2 = date_to,
		source = source,
		fields = fields,
		attribution = attribution
    ],

    // Начальное форматирование параметров
    Param = [
        Transformations = [
            method = Self, //Default,
            request_id = List,
            source = Self, //Default,
            date1 = Date,
            date2 = Date,
            fields = List,
            attribution = Default
        ],
        Date = (d) => Date.ToText( Record.Field( raw_params, d ), _date_format), // форматирование дат по шаблону
        _date_format = "yyyy-MM-dd",
        List = (l) => // преобразую в список any
            let val = Record.Field( raw_params, l ) 
            in  if val = null then null // null не трогаю
                else if Value.Is( val, type list ) then val // список остается как есть 
                // числа должны оставаться числами
                else if Value.Is(val, type number) then List.Transform(_split(val), Number.From)
                else _split(val),
        Default = (d) => 
            let self = Record.Field( raw_params, d ) 
            in  if self <> null then self 
                else Doc[_getAllowedTable](d)[Допустимое значение]{0},
        Self = (v) => Record.Field( raw_params, v ),
        Transform = Record.Combine(
            List.Transform( 
                Record.FieldNames( raw_params ),
                each Record.AddField( [], _,
                    if Record.HasFields( Transformations, _ ) then 
                        Record.Field(Transformations, _)(_)
                    else Record.Field( raw_params, _ )
                )
            )
        ),
        _split = (v) => List.RemoveNulls( Text.SplitAny( Text.From(v), ", .;" ) )
    ],

    trans = Param[Transform],
    

    
    // распаковка ответа
	flat_run = (rec as list) => let
		row_list = List.Transform(
			List.Zip({{ 1..List.Count(rec) }, rec }), // добавляю индекс для pivot. Мне кажется на длинных списках так работает быстрее, чем List.PositionOf
			each { _{0}, Record.ToTable(  _{1} )} // делаю таблицу из "плоских" записей
		),
		tabl = Table.FromRows( row_list, type table [ Index = number, Table = table ]),
		expand = Table.ExpandTableColumn( tabl, "Table", { "Name", "Value" }), // стандартные названия, созданные Record.ToTable
		pivot = Table.Pivot( expand, List.Distinct( expand[ Name ]), "Name", "Value" ), // тут нужен индекс
		drop_index = Table.RemoveColumns( pivot, "Index" ), // индекс больше не нужен
		reorder = Table.ReorderColumns( drop_index, List.Sort( Table.ColumnNames( drop_index ))), // сортирую колонки по алфавиту
		return = reorder
	in return,

    // Валидация параметров
    Doc = [
        // параметр attribution
        _attribution = [
            Name = "Атрибуция",
            AllowedValues = #table( _type_table, {
                {"last", "последний источник (используется по умолчанию)"},
                {"lastsign", "последний значимый источник"},
                {"last_yandex_direct_click", "последний переход из Директа"},
                {"first", "первый источник"}
            })
        ],
        // параметр counter_id
        _counter_id = [
            Name = "Счетчик метрики",
            AllowedValues = let
                test_param = Web.Contents("https://api-metrika.yandex.net/management/v1/counters", Options),
                test_json = Json.Document(test_param)[counters],
                flat = Table.SelectColumns(flat_run(test_json),{"id","name","site"})
                in Table.RenameColumns(
                    Table.CombineColumns( flat, {"name","site"}, Combiner.CombineTextByDelimiter(" - "), "Описание" ),
                    {{"id", "Допустимое значение"}}
                )
        ],
        _date1 = [
            AllowedValues = #table( _type_table, {
                {Text.Format("#date(#[year],#[month],#[day])",[ year = Date.Year(_yesterday), month = Date.Month(_yesterday), day = Date.Day(_yesterday)]),"Дата начала (не раньше вчерашней даты)"}
            })
        ],
        _date2 = [
            AllowedValues = #table( _type_table, {
                { let dat = if trans[date1] <> null then raw_params[date1] else _yesterday in Text.Format("#date(#[year],#[month],#[day])",[ year = Date.Year(dat), month = Date.Month(dat), day = Date.Day(dat)]),"Дата окончания (не раньше даты начала)"}
            })
        ],
        _fields = [
            Name = "Поля запроса",
            AllowedValues = let
                cur = Record.Field(@Doc, "_" & trans[source]),
                prefix = cur[prefix],
                page = Web.Page(Web.Contents(cur[url])),
                tabl = page{0}[Data],
                rename = Table.RenameColumns(tabl, {"Поле", "Допустимое значение"}, MissingField.Ignore),
                return = Table.ReplaceValue(rename, prefix & "last", prefix & "<attribution>", Replacer.ReplaceText, {"Допустимое значение"})
            in try return otherwise _blank_table
        ],
        _method = [
            Name = "Тип запроса",
            AllowedValues = #table( _type_table, {
                {"list", "Список запросов логов"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/getlogrequests-docpage/
                //{"evaluate", "Возможность создания запроса"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/evaluate-docpage/
                {"info", "Информация о запросе логов"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/getlogrequest-docpage/
                {"download", "Загрузка обработанного запроса"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/download-docpage/
                {"clean", "Удаление обработанного запроса"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/clean-docpage/
                {"cancel", "Отмена обработки запроса"}, // https://yandex.ru/dev/metrika/doc/api2/logs/queries/cancel-docpage/
                {"create", "Создание запроса"} // https://yandex.ru/dev/metrika/doc/api2/logs/queries/createlogrequest-docpage/
            })
        ],
        _request_id = [
            Name = "ID запроса",
            AllowedValues = 
                let null_table = #table( _type_table, {{0, "Не использовать"}}),
                all_table = #table( _type_table, {{"all", "Выбрать все"}}),
                all = Source("list"),
                rest_table = Table.RenameColumns(
                    Table.SelectColumns(
                        Table.CombineColumns(
                            all,
                            {"date1", "date2", "source", "attribution"}, 
                            Combiner.CombineTextByEachDelimiter({" - ", " ", " "}, QuoteStyle.None),
                            "Описание"
                        ),
                        {"Описание", "request_id"}
                    )
                    ,{{"request_id", "Допустимое значение"}}
                )
            in  if Table.IsEmpty(all) then null_table else  all_table & null_table & rest_table
        ],
        _source = [
            Name = "Отчёт",
            AllowedValues = #table( _type_table, {
                {"visits", "Визиты"},
                {"hits", "Просмотры"}
            })
        ],
        _status = [
            Name = "Статус",
            AllowedValues = #table( _type_table, {
                {"processed", "обработан"},
                {"canceled", "отменён"},
                {"processing_failed", "ошибка при обработке"},
                {"created", "создан"},
                {"cleaned_by_user", "очищен пользователем"},
                {"cleaned_automatically_as_too_old", "очищен автоматически"}
            })
        ],
        _token = [
            Name = "Токен",
            AllowedValues = #table( _type_table, {
                {"https://yogabi.ru/services/yauth/", "Инструкция для получения токена"}
            })
        ],
        _yesterday = Date.AddDays(Date.From(DateTime.FixedLocalNow()),-1),
        // болванка с параметрами таблицы
        _type_table = type table [ #"Допустимое значение" = text, Описание = text ],
        _blank_table = Table.RemoveRows(#table(_type_table, {{null,null}}),0),
        // ссылка на документацию hits
        _hits = [
            url = "https://yandex.ru/dev/metrika/doc/api2/logs/fields/hits-docpage/",
            prefix = "ym:pv:"
        ],
        // ссылка на документацию visits
        _visits = [
            url = "https://yandex.ru/dev/metrika/doc/api2/logs/fields/visits-docpage/",
            prefix = "ym:s:"
        ],
        // получает таблицу с допустимыми значениями параметра
        _getAllowedTable = (param) => 
            if Record.HasFields(@Doc, "_" & param) then 
                Record.Field(@Doc, "_" & param)[AllowedValues]
            else null,
        // проверяет допустимо ли значение параметра
        _check_val = (param, val) => 
            let allowed = _getAllowedTable(param)
            in  if val = null then false
                else if param = "token" then true
                else if param = "date1" then val <= Date.ToText(_yesterday,Param[_date_format]) // лучше сравнивать даты, а не текстовое представление
                else if param = "date2" then val >= trans[date1]
                else if allowed = null then true 
                else List.ContainsAll( 
                    allowed[Допустимое значение], 
                    if Value.Is(val, type list) then val else { val }
                ),
        // генерирует таблицу с допустимыми значениями
        _getHelp = (param) => let
            allowed = _getAllowedTable(param{1}),
            quotes = 
                Table.TransformColumns(allowed, {"Допустимое значение", each if not(List.Contains({"token","date1","date2"},param{1})) and Value.Is(_, type text) then Text.Format("""#[val]""",[val = _]) else _}),
            add_param_name = Table.AddColumn( quotes, "Параметр", each param{1}, type text ),
            add_param_index =
                Table.AddColumn(
                    add_param_name, 
                    "Позиция", 
                    each param{0}, 
                    type text
                )
            in add_param_index,
        // проверяет ошибки в параметрах
        getErrors = (params) => let 
            rfn = Record.FieldNames( params ),
            errors = 
                List.Transform(
                    rfn,
                    each if _check_val( _ , Record.Field( params, _ )) then _blank_table
                        else _getHelp( { List.PositionOf( rfn, _ ) + 1, _ } )
                ),
            error_table =
                // если не указан токен, то получаем токен
                if trans[token] = null then _getHelp({1, "token"})
                // если не указан счетчик, то предлагаем доступные
                else if trans[counter_id] = null or not(_check_val("counter_id", trans[counter_id])) then _getHelp({2, "counter_id"})
                // если тип запроса не указан, предлагаем варианты
                else if trans[request_id] = null then _getHelp({List.PositionOf( rfn, "request_id" )+1, "request_id"}) 
                else if trans[method] = null then _getHelp({List.PositionOf( rfn, "method" )+1, "method"})
                // если тип запроса - список запросов логов, то остальные параметры проверять не нужно
                else if trans[method] = "list" then _blank_table
                // если указан идентификатор запроса, подходящий тип запроса, но такой идентификатор не найден
                // предлагаем список доступных идентификаторов 
                else if List.Contains({"create","evaluate"},trans[method]) then if errors = null then null else Table.Combine(List.RemoveRange(errors,List.PositionOf( rfn, "request_id" ),1))
                else if trans[request_id] <> null 
                    and List.Contains({ "info", "download", "clean", "cancel" }, trans[method] ) 
                    and not( _check_val("request_id", trans[request_id]) ) then _getHelp({List.PositionOf( rfn, "request_id" )+1, "request_id"})
                else Table.Combine(errors)
            in  //errors/*
                if Table.IsEmpty(error_table) then error "Нет ошибок" 
                else Table.ReorderColumns(error_table, {"Позиция", "Параметр", "Допустимое значение", "Описание"})//*/
    ],
    errors = Doc[getErrors](trans),

    //doc = Doc[getAllowed]("source"),

    // Параметры запроса
    Query = Record.Combine(List.Transform( // копирую GET-параметры из подготовленных
        { "date1", "date2", "fields", "source", "attribution" }, 
        each Record.AddField([], _, Record.Field( trans, _ ))
    )),
    Method = ( method, optional request, optional part_number ) => Record.Field([
        counter = [],
        list = [
            RelativePath = "logrequests"
        ],
        evaluate = [
            RelativePath = "logrequests/evaluate",
            Query = Query
        ],
        create = [
            RelativePath = "logrequests",
            Content = Json.FromValue([]),
            Query = Query
        ],
        info = [
            RelativePath = "logrequest/" & Text.From( request )
        ],
        clean = [
            RelativePath = Text.Format( "logrequest/#[requestId]/clean", [
                requestId = Text.From( request )
            ]),
            Content = Json.FromValue([])
        ],
        cancel = [
            RelativePath = Text.Format( "logrequest/#[requestId]/cancel", [
                requestId = Text.From( request )
            ]),
            Content = Json.FromValue([])
        ],
        download = [
            RelativePath = Text.Format( 
                "logrequest/#[requestId]/part/#[partNumber]/download", [
                    requestId = Text.From( request ), 
                    partNumber = Text.From( part_number )
                ]
            )
        ]
    ], method),
   
    
    url = Text.Format("https://api-metrika.yandex.net/management/v1/counter/#[counterId]", [counterId = Text.From(counter_id)]), 

    Headers = [
        #"Authorization" = "Bearer " & trans[token],
        #"Accept-Language" = "ru",
        #"Accept-Encoding" = "gzip"
    ],
    
    Options = [
        Headers = Headers,
        ManualStatusHandling = {400},
        IsRetry = true
    ],

    Source = (method, optional requests, optional part_number ) => let
        Settings = Method(method, requests, part_number),
        Source = Web.Contents(url, Options & Settings),
        json = Json.Document(Source),
        values = Record.FieldValues(json){0}, // ВНИМАТЕЛЬНО! Следим, чтобы ничего не потерялось!
        result = 
            if method = "download" then report(Source)
            else if method = "clean" then values 
            else if Value.Is(values, type record) then values 
            else flat_run(values)
    in result,
    
    report = (source) => let
        tabl = Table.PromoteHeaders( Csv.Document( source, null, "#(tab)" ) ),
        tcn = Table.ColumnNames(tabl),
        replace = List.Transform(tcn, each Text.Replace(_,"<attribution>",trans[attribution])),
        return = Table.RenameColumns(tabl,List.Zip({tcn,replace}))
    in return,
    
    ////requests_list = Source(Settings("list")),
    
    Requests = [
        _all = _no_empty(Source("list")),
        All = if _all = null then null else _all,
        Same = if All = null then null else _no_empty(Table.SelectRows(
            All,
            (request)=> List.AllTrue(
                List.Transform(
                    Record.FieldNames(Query), 
                    (field) => 
                        if field = "fields" then
                            List.Sort(request[fields]) = List.Sort(Query[fields]) 
                        else Text.Lower(Record.Field(request,field)) = Text.Lower(Record.Field(Query,field))
                )
            )
        )),
        ID = if All = null or trans[request_id] = null then null else _no_empty(Table.SelectRows(
            All,
            each List.Contains( trans[request_id], [request_id] )
        )),
        Processed = (optional requests) => Status( "processed", requests),
        Created = (optional requests) => Status( "created", requests),
        Status = ( status, optional requests ) => _no_empty(Table.SelectRows(
            if requests = null then All else requests,
            each [status] = status
        )),
        _no_empty = (tabl) => if Table.IsEmpty(tabl) then null else tabl
    ],


        
    return = //errors /*
        try errors otherwise try
        if trans[method] = "list" then
            Source("list")
        else if trans[method] = "create" then
            let result = Requests[Same] in 
                if result = null then Source("create") 
                else try Table.SingleRow(result) otherwise result
        else if trans[method]  = "info" then
            let result = if trans[request_id] = null then Requests[Same] else Requests[ID] in 
                if result = null then "Запрос не найден"
                else try Table.SingleRow(result) otherwise result
        else if trans[method] = "clean" then
            let c_requests = 
                if trans[request_id] = "all" then Requests[Processed]() 
                else Requests[Processed](Requests[ID])
            in if c_requests <> null then //Table.Combine( 
                    List.Transform(
                        c_requests[request_id], 
                        each Source("clean",_))
            //)
                else "Нечего удалять: идентификатор запроса не указан или подходящие для удаления запросы не найдены"
        else if trans[method] = "cancel" then
            let requests = 
                if trans[request_id] = "all" then Requests[Created]() 
                else Requests[Created](Requests[ID])
            in if requests <> null then List.Transform(requests, each Source("cancel",_)) else "Нечего отменять"
        else if trans[method] = "download" then
            let result = if trans[request_id] = null then Requests[Same] else Requests[ID], 
                processed = Requests[Processed]( result )
            in 
                if processed <> null then 
                    Table.Combine(List.Transform(Table.ToRecords(processed), (request) =>
                        Table.Combine(List.Transform(request[parts], (part) => Source("download", request[request_id], part[part_number])))
                    ))
                else if result <> null then 
                    //try Table.SingleRow(result) otherwise 
                    result
                else "Нет подходящих для загрузки запросов"
        else null
        otherwise if List.Contains("clean","cancel",trans[method]) then "Запросы удалены" else "Неизвестная ошибка"//*/
in
    return
