# Конструктор API-функций для Power BI
Обертка для Web.Contents с расширенными возможностями для взаимодействия с различными web-API:
- автоматическое постраничное получение данных (пагинация со смещением)
- используйте разные методы API и разные API внутри одной функции
- автоматически создавайте функции для взаимодействия с пользователем

## Пример работы
Скопируйте [пример настройки для работы с API](https://github.com/meta110/powerbi/blob/master/API-constructor/example.m "пример настройки для работы с API"). В примере в рамках одной функции реализованы следующие методы API:
- получение [списка файлов на вашем Яндекс Диске](https://dev.yandex.net/disk-polygon/?lang=ru&tld=ru#!/v147disk47resources/GetFlatFilesList "списка файлов на вашем Яндекс Диске") (с пагинацией)
- получение [метаданных файла или каталога](https://dev.yandex.net/disk-polygon/?lang=ru&tld=ru#!/v147disk47resources/GetResource "метаданных файла или каталога") на Яндекс Диске
- получение [информации о домене](https://whoisjson.com/documentation "информации о домене") с помощью сервиса WhoisJSON

Для запуска примера зарегистрируйтесь в Яндексе и WhoisJSON и получите токены доступа к API. Регистрация и токены бесплатны.

## Структура аргумента
Функция выполнена в стиле "each-like" и принимает единственный аргумент:
- Аргумент представляет собой список списков записей
- Структура отдельной записи совпадает с [Web.Contents options](https://learn.microsoft.com/en-us/powerquery-m/web-contents#about "Web.Contents options") (второй аргумент функции Web.Contents) для отдельного метода
- Функция управляется через метаданные

Пример структуры аргумента:
```
    { { method meta method_meta } }
```

ещё пример посложнее:
```
    {
    	{
    		groupA_method1 meta private_methodA1_meta,
    		groupA_method2 meta private_methodA2_meta
    	} meta groupA_general_meta, // шаблон группы A
    	{
    		groupB_method1 meta private_methodB1_meta,
    		groupB_method2 meta private_methodB2_meta
    	} meta groupB_general_meta // шаблон группы B
    }
```
## Метаданные и шаблоны
Метаданные управляют поведением всей функции, при этом:
- частные метаданные записи **объединяются** с метаданными списка (шаблонами)
- частные метаданные имеют более высокий приоритет и **перезаписывают** значения с такими же названиями из общих метаданных (шаблонов), т. е. `private_methodA1_meta > groupA_general_meta`

Обязательные метаданные:
- **url** - общая ссылка конечной точки API (без учета RelativePath, т. е. первый аргумент функции Web.Contents)
- **Name** - название метода (как оно появится и будет называться в функции-селекторе методов). Должно быть указано для *каждой* записи и быть быть *уникальным* в пределах всех списков

Предлагаю объединять разные методы, предоставляемые одним и тем же API и помещать в общие метаданные списка (шаблоны) следующие данные:
- **url** (не включая RelativePath) обычно общий для всех методов одного API
- **авторизация** в одном API практически всегда реализована одинаково (токены в заголовках, GET-параметрах url и т. д.)
- **пагинация** для разных методов одного и того де API часто реализуется одинаково
- **ошибки** API и статусы ответа сервера, отличные от 200, ~~примерно всегда~~ обрабатываются одинаково в пределах одного API

> Шаблоны помогут серьёзно сократить и упростить ваш код, но использовать их необязательно!

## Полная структура метаданных
Так она выглядит в том числе после объединения частных метаданных метода с шаблоном (nullable = необязательный):

```
    // образец полных метаданных
    metaNewFormat = type [
        url = text, // основной url
        Name = text, // название метода
        Description = nullable text, // описание метода,
        common = nullable [ // общая структура настроек Web.Contents
            RelativePath = nullable text,
            Headers = nullable record,
            Content = nullable record,
            Query = nullable record,
            ManualStatusHandling = nullable list,
            IsRetry = nullable logical
        ],
        request = nullable [ // перед отправкой запроса к API
            content = nullable function, // функция, преобразующая Content в Binary.Type (по-умолчанию Json.FromValue)
            query = nullable function, // функция, преобразующая все поля Query в текст (по-умолчанию рекурсивная toText)
            queryFormat = nullable [ // настройки рекурсивной toText
                culture = nullable text, // культура для преобразования числа (по-умолчанию "en-US")
                dateFormat = nullable text, // строка форматирования даты (по-умолчанию "yyyy-MM-dd")
                separator = nullable text // разделитель для объединения списка элементов в строку (по-умолчанию ",")
            ]
        ],
        paginate = nullable logical, // включить пагинацию
        pagination = nullable [ // пагинация
            offsetField = record, // положение поля, эквивалентного offset, в структуре настроек Web.Contents
            offsetValue = function, // извлекает offset следующей страницы из распакованного функцией response.check ответа API
            dataValue = function, // извлекает страницу (список строк) из распакованного функцией response.check ответа API
            delay = number // анти-спам задержка повторного запроса к API в секундах
        ],
        response = nullable [ // преобразование ответа API
            check = nullable function, // выполняется сразу после распаковки ответа API (по-умолчанию "each _")
            final= nullable function // выполняется самой последней, в т. ч. после пагинации (по-умолчанию пытается Table.FromRecords)
        ],
        debug = nullable logical // дебаг если это поле существует: false - запрос до отправки (табличный вид), true - чистый распакованный binary ответа API без дополнительных преобразований из response
    ]
```
