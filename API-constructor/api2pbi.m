each
let
    args = _,


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
        debug = nullable logical, // дебаг если это поле существует: false - запрос до отправки (табличный вид), true - чистый распакованный binary ответа API без дополнительных преобразований из response
        
        QueryFolding = nullable [ // иногда PQ его самовольно добавляет
            IsFolded = nullable logical,
            HasNativeQuery = nullable logical,
            Kind = nullable text,
            Path = nullable text
        ]
    ],

/////// агрегация метаданных
    aggregate = let
        combine = Table.FromPartitions( "Metadata",
                List.Transform( args, each { Value.Metadata( _ ), Table.FromValue( _ ) } )
            ),
        // комбинирую метаданные
        metadata = Table.AddColumn( combine, "Meta", each Record.Merge( { 
            Record.RemoveFields( [Metadata], { "common" }, MissingField.Ignore ), 
            Value.Metadata([Value]) 
        } ) ),
        // извлекаю шаблон аргументов Web.Contents
        common = Table.AddColumn( metadata, "Common", each [Metadata][common]? ?? [Meta][common]? ),
        // комбинирую аргументы Web.Contents c шаблоном
        value = Table.CombineColumns( common, { "Common", "Value"}, Record.Merge, "Value" ),
        // пагинация
        pagination = Table.FromRecords( Table.TransformRows( value, each 
            if [Meta][paginate]? = true 
            // добавляю поле пагинации в запись
            then [ Value = Record.Merge({[Value],[Meta][pagination][offsetField]}), Meta = [Meta] ]
            // убираю все упоминания о пагинации
            else [ Value = [Value], Meta = Record.RemoveFields( [Meta], "pagination", MissingField.Ignore ) ]
        ) ),
        // названия методов
        methods = Table.AddColumn( pagination, "Name", each [Meta][Name]? )
    in  methods,

    // комбинирует записи любой вложенности
    // чем позже запись в списке, тем выше приоритет значения поля
    Record.Merge = ( r as list ) => let
        dropNulls = List.RemoveNulls( r ),
        test = List.Transform( dropNulls, each Value.Is( _, type record) ),
        tables = Table.Combine( List.Transform( dropNulls, Record.ToTable ) ),
        merge = Table.Group( Table.Buffer( tables ), "Name", { "Value", each 
            if Value.Is( List.Last( [Value] ), type record ) 
            then @Record.Merge( [Value] ) 
            else List.Last( [Value] )
        } ),
        rec = Record.FromTable( merge )
    in  if List.IsEmpty( dropNulls ) then error "Record.Merge: пустой список"
        else if List.AllTrue( test ) then rec else r{ List.PositionOf( test, false ) },

    Type.ToFlatTable = ( testType , optional n ) => let
        n1 = if n = null then 0 else n,
        columns = { "Value", Text.From( n1 ) },
        tabl = Record.ToTable( Type.RecordFields( testType ) ),
        recordFields = 
            Table.TransformRows( tabl, each 
                Table.Combine({
                    Table.FromRows( {{ [Value][Type], [Name] }}, columns ),
                    if Type.Is( [Value][Type], type record ) 
                    then Table.FromPartitions( Text.From( n1 ), 
                        {{ [Name], @Type.ToFlatTable( [Value][Type], n1 + 1 ) }})
                    else Table.FromRows( {}, columns )
                })
            )
    in  if Type.Is( testType, type record ) 
        then Table.Combine( recordFields )
        else error "Работает только с записями",

    // преобразует все уровни вложенности записи в плоскую таблицу с иерархией имен
    Record.ToFlatTable = ( r as record, optional n ) => let
        n1 = if n = null then 0 else n,
        columns = { "Value", Text.From( n1 ) },
        tabl = Record.ToTable( r ),
        transform = Table.TransformRows( tabl, each
            if Value.Is( [Value], type record ) then 
                if [Value] = [] then Table.FromRows( {{ null, [Name] }}, columns )
                else Table.FromPartitions( Text.From( n1 ), 
                    {{ [Name], @Record.ToFlatTable( ([Value]), n1 + 1 ) }} )
            else Table.FromRows( {{ [Value], [Name] }}, columns )
        )
    in  Table.Combine( transform ),

    checkIntegrity2 = ( instance as table, template as table, optional strict as logical, optional l as number ) => let
        l1 = l ?? 0,
        s1 = strict ?? true,
        level = Text.From(l1),
        next = Text.From( l1 + 1 ),
        // выбираю поля этого уровня
        templateFields = Table.SelectRows( template, each Record.FieldOrDefault( _, next, null ) = null ),
        instanceFields = Table.SelectRows( instance, each Record.FieldOrDefault( _, level, null ) <> null 
            and Record.FieldOrDefault( _, next, null ) = null ),
        // лишние поля
        extraFields = List.RemoveNulls( Table.TransformRows(
            instanceFields, each if List.Contains( Table.Column( templateFields, level ), Record.Field( _, level ) ) 
                then null else _
        )),
        // проверяю типы значений
        checkTypes = List.RemoveNulls(
                Table.TransformRows( instanceFields, each let 
                this = Record.Field( _, level ),
                example = Table.SelectRows( templateFields, each Record.FieldOrDefault( _, level, null ) = this ){0}? 
            in  //example /*
                if ( example = null ) 
                    or Value.Is( [Value], example[Value] )
                    or [Value] = null and Type.IsNullable( example[Value] ) then null
                else example //*/
            )
        ),
        // обязательные поля
        requiredFields = Table.SelectRows( templateFields, each not Type.IsNullable([Value]) ),
        existingFields = Table.Column( instance, level ),
        checkRequired = List.RemoveNulls(
            Table.TransformRows(
                requiredFields,
                each if not List.Contains( existingFields, Record.Field( _, level ) ) then _ else null
            )
        ),
        // убираю несуществующие поля и поля текущего уровня
        leaveExisting = Table.SelectRows( template, each List.Contains( existingFields, Record.Field( _, level ) ) 
            and Record.FieldOrDefault( _, next, null ) <> null ),
        // show must go on
        result = 
            if Table.IsEmpty( template ) then null
            else if not Table.HasColumns( instance, level ) then
                if Table.IsEmpty( requiredFields ) then null
                else "отсутствуют обязательные поля: " & details( checkRequired, level )
            else if s1 and not List.IsEmpty( extraFields ) 
                then "указаны лишние поля: " & details( extraFields, level )
            else if List.IsEmpty( checkRequired ) then 
                if List.IsEmpty( checkTypes ) then @checkIntegrity2( instance, leaveExisting, s1, l1 + 1 )
                else "неверные типы значений у полей: " & details( checkTypes, level )
            else "отсутствуют обязательные поля: " & details( checkRequired, level )
    in  //if l = 1 then details( checkRequired, level ) else//instanceFields,
    //checkRequired,
    //{templateFields,instanceFields},
        result,

    // формирую подсказку
    details = ( t , level as text ) => let 
        tab = Table.FromRecords( t ),
        name = Table.CombineColumns( tab, { "0"..level }, each Text.Combine( _, "." ), "Name" ),
        rows = Table.TransformRows( name, each [Name] & " " & typeToText( [Value] ) ),
        comb = Text.Combine( rows, ", ")
    in  comb, //comb,
    typeToText = each let _type = if Value.Is( _, type type) then _ else Value.Type( _ ) in
        Table.SingleRow(Table.Schema(#table(type table [Col1 = _type], {})))[TypeName],


    // сворачивает таблицу с иерархией в запись с вложенностью
    FlatTable.ToRecord = ( t as table, optional n ) => let
        n1 = if n = null then 0 else n + 1,
        this = Text.From( n1 ),
        g = Table.Group( t, this, { "Value", each 
            if  Table.RowCount(_) = 1 
                and Record.FieldOrDefault( _{0}, Text.From( n1 + 1 ), null ) = null 
            then [Value]{0}
            else @FlatTable.ToRecord( _, n1 )
        } ),
        r = Record.FromList( g[Value], Table.Column( g, this ) )
    in  r,

    // образец формата метаданных
    flatType = Table.Buffer( Type.ToFlatTable( metaNewFormat ) ),
    totalColumns = Table.ColumnCount( flatType ),
    nameColumns = {"0"..Text.From( totalColumns - 2 )},
    printableType = Table.TransformRows( flatType, each let 
        names = Record.FieldValues(Record.SelectFields(_,nameColumns)),
        nul = List.PositionOf(names,null),
        fix = if nul = -1 then totalColumns - 1 else nul
    in  Text.Repeat("#(tab)", fix ) & names{ fix - 1} & " = " & typeToText([Value])),
    printable = "#(lf)Шаблон параметров:#(lf)" & Text.Combine( printableType, "#(lf)" ),
    flatRecord = Table.TransformColumns( aggregate, { "Meta", Record.ToFlatTable } ),
    testMetadata = Table.TransformColumns( flatRecord, { "Meta", each checkIntegrity2( _, flatType ) } ),
    rowsWithErrors = let e = Table.SelectRows( testMetadata, each [Meta] <> null ) in 
        if Table.IsEmpty(e) then null 
        else Table.TransformRows( e, each Text.Format("функция ""#[Name]"": #[Meta]", _) ),

    // culture as text, dateFormat as text, separator as text, primitiveToText as function
    toText = ( optional culture, optional dateFormat, optional separator ) => let
        culture = culture ?? "en-US",
        dateFormat = dateFormat ?? "yyyy-MM-dd",
        separator = separator ?? ",",
        Query.ToText = each
            if Value.Is( _, type text ) then _
            else if Value.Is( _, type date ) then
                Date.ToText( _, dateFormat )
            else if Value.Is( _, type list ) then
                Text.Combine( List.Transform( _, @Query.ToText ), separator )
            else if Value.Is ( _, type record ) then 
                Record.FromList( 
                    List.Transform( Record.FieldValues( _ ), @Query.ToText ), 
                    Record.FieldNames( _ ) 
                )
            else if Value.Is( _, type number ) then
                Text.From( _, culture )
            else Text.From( _ )
    in  Query.ToText,
    

    // функция селектора методов
    // сюда надо добавить проверку достаточности скомбинированных метаданных
    func = let

        // названия методов
        methods = if rowsWithErrors = null then aggregate else error Text.Combine(rowsWithErrors & {printable}, "#(lf)" ),
        // тип функции
        functionType = Type.ForFunction([
            ReturnType = type any,
            Parameters = [ 
                method = type nullable text meta [ 
                    Documentation.FieldCaption = "Метод", 
                    Documentation.AllowedValues = methods[Name] 
                ]
            ]
        ], 0 ) meta [ Documentation.Name = "Выберите метод", Documentation.Description = "Функция, реализующая работу с выбранным методом, будет сгенерирована автоматически" ],
        // прототип функции
        prototype = each let v = methods{ [ Name = _{0}? ] }? 
            in  if _ = null or v = null then error "Выбран несуществующий метод"
                else method( v[Value], v[Meta] ),
        // одиночная функция
        result = if Table.RowCount( methods ) = 1
//////////////// ПРОВЕРИТЬ /////////////////
            then method( methods{0}[Value], methods{0}[Meta] ) 
            else Function.From( functionType, prototype )
    in  result,

    // получает ответы пользователя
    // надо отрефакторить
    prototype = ( restValues as table, metadata as record, optional addIndex as table ) => (optional a) => let
        // заполняю значениями по-умолчанию и преобразую
        userData = Table.AddColumn( addIndex, "Value", each let 
                v = a{[Index]}? ?? [default]? 
            in  if v = null then null 
                else Function.Invoke( [modify]? ?? ( (x) => x ), { v } ) 
        ),
        // объединяю и удаляю пустые (null)
        combineParams = if addIndex = null then restValues else userData & restValues,
        allParams = Table.SelectRows( combineParams, each [Value] <> null ),
        // восстанавливаю запись из таблицы
        back2Record = FlatTable.ToRecord( allParams ),
        // добавляю пагинацию
        pagination = Record.Merge({ metadata[pagination][offsetField]?, back2Record }), 
        // статусы ответа (делаю здесь один раз, чтобы потом не повторять в цикле)
        responseStatuses = allParams{[#"0" = "ManualStatusHandling"] }?,
        statuses = 
            if responseStatuses <> null
            then Table.FromRows( 
                List.Transform( responseStatuses[Value], 
                    each { _, List.Last( Record.FieldValues( Value.Metadata( _ ) ) ) } 
                ) 
            )
            else null,
        // пагинация
        offset = Record.ToFlatTable( metadata[pagination][offsetField] ),
        // функция, получающая страницу по заданному offset
        getPage = ( optional o ) => let
            this = if o = null then []
                else FlatTable.ToRecord( Table.TransformColumns( offset, {"Value", each o } ) ),
            merge = Record.Merge({ pagination, this }),
            bufferResponse = api( metadata, merge, statuses ),
            // нахожу offset следующей страницы
            next = metadata[pagination][offsetValue]( bufferResponse ),
            // извлекаю список с данными из нужного поля
            data = metadata[pagination][dataValue]( bufferResponse )
        in  data meta [ offset = next ],
        // получаю страницы
        allPages = getAllPages( getPage, getNextPage( getPage, metadata[pagination]?[delay]? ) ),
        // комбинирую, если есть что комбинировать
        combinePages = if metadata[paginate]? = true
            then List.Combine( allPages )
            else api( metadata, back2Record, statuses )
    in  //allParams/*
        if metadata[debug]? <> null then // если надо дебажить
            if metadata[debug] then api( metadata, back2Record, statuses )
            else allParams
        else if metadata[response]?[final]? <> null then metadata[response][final]( combinePages )
        else records2table( combinePages ) //*/
    ,

    // создает выбранную функцию
    method = ( content as record, metadata as record ) => let
        // делаю плоскую таблицу из иерархии записей
        record2Table = Record.ToFlatTable( content ),
        // значения этих полей уже заполнены
        restValues = Table.SelectRows( record2Table, each not Value.Is( [Value], type type ) ),
        // значения этих полей нужно запросить в функции, генерирую её тип
        userParams = Table.SelectRows( record2Table, each Value.Is( [Value], type type ) ),
        fieldNames = List.Sort( List.RemoveItems( Table.ColumnNames(userParams), {"Value"} ) ),
        nested = Table.CombineColumns( userParams, fieldNames, each Text.Combine(_,"."), "Name" ),
        functionType = Type.ForFunction([
                ReturnType = type function,
                Parameters = if Table.IsEmpty(userParams) then [] else Record.FromTable(nested)
        ], 0 ) meta [ Documentation.Name = metadata[ Name ]?, Documentation.Description = metadata[ Description ]? ],
        // выбираю названия метаданных, не относящиеся к документации
        additionalDataNames = List.Select( 
            Record.FieldNames( Value.Metadata( userParams[Value]{0} ) ), 
            each not List.Contains( { "Documentation", "Formatting" }, Text.Split( _, "." ){0} )
        ),
        // переношу метаданные в дополнительные колонки
        addMeta = List.Accumulate( additionalDataNames, userParams,
            ( s, c ) => Table.AddColumn( s, c, each Record.FieldOrDefault( Value.Metadata([Value]), c, null ) ) 
        ),
        dropValues = Table.RemoveColumns( addMeta, "Value" ),
        addIndex = /*if Table.IsEmpty(userParams) then null else*/ Table.AddIndexColumn( dropValues, "Index" ),
        func = if Table.IsEmpty(userParams) 
            then prototype( restValues, metadata )()
            else Function.From( functionType, prototype( restValues, metadata, addIndex ) )
    in  func// meta metadata
    ,

    // пробую распаковать список записей
    records2table = each
        if Value.Is( _, type list ) and Value.Is( _{0}, type record ) then Table.FromRecords( _, null, MissingField.UseNull ) else _,

    // отправляет запрос и блокирует повторный
    api = ( metadata, merge, statuses ) => let 
        url = metadata[url],
        content = metadata[request]?[content]? ?? Json.FromValue,
        query = metadata[request]?[query]? ?? toText(
            metadata[queryFormat]?[culture]?,
            metadata[queryFormat]?[dateFormat]?,
            metadata[queryFormat]?[separator]?
        ),
        bad = if metadata[response]?[check]? = null or metadata[debug]? = true then ( each _ ) else metadata[response][check],
        before = Record.TransformFields( merge, {{ "Content", content }, { "Query", query }, { "Headers", toText() }}, MissingField.Ignore ),
        send = Web.Contents( url, before ) 
        in buffer( Binary.Buffer( send ), Value.Metadata( send ), statuses, bad ),

    // распаковывает json
    json2 = ( response, check ) => let
        j = try Json.Document( response )
    in  if j[HasError] then // JSON не получен
            error j[Error]
        else check( j[Value] ), // ok

    // распаковывает tsv
    // заголовки должны быть в первой строке
    // для унификации ответ помещаю в список
    tsv = ( v ) => let 
        csv = Csv.Document( v, null, "#(tab)" ),
        headers = Table.PromoteHeaders( csv, [ PromoteAllScalars = true ] )
    in  headers,

    // проверяет статусы ответа сервера и решает как их распаковать
    buffer = ( buffer, metadata, optional statuses as table, optional bad as function ) => let
        status = metadata[Response.Status],
        contentType = metadata[Content.Type],
        statusInfo = statuses{[Column1=status]}?[Column2]?,
        extract = 
            if      contentType = "text/tab-separated-values"   then tsv( buffer )
            else if contentType = "application/json"            then json2( buffer, bad )
            else error Text.Format( "Неизвестный Content-Type: #[content]", [ content = contentType ] ),
        result =  
            if status = 200 then extract
            else if statuses <> null and status <> null and statusInfo <> null then statusInfo( buffer )
            else error Text.Format("Статус ответа: #[status]", [ status = status ])
        in  result meta metadata,
    
    // ищет и получает следующую страницу с анти-спам задержкой
    getNextPage = ( getPage, optional delay ) => let
        delay = #duration( 0, 0, 0, delay ?? 0 )
    in  ( previousPage ) =>  let
            metadata = Value.Metadata( previousPage ),
            offset = metadata[offset]?,
            nextPage = Function.InvokeAfter( () => getPage( offset ), delay )
        in  if offset = null then null else nextPage,
    // собирает все страницы в "цикле" пока функция getNextPage не вернет null
    getAllPages = ( getPage as function, getNextPage as function ) => let 
        // пагинация
        pages = List.Generate(
            () => getPage(),
            each _ <> null,
            each getNextPage ( _ )
        )
    in  pages,

    result = func
in
    result
