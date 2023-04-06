let
    API = API, // ссылка на конструктор https://github.com/meta110/powerbi/blob/master/API-constructor/api2pbi.m

    // эта функция форматирует документацию для параметра
    // здесь она не используется, ее можно скопировать и вставить туда, 
    // где подготавливаются параметры
    argSep = ",|",
    argMeta = ( 
        t as type, // 1
        optional caption as text, // 2
        optional allowed, // 3
        optional default, // 4
        optional limit as number, // 5
        optional modify as function // 6
    ) => t meta ( [
        Documentation.FieldCaption = caption,
        //Documentation.FieldDescription = [ Description ]?,
        //Documentation.SampleValues = [ Sample ]?,
        //Formatting.IsMultiLine = [ MultiLine ]?,
        //Formatting.IsCode = [ isCode ]?
        limit = limit,
        modify = modify,
        default = 
            if Type.Is( t, type list ) and Value.Is( default, type text )
            then if Text.PositionOfAny( default, Text.ToList( argSep ) ) > 0 
                then Text.SplitAny( default, argSep ) else { default }
            else default
    ] & ( if allowed = null then [] else [ // не нравится как реализовань
        Documentation.AllowedValues = // если равен null, то появляется поле с выбором без доступных вариантов
            if Value.Is( allowed, type list ) then allowed
            else Text.SplitAny( allowed, argSep ) 
    ] ) ),


    v5 = { 
// Campaigns
        [ // https://yandex.ru/dev/direct/doc/ref-v5/campaigns/get.html
            RelativePath = "campaigns",
            Content = [ method = "get",
                params = [
                SelectionCriteria = [
                    //Ids = type { number },
                    //Types = argMeta( type { text }, "Тип кампании","TEXT_CAMPAIGN|MOBILE_APP_CAMPAIGN|DYNAMIC_TEXT_CAMPAIGN|CPM_BANNER_CAMPAIGN|SMART_CAMPAIGN"),
                    //States = argMeta( type { text }, "Состояния","ARCHIVED|CONVERTED|ENDED|OFF|ON|SUSPENDED"),
                    Statuses = { "ACCEPTED" } //= argMeta( type { text }, "Статусы кампаний", "ACCEPTED|DRAFT|MODERATION|REJECTED"),
                    //StatusesPayment = argMeta( type { text }, "StatusesPayment", "DISALLOWED|ALLOWED")
                ],
                FieldNames = {"Id","Name"},//argMeta( type { text }, "Поля отчета", "BlockedIps|ExcludedSites|Currency|DailyBudget|Notification|EndDate|Funds|ClientInfo|Id|Name|NegativeKeywords|RepresentedBy|StartDate|Statistics|State|Status|StatusPayment|StatusClarification|SourceId|TimeTargeting|TimeZone|Type"),
                Page = [ Limit = 10000 ]
            ] ]
        ] meta [ 
            Name = "Директ: Список кампаний", 
            Description = "Получить сведения о кампаниях", 
            pagination = [ dataValue = each [Campaigns]? ], 
            paginate = true 
        ],

// AdGroups
// Campaigns
        [ // https://yandex.ru/dev/direct/doc/ref-v5/adgroups/get.html
            RelativePath = "adgroups",
            Content = [ method = "get",
                params = [
                SelectionCriteria = [
                    CampaignIds = argMeta( type { number }, "Список идентификаторов кампаний"),
                    Statuses = argMeta( type { text }, "Статусы модерации", "ACCEPTED|DRAFT|MODERATION|REJECTED", "ACCEPTED")
                ],
                FieldNames = argMeta( type { text }, "Поля отчета", "CampaignId|Id|Name|NegativeKeywords|NegativeKeywordSharedSetIds|RegionIds|RestrictedRegionIds|ServingStatus|Status|Subtype|TrackingParams|Type",{"Id","Name"}),
                Page = [ Limit = 10000 ]
            ] ]
        ] meta [ 
            Name = "Директ: Список групп объявлений", 
            Description = "Получить сведения о группах объявлений", 
            pagination = [ dataValue = each [AdGroups]? ], 
            paginate = true 
        ],

// Reports https://yandex.ru/dev/direct/doc/reports/spec.html
        [
            RelativePath = "reports",
            Headers = [
                processingMode = "offline",
                returnMoneyInMicros = true,
                skipReportHeader = true,
                skipColumnHeader = false,
                skipReportSummary = true
            ],
            Content = [
                params = [
                    SelectionCriteria =[
                        DateFrom = type text, //Date.From(DateTime.LocalNow()) - Duration.From(4),
                        DateTo = type text, //Date.From(DateTime.LocalNow()),
                        Filter = argMeta( type list, "Фильтр", null, {[Field="Impressions",Operator="GREATER_THAN",Values={0}]})
                    ],
                    Goals = argMeta( type { number }, "Список целей"),
                    FieldNames = argMeta( type { text }, "Список полей", "LocationOfPresenceId,LocationOfPresenceName,Month,Week,CampaignId,CampaignName,Clicks,Cost,Impressions,Conversions,Bounces,Age,AdFormat",null,null,each Text.Split(_,",")),
                    DateRangeType = "CUSTOM_DATE",
                    ReportName = argMeta( type text, "Название отчета"),//"test6",
                    ReportType = "CUSTOM_REPORT",
                    Format = "TSV",
                    IncludeVAT = "YES"
                ]
            ],
            ManualStatusHandling = { 
                201 meta [ func = each error "Отчёт поставлен в очередь на подготовку офлайн" ],
                202 meta [ func = each error "Отчет подготавливается в режиме офлайн" ],
                400, 404
            }  meta [ func = each error Json.Document( _ )[error]?[error_detail]? ]

        ] meta [ Name = "Директ: Статистика", Description = "Получить отчёт", pagination = null ]
    } meta [
        url = "https://api.direct.yandex.com/json/v5/",
        common = [
            Headers = [ 
                #"Authorization" = argMeta(type text, "Токен", null, null, null, each "Bearer " & _),
                #"Accept-Language" = "ru",
                #"Client-Login" = type text
            ]
        ],
        pagination = [
            offsetField = [ Content = [ params = [ Page = [ Offset = 0 ] ] ] ],
            offsetValue = each [LimitedBy]?,
            delay = 0.1
        ],
        response = [
            check = each if [error]? <> null then error [error][error_detail] else [result]
        ]
        
        //,debug = true
    ],

    counters = { 
// счетчики метрики
        [
            RelativePath = "management/v1/counters",
            Headers = [
                #"Content-Type" = "application/json"
            ],
            Query = [
                field = "goals,grants"
            ]
        ] meta [ Name = "Метрика: Список счетчиков", response = [ check = each [counters] ] ],
// отчет метрики https://yandex.ru/dev/metrika/doc/api2/api_v1/data.html
        [
            RelativePath = "stat/v1/data",
            Headers = [
                #"Content-Type" = "application/x-yametrika+json",
                #"Accept-Encoding" = "gzip"
            ],
            Query = [
                ids = argMeta( type {text}, "Номера счетчиков через запятую"),
                dimensions = argMeta( type {text}, "Группировки списком или через запятую, не более 10"),
                metrics = argMeta( type {text}, "Метрики списком или через запятую, не более 20",null,"ym:s:visits,ym:s:pageviews,ym:s:users"),
                accuracy = 1, //argMeta( type number, "Точность", null, 1 ),
                date1 = argMeta( type date, "Дата начала интервала", null, Date.From( DateTime.LocalNow() - Duration.From(7) )),
                date2 = argMeta( type date, "Дата окончания интервала", null, Date.From( DateTime.LocalNow() )),
                limit = 5
            ]
        ] meta [ 
            Name = "Метрика: Отчёт таблица",
            paginate = true,
            pagination = [
                offsetField = [ Query = [Offset = 1] ],
                offsetValue = each 
                    let offset = [query][offset] + List.Count([data]) 
                    in if [data] = null or [total_rows] <= offset then null else offset,
                dataValue = each [data] meta Record.RemoveFields(_,"data"),
                delay = 0.1
            ],
            response = [
                final = each let
                    metadata = Value.Metadata(_),
                    unpack = Table.TransformRows(
                        Table.FromRecords(_), 
                        each Record.FromList( 
                            List.Transform([dimensions], each [name]) & [metrics], 
                            metadata[query][dimensions]? & metadata[query][metrics]?
                        )
                    )
                in  Table.FromRecords(unpack)
            ]
            //,debug=true
        ]
    } meta [ 
        url = "https://api-metrika.yandex.net/",
        common = [
            Headers = [
                Authorization = argMeta(type text, "Токен", null, null, null, each "OAuth " & _)
            ],
            ManualStatusHandling = { 400 } meta [ f = each error Json.Document(_)[message]? ]
        ]
    ],


    args = { counters , v5 }, 



    Source = API(args)
in
    Source
