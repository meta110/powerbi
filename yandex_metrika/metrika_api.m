// коннектор к обычному (традиционному) API Яндекс Метрики https://yandex.ru/dev/metrika/doc/api2/api_v1/intro-docpage/
let
    delay = 0.05, // задержка между последовательными запросами в секундах https://yandex.ru/dev/metrika/doc/api2/intro/quotas.html
    Source = (
        optional date_start as date, // дата начала интервала, если не задана, будет 7 дней назад
        optional date_end as date, // дата окончания интервала, если не задана, то будет вчера
        optional group as text, // детализация интервалов между датами, по умолчанию за весь период
        optional dimensions as text, // список группировок https://yandex.ru/dev/metrika/doc/api2/api_v1/attrandmetr/dim_all-docpage/
        optional metrics as text, // список метрик https://yandex.ru/dev/metrika/doc/api2/api_v1/attrandmetr/dim_all-docpage/
        optional preset as text, // шаблон https://yandex.ru/dev/metrika/doc/api2/api_v1/presets/presets-docpage/
        optional filters as text, // фильтры сегментов https://yandex.ru/dev/metrika/doc/api2/api_v1/segmentation-docpage/
        optional goal_id as number, // идентификатор одной (пока) цели
        optional counter as number, // номер счетчика Яндекс Метрики
        optional token as text // авторизационный токен можно получить по ссылке https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d

    ) => let
        // Документация по API https://yandex.ru/dev/metrika/doc/api2/api_v1/data-docpage/
        date1 = if date_start = null then "7daysAgo" else  Date.ToText(date_start, "yyyy-MM-dd"), // дата начала интервала
        date2 = if date_end = null then "yesterday" else  Date.ToText(date_end, "yyyy-MM-dd"), // дата окончания интервала
        group = if group <> null and List.Contains({"all", "auto", "minutes", "dekaminute", "minute", "hour", "hours", "day", "week", "month", "quarter", "year"}, group) then group else "all",
        
        token = if token = null then "" else token, // токен авторизации
        counter = if counter = null then 44147844 else counter, // если счетчик не указан, то используется демосчетчик из документации
    
        format_params = (string) => Text.Combine(List.Select(Text.SplitAny(string,"#(tab) ,;.|"), each _ <> ""),","), // заменяю разделители на запятые и убираю лишние символы вокруг слов
    
        // удаляю пустые группировки, метрики и шаблоны немного извращенным способом. Можно сделать покороче
        params = Record.RemoveFields(
            [
                dimensions = format_params(dimensions),
                metrics = format_params(metrics),
                preset = format_params(preset)
            ],
            List.RemoveNulls(
                {if dimensions = null then "dimensions" else null}
                & {if metrics = null then "metrics" else null}
                & {if preset = null then "preset" else null}
            )
        ),
    
        // получить токен авторизации по ссылке https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d
        header_metrika_auth = [
            #"Authorization" = "OAuth " & token,
            #"Content-Type" = "application/x-yametrika+json",
            #"Accept-Encoding" = "gzip"
        ],
        limit = 100, // метрика может вернуть до 100 000 строк
        query = [
            ids = Text.From(counter), // номера счетчиков через запятую
            date1 = date1, // дата начала периода
            date2 = date2, // дата окончания периода
            group = group, // группировка внутри диапазона дат
            accuracy = "full", // нужна максимальная точность
            limit = Text.From(limit), // лимит
            lang = "ru" // по-умолчанию возвращает все значения на английском
            //offset = "1"
        ] 
        & (if params = [] then [ preset = "sources_summary" ] else params) // если ничего не задано, вывожу шаблон источников трафика
        & (if goal_id = null then [] else [ goal_id = Text.From(goal_id) ]) // проверяю задан ли идентификатор цели
        & (if filters = null then [] else [ filters = filters ]), // проверяю заданы ли фильтры
        
        Url = "https://api-metrika.yandex.net/stat/v1/data", // адрес подключения
    
        Options = [
            Headers = header_metrika_auth, // заголовки запроса
            ManualStatusHandling={400} // 400 ошибку обрабатываю вручную
        ],
    
        Source = (offset as number) => Web.Contents(Url,Options & [ Query = query & [offset = Text.From(offset)]]),
        sample = Source(1), // пробный запрос
        Json = Json.Document(sample), // разбираю JSON
        total = Json[total_rows], // сколько всего строк найдено?
        
        // получаю остальные результаты
        all_results = List.Generate(
            ()=>[
                offset = limit + 1, // пропускаю данные, которые уже есть в пробном запросе
                chunk = Function.InvokeAfter( () => Json.Document(Source(offset)), #duration(0,0,0,delay) ) // получаю свежие
            ],
            each [offset] < total, // проверяю, что не дошел до последней страницы пагинации
            each [
                offset = [offset] + limit, // увеличиваю страницу
                chunk = Function.InvokeAfter( () => Json.Document(Source(offset)), #duration(0,0,0,delay) ) // получаю данные с новой страницы
            ]
            , each [chunk] // возвращаю только данные
        ),
       
        Columns = Json[query][dimensions] & Json[query][metrics], // забираю заголовки столбцов из запроса
        data = Json[data] & List.Combine(List.Transform(all_results, each _[data])), // соединяю пробный запрос и остальные страницы пагинации
        unpack = List.Transform( // распаковываю данные
            data, 
            each Record.FromList(List.Transform(_[dimensions], each _[name]) & _[metrics], Columns)
        ),
        // если пробный запрос был с ошибкой, то возвращаю только его. Если ошибки не было, возвращаю таблицу с данными
        tbl = if Value.Metadata(sample)[Response.Status] = 200 then Table.FromRecords(unpack,null,MissingField.UseNull) else Json
    in
        tbl,
        // документация к функции
    fnType = type function(
        optional date_start as (type date 
            meta [
                Documentation.FieldCaption = "Дата начала интервала:",
                Documentation.FieldDescription = "Дата начала интервала не может быть позднее чем сегодня",
                Documentation.SampleValues = {DateTime.Date(DateTime.LocalNow() - 1)}
            ]
        ),
        optional date_end as (type date 
            meta [
                Documentation.FieldCaption = "Дата окончания интервала:",
                Documentation.FieldDescription = "Дата окончания должна совпадать с датой начала интервала или быть раньше нее",
                Documentation.SampleValues = {DateTime.Date(DateTime.LocalNow() - 1)}
            ]
        ),
        optional group as (type text
            meta [
                Documentation.FieldCaption = "Группировка по дате:",
                Documentation.FieldDescription = "Значение по умолчанию: all #(cr)#(cr)Допустимые значения:#(cr)""all"" — временной интервал не разбивается.#(cr)""auto"" — интервал устанавливается с учетом выбранного отчетного периода и количества данных, достаточного для этого периода.#(cr)""minutes"" — временной интервал разбивается на интервалы из некоторого количества минут.#(cr)""dekaminute"" — временной интервал разбивается на 10-минутные интервалы.#(cr)""minute"" — временной интервал разбивается на минутные интервалы.#(cr)""hour"" — временной интервал разбивается на часовые интервалы.#(cr)""hours"" — временной интервал разбивается на интервалы из нескольких часов.#(cr)""day"" — временной интервал разбивается по дням.#(cr)""week"" — временной интервал разбивается по неделям.#(cr)""month"" — временной интервал разбивается по месяцам.#(cr)""quarter"" — временной интервал разбивается по кварталам.#(cr)""year"" — временной интервал разбивается по годам.",
                Documentation.AllowedValues = {"all", "auto", "minutes", "dekaminute", "minute", "hour", "hours", "day", "week", "month", "quarter", "year"}
            ]
        ),
        optional dimensions as (type text
            meta [
                Documentation.FieldCaption = "Список группировок (dimensions) через запятую:",
                Documentation.FieldDescription = "Не более 10 группировок из списка https://yandex.ru/dev/metrika/doc/api2/api_v1/attrandmetr/dim_all-docpage/"
            ]
        ),
        optional metrics as (type text
            meta [
                Documentation.FieldCaption = "Список метрик (metrics) через запятую:",
                Documentation.FieldDescription = "Не более 20 метрик из списка https://yandex.ru/dev/metrika/doc/api2/api_v1/attrandmetr/dim_all-docpage/"
            ]
        ),
        optional preset as (type text
            meta [
                Documentation.FieldCaption = "Шаблон (preset):",
                Documentation.FieldDescription = "Возможные шаблоны https://yandex.ru/dev/metrika/doc/api2/api_v1/presets/presets-docpage/"
            ]
        ),
        optional filters as (type text
            meta [
                Documentation.FieldCaption = "Фильтр сегмента (filters):",
                Documentation.FieldDescription = "Корректная строка фильтра https://yandex.ru/dev/metrika/doc/api2/api_v1/segmentation-docpage/"
            ]
        ),
        optional goal_id as (type number 
            meta [
                Documentation.FieldCaption = "Идентификатор цели:",
                Documentation.FieldDescription = "Укажите идентификатор цели - его можно посмотреть в настройках Яндекс Метрики",
                Documentation.SampleValues = {123456}
            ]
        ),
        optional counter as (type number 
            meta [
                Documentation.FieldCaption = "Номер счетчика Яндекс.Метрики:",
                Documentation.FieldDescription = "Ищите номер счетчика в Метрике нужного сайта или на странице https://metrika.yandex.ru/list",
                Documentation.SampleValues = {44147844}
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
    Value.ReplaceType(Source, fnType)
