let
    token_yandex = token_yandex, // получите бесплатный токен здесь https://yandex.ru/dev/disk/poligon/
    token_whois = token_whois,  // получите бесплатный токен здесь https://whoisjson.com/
    API = API, // ссылка на запрос с функцией, скопированной из файла https://github.com/meta110/powerbi/blob/master/API-constructor/api2pbi.m

     // эта вспомогательная функция форматирует документацию для параметра
    // пользоватся ей необязательно, если вам нравится документировать параметры функции напрямую, 
    // скопирована отсюда https://github.com/meta110/powerbi/blob/master/API-constructor/api2pbi.m
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
    
    token = token_yandex,

    //wrong = Uri.BuildQueryString(parameters),
    params = {
/// Метод 1    
    [
        RelativePath = "files", // type text
        Query = [
            limit = 1000,
            //offset = 10,
            media_type = argMeta(type text, "Фильтр по медиа типу", "audio, backup, book, compressed, data, development, diskimage, document, encoded, executable, flash, font, image, settings, spreadsheet, text, unknown, video, web", "audio" ) /*type text meta [ 
                Documentation.FieldCaption = "Фильтр по медиа типу",
                Documentation.AllowedValues = Text.Split("audio, backup, book, compressed, data, development, diskimage, document, encoded, executable, flash, font, image, settings, spreadsheet, text, unknown, video, web", ",") //{"spreadsheet","audio"}
                ,default = "audio"
                //,modify = 
            ]*///"spreadsheet"
            //media_type = "spreadsheet"
        ]// //as record
    ] meta [
        Name = "Cписок файлов, упорядоченный по имени", //, blabla = ""
        Description = "Получает список файлов, упорядоченный по имени"
        ,paginate = true
        //,debug = false
    ],
//// Метод 2
    [
        Headers = [
            Accept = "application/json",
            Authorization = "OAuth " & token
        ],
        Query = [
            path = type text
        ]// //as record
    ] meta [
        Name = "Метаданные о файле или каталоге" //, blabla = ""
        //,debug = false
    ],
/// Метод 3    
    [
        RelativePath = "last-uploaded", // type text
        Query = [
            limit = 1000,
            //offset = 10,
            media_type = type text meta [ 
                Documentation.FieldCaption = "Фильтр по медиа типу",
                Documentation.AllowedValues = Text.Split("audio, backup, book, compressed, data, development, diskimage, document, encoded, executable, flash, font, image, settings, spreadsheet, text, unknown, video, web", ",") //{"spreadsheet","audio"}
                ,default = "audio"
                //,modify = 
            ]//"spreadsheet"
            //media_type = "spreadsheet"
        ]// //as record
    ] meta [
        Name = "Cписок файлов, упорядоченный по дате загрузки" //, blabla = ""
        ,paginate = true
        //,debug = false
    ]
} meta [
    url = "https://cloud-api.yandex.net/v1/disk/resources",
    common = [
        Headers = [
            Accept = "application/json",
            Authorization = "OAuth " & token
        ],
        ManualStatusHandling = { 400, 403, 406, 409 } meta [ func = each error Json.Document(_)[message] ]
    ],
    pagination = [
        offsetField = [ Query = [ offset = 0 ] ], // положение поля, отвечающего за смещение и его начальное значение
        //offsetValue = each if [limit] > List.Count([items]) then null else [offset] + [limit], // функция поиска СЛЕДУЮЩЕГО смещения. Если дальше страниц нет, функция должна возвращать null
        offsetValue = each if [items] = {} or [offset]? = null then null else [offset] + List.Count([items]), // функция поиска СЛЕДУЮЩЕГО смещения. Если дальше страниц нет, функция должна возвращать null
        dataValue = each [items], // здесь находится текущая страница данных - сами данные
        delay = 1 // задержка между последовательными запросами в секундах
    ]
],

    whois = [
        Headers = [ Authorization = "TOKEN=" & token_whois ],
        RelativePath = "whois",
        Query = [
            domain = type text, //"t.me",
            format = "json"
        ]
    ] meta [
        Name = "Получить сведения о домене",
        url = "https://whoisjson.com/api/v1"
    ],
    
    response = API({ params, { whois } })
    
in
    response
