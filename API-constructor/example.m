let
    token_yandex = token_yandex, // получите бесплатный токен здесь https://yandex.ru/dev/disk/poligon/
    token_whois = token_whois,  // получите бесплатный токен здесь https://whoisjson.com/
    API = api2pbi, // ссылка на функцию-генератор

    // https://yandex.ru/dev/disk/poligon/
    args = {
// "Список файлов по имени"
        [
            RelativePath = "files", // type text
            Query = [
                limit = 5,
                media_type = type text meta [ 
                    Documentation.FieldCaption = "Тип медиа",
                    Documentation.AllowedValues = Text.Split( "audio, backup, book, compressed, data, development, diskimage, document, encoded, executable, flash, font, image, settings, spreadsheet, text, unknown, video, web", "," ) 
                    ,default = "spreadsheet"
                ]
            ]
        ] meta [ 
            Name = "Список файлов по имени",
            Description = "Получает список всех файлов диска, отсортированный по имени",
            // включаю пагинацию
            paginate = true,
            // проверка response
            response = [ check = each if [items]? = null or [items] = {} then error "Ничего не найдено" else _ ]
        ],
// "Метаинформация о файле"
        [
            Query = [
                path = type text
            ]
        ] meta [ 
            Name = "Метаинформация о файле" 
        ]
// Общие метаданные
    } meta [ 
        url = "https://cloud-api.yandex.net/v1/disk/resources",
        common = [
            Headers = [
                Accept = "application/json",
                Authorization = "OAuth " & token_yandex
            ],
            ManualStatusHandling = { 
                400  meta [ func = Json.Document ], 
                403, 
                406, 
                409 
            }
        ],
        // настройки пагинации
        pagination = [
            offsetValue = each if List.Count([items]) < [limit] then null else [limit] + [offset],
            offsetField = [ Query = [ offset = 0 ] ],
            dataValue = each [items],
            delay = 0.1
        ]
        //debug = true
    ],


    // https://whoisjson.com/documentation
    whois = [
        Headers = [
            Authorization = "TOKEN=" & token_whois
        ],
        RelativePath = "whois",
        Query = [
            domain = type text meta [ Documentation.FieldCaption = "Название домена"],
            format = "json"
        ]
    ] meta [
        url = "https://whoisjson.com/api/v1",
        Name = "Информация о домене",
        Description = "Информация о домене из WHOIS"
        //debug = 
    ],

    Source = API({args,{whois}})
in
    Source
