let
    VK_API_VERSION = "5.131",
    VK_TOKEN = #"Вконтакте Токен", /// не забудьте добавить!
    API = //// ссылка на функцию-конструктор https://github.com/meta110/powerbi/blob/master/API-constructor/api2pbi.m
    
    ///// ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ
    // форматирует документацию для параметра 
    // можно сразу писать как надо, но с ней вроде бы короче
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

    /// ВКОНТАКТЕ
    pagination_tmpl = "// VKScript универсальный с пагинацией#(cr)#(lf)var iterations_limit = 25; // не более 25 обращений к API#(cr)#(lf)var max_results = #[return_results]; // столько результатов вернуть, если 0 - возвращаются все#(cr)#(lf)var args = #[args];#(cr)#(lf)var next = false;#(cr)#(lf)var call = #[method]( args );#(cr)#(lf)//return call; // тест: вернет без пагинации#(cr)#(lf)if ( !call.count ) {#(cr)#(lf)#(tab)return call;#(cr)#(lf)}#(cr)#(lf)if ( !args.count ) { // задаю count, если его не было#(cr)#(lf)#(tab)args.count = call.items.length;#(cr)#(lf)}#(cr)#(lf)if ( !args.offset ) { // задаю offset, если его не было#(cr)#(lf)#(tab)args.offset = 0;#(cr)#(lf)}#(cr)#(lf)if ( max_results == 0 ) { // возвращаю все результаты, если не указано#(cr)#(lf)#(tab)max_results = call.count - args.offset;#(cr)#(lf)}#(cr)#(lf)if ( iterations_limit < max_results / args.count ) { // если итераций недостаточно, беру сколько есть#(cr)#(lf)#(tab)max_results =  args.count * iterations_limit;#(cr)#(lf)#(tab)next = true;#(cr)#(lf)}#(cr)#(lf)var max_offset = max_results + args.offset - args.count; // максимальный offset с учетом текущего и ограничений#(cr)#(lf)var result = call.items;#(cr)#(lf)// return { args: args, next: next, max_results: max_results }; // тест: вернет параметры перед пагинацией#(cr)#(lf)while ( args.offset < max_offset  ) {#(cr)#(lf)#(tab)args.offset = args.offset + args.count;#(cr)#(lf)#(tab)call = #[method]( args );#(cr)#(lf)#(tab)result = result + call.items;#(cr)#(lf)}#(cr)#(lf)//return { args: args, last: call, result: result }; // тест: вернет последние аргументы и результат#(cr)#(lf)call.items = result;#(cr)#(lf)if ( next ) {#(cr)#(lf)#(tab)call.next = args;#(cr)#(lf)}#(cr)#(lf)return call;",

    // упаковывает Content в execute Вконтакте
    fill = ( r ) => Text.ToBinary( Uri.BuildQueryString( 
        Record.RemoveFields( r, { "method", "args" }, MissingField.Ignore ) & [
            code = Text.Format( pagination_tmpl, [
                method = "API." & r[method],
                args = Text.FromBinary( Json.FromValue( r[args]? ?? {} ) ),
                return_results = 0
            ] )
        ]
    ) ),

    // распаковывает ответ со статистикой ВК
    vk_stat_expand = ( Source ) => let 
        tr = Table.TransformColumns( Source, { "stats", each if List.IsEmpty(_) then null else Table.FromRecords(_,null,MissingField.UseNull)} ),
        #"Filtered Rows" = Table.SelectRows(tr, each ([stats] <> null)),
        #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"type"}),
        set = Table.FromPartitions("Id",Table.ToRows(#"Removed Columns")),
        #"Removed Columns1" = Table.RemoveColumns(set,{"reach", "ctr", "uniq_views_count", "effective_cost_per_click", "effective_cost_per_mille", "effective_cpf"}, MissingField.Ignore),
        types = {{"day", type date}, {"spent", Currency.Type}, {"impressions", Int64.Type}, {"link_external_clicks", Int64.Type}, {"CampaignId", Int64.Type}, {"join_rate", Int64.Type}, {"clicks", Int64.Type}},
        names = List.Buffer(Table.ColumnNames(#"Removed Columns1")),
        #"Changed Type" = Table.TransformColumnTypes(#"Removed Columns1", List.Select(types, each List.Contains(names,_{0})), "en-US")
    in  #"Changed Type",

    vk = { 
        [
            Content = [ 
                method = "ads.getAccounts", 
                args = []
            ]
        ] meta [ Name = "ВК: список рекламных кабинетов" ],
        [
            Content = [
                method = "ads.getClients",
                args = [
                    account_id = type number
                ]
            ]
        ] meta [ 
            Name = "ВК: список клиентов в кабинете",
            response = [ final = each Table.TransformColumns( Table.FromRecords(_),{{"name", each Text.FromBinary(Text.ToBinary(_,1251),65001), type text}}) ]
        ],
        [ // https://dev.vk.com/method/ads.getCampaigns
            Content = [
                method = "ads.getCampaigns",
                args = [
                    account_id = argMeta( type number, "ID аккаунта" ),
                    client_id = argMeta( type number, "ID клиента" ),
                    include_deleted = 0
                ]
            ]
        ] meta [ Name = "ВК: список кампаний"],        
        [ // https://dev.vk.com/method/ads.getAds
            Content = [
                method = "ads.getAds",
                args = [
                    account_id = argMeta( type number, "ID аккаунта" ),
                    client_id = argMeta( type number, "ID клиента" ),
                    include_deleted = 0
                ]
            ]
        ] meta [ Name = "ВК: список объявлений"],
        [ // https://dev.vk.com/method/ads.getStatistics
            Content = [
                method = "ads.getStatistics",
                args = [
                    account_id = argMeta( type number, "ID аккаунта" ),
                    ids_type = argMeta( type text, "Тип идентификаторов", "ad,campaign,client,office", "campaign"),
                    ids = argMeta( type {number}, "Идентификаторы", null, null, null, each Text.Combine( List.Transform(_,Text.From),",") ),
                    period = argMeta( type text, "Гранулярность по датам", "day,week,month,year,overall" ),
                    date_from = argMeta( type date, "Начальная дата" ),
                    date_to = argMeta( type date, "Конечная дата" )
                ]
            ]
        ] meta [ 
            Name = "ВК: статистика", 
            Description = "Возвращает статистику показателей эффективности по рекламным объявлениям, кампаниям, клиентам или всему кабинету.",
            response = [ final = each vk_stat_expand(Table.FromRecords(_)) ]
        ],
        [ // https://dev.vk.com/method/wall.get
            Content = [
                method = "wall.get",
                args = [
                    owner_id = argMeta(type number,"Идентификатор сообщества",null,null,null, each _*-1),
                    count = argMeta(type number, "Количество записей")

                ]
            ]
        ] meta [
            Name = "ВК: посты на стене",
            response = [ final = each Table.FromRecords([items],null,MissingField.UseNull) ]
        ],
        [ // https://dev.vk.com/method/groups.getById
            Content = [
                method = "groups.getById",
                args = [
                    group_ids = argMeta(type {text}, "Идентификаторы или короткие имена сообществ"),
                    group_id = argMeta(type text, "Идентификатор или короткое имя сообщества"),
                    fields = argMeta(type {text}, "Список дополнительный полей", "activity|ban_info|can_post|can_see_all_posts|city|contacts|counters|country|cover|description|finish_date|fixed_post|links|market|members_count|place|site|start_date|status|verified|wiki_page")
                ]
            ]
        ] meta [
            Name = "ВК: информация о сообществе"
        ]
    } meta [ 
        url = "https://api.vk.com",
        common = [
            RelativePath = "method/execute",
            Headers = [ #"Content-Type" = "application/x-www-form-urlencoded" ],
            Content = [
                lang = "ru",
                v = VK_API_VERSION,
                access_token = VK_TOKEN,
                func_v = ""
            ]
        ],
        //debug = true,
        request = [ content = fill ],
        response = [ check = each if[error]? = null then [response] else [error] ]
    ],

    Source = API({vk})
in
    Source
