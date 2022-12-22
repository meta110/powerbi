let
    // Новая версия файла находится здесь https://github.com/meta110/powerbi/blob/master/sqliteproxy/pbi2sqlite.m

    // Таблица преобразований типов колонок в SQLite и обратно
    // например, даты можно хранить в виде целочисленного таймштампа или текстом
    // допустимые типы https://www.sqlite.org/datatype3.html#storage_classes_and_datatypes
    typeConversion = #table( 
        type table [ Name = text, Type = type, Value = text, Transform = function, Revert = function ], {
        { "Percentage.Type",Percentage.Type,"REAL",   Number.From,    each Percentage.From( _, LOCALE ) },
        { "Int64.Type",     Int64.Type,     "INTEGER",Int64.From,     each Int64.From( _, LOCALE ) },
        { "Date.Type",      Date.Type,      "INTEGER",DateTime2Timestamp, each Date.From( Timestamp2DateTimeZone( _ ) ) },
        { "DateTime.Type",  DateTime.Type,  "INTEGER",DateTime2Timestamp, each DateTime.From( Timestamp2DateTimeZone( _ ) ) },
        { "Text.Type",      Text.Type,      "TEXT",   each _,         each _ },
        { "Duration.Type",  Duration.Type,  "TEXT",   Text.From,      Duration.From },
        { "Currency.Type",  Currency.Type,  "REAL",   Number.From,    each Currency.From( _, LOCALE ) },
        { "List.Type",      List.Type,      "TEXT",   Value.ToText,   Json.Document },
        { "Number.Type",    Number.Type,    "REAL",   Number.From,    each Number.From( _, LOCALE ) },
        { "Any.Type",       Text.Type,      "TEXT",   each _,         each _}
        } ),

    PyScript = "    #(cr)#(lf)import os#(cr)#(lf)import json#(cr)#(lf)import sqlite3#(cr)#(lf)#(cr)#(lf)def test_path(paths):#(cr)#(lf)    try:#(cr)#(lf)        paths = json.loads( paths )#(cr)#(lf)        for path in paths:#(cr)#(lf)            abspath = os.path.abspath( path )#(cr)#(lf)            dirname = os.path.dirname( abspath )#(cr)#(lf)            if ( os.path.exists( dirname ) ):#(cr)#(lf)                return abspath#(cr)#(lf)    except: return False#(cr)#(lf)#(cr)#(lf)class Config(object):#(cr)#(lf)    def __init__(self,df): #df is a pd.DataFrame#(cr)#(lf)        df = df.set_index('Name',drop=True,inplace=False)#(cr)#(lf)        self.abspath = test_path( df.loc['db_path']['Value'] )#(cr)#(lf)        self.cwd = os.getcwd()#(cr)#(lf)        self.table_name = df.loc['table_name']['Value']#(cr)#(lf)        self.schema_name = self.table_name + '_schema'#(cr)#(lf)        try:#(cr)#(lf)            self.key_columns = json.loads(df.loc['key_columns']['Value'])#(cr)#(lf)        except:#(cr)#(lf)            self.key_columns = ''         #(cr)#(lf)        self.raise_error = df.loc['raise_error']['Value'] == 'True'#(cr)#(lf)#(cr)#(lf)#test = Config(config)#(cr)#(lf)#%%#(cr)#(lf)    #(cr)#(lf)def is_table_exists(table):#(cr)#(lf)    '''Проверяю через мастер-таблицу, что нужная таблица есть в БД'''#(cr)#(lf)    with con:#(cr)#(lf)        test = con.execute(f""SELECT * FROM sqlite_master WHERE type='table' AND name='{table}';"").fetchall()#(cr)#(lf)    return len(test) > 0#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def create_table( table_name, df, table_key ):#(cr)#(lf)    '''Создаю таблицу и настраиваю поля'''#(cr)#(lf)    tmpl = '''#(cr)#(lf)        DROP TABLE IF EXISTS ""{table_name}"";    #(cr)#(lf)        CREATE TABLE ""{table_name}"" (#(cr)#(lf)            {fields},#(cr)#(lf)            {key}#(cr)#(lf)        );#(cr)#(lf)    '''#(cr)#(lf)    column_tmpl = '""{name}"" {type}'#(cr)#(lf)    key_tmpl = 'PRIMARY KEY ({table_key})'#(cr)#(lf)    # заполняю шаблон для колонок#(cr)#(lf)    column_statements = [#(cr)#(lf)        column_tmpl.format( name = key, type = value )#(cr)#(lf)        for key, value in schema[['Name','Value']].values #(cr)#(lf)    ] #(cr)#(lf)    # закавычиваю ключевые колонки#(cr)#(lf)    key_statement = key_tmpl.format(#(cr)#(lf)        table_key = ', '.join( [ '""' + key + '""' for key in table_key ] ) )#(cr)#(lf)    #(cr)#(lf)    # заполняю запрос#(cr)#(lf)    query = tmpl.format(#(cr)#(lf)        table_name = table_name,#(cr)#(lf)        fields     = ',\n            '.join( sorted( column_statements ) ),#(cr)#(lf)        key        = key_statement#(cr)#(lf)    )#(cr)#(lf)    with con:#(cr)#(lf)        con.executescript(query)#(cr)#(lf)    con.commit()#(cr)#(lf)    #(cr)#(lf)    return query#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def read_df(table):#(cr)#(lf)    ''' Забирает таблицу из БД в датафрейм '''#(cr)#(lf)    with con:#(cr)#(lf)        return pandas.read_sql( f'SELECT * FROM ""{table}""', con )#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def write_df(table,data):#(cr)#(lf)    ''' Записывает датафрейм в БД '''#(cr)#(lf)    with con:#(cr)#(lf)        return data.to_sql(table,con,index=False, if_exists='replace')#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def upsert(table,df_columns,keycolumn):#(cr)#(lf)    '''Строит UPSERT запрос'''#(cr)#(lf)    #df_columns = list(df) #list(map(get_ch_field_name, fields)) #(cr)#(lf)    values = 'VALUES({})'.format(','.join(['?' for col in df_columns]))#(cr)#(lf)    columns = ','.join([ '""' + column + '""' for column in df_columns ])#(cr)#(lf)#(cr)#(lf)    for key in keycolumn:    #(cr)#(lf)        df_columns.remove(key) # модифицирует сам список, поэтому возвращает None#(cr)#(lf)    #(cr)#(lf)    update_list = ['""{}"" = EXCLUDED.""{}""'.format(col, col) for col in df_columns]#(cr)#(lf)    update_str = ','.join(update_list)#(cr)#(lf)    insert_stmt = 'INSERT INTO ""{}"" ({}) {} ON CONFLICT ({}) DO UPDATE SET {}'.format(#(cr)#(lf)        table, columns, values, ','.join([ '""' + column + '""' for column in keycolumn]), update_str)#(cr)#(lf)#(cr)#(lf)    return insert_stmt#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def upload(table, df, keycolumn):#(cr)#(lf)    '''Загружает данные в SQLite'''#(cr)#(lf)    insert_stmt = upsert(table,list(df),keycolumn)#(cr)#(lf)    with con:#(cr)#(lf)        con.executemany(insert_stmt, df.values.tolist())#(cr)#(lf)    #(cr)#(lf)    con.commit()        #(cr)#(lf)#(cr)#(lf)#(cr)#(lf)class Schema(object):#(cr)#(lf)    def __init__(self,df):#(cr)#(lf)        self.exists = not df.empty#(cr)#(lf)        self.schema = df#(cr)#(lf)        self.should_init_db = False#(cr)#(lf)        self.incompatible_fields = False#(cr)#(lf)        if ( self.exists ):#(cr)#(lf)            self.cleaned = df.drop(columns='Position').sort_values('Name').reset_index(drop=True)#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def update_schema( one: Schema, another: Schema ):#(cr)#(lf)    if ( another.exists and one.exists ):#(cr)#(lf)        if one.cleaned.equals( another.cleaned ):#(cr)#(lf)            one.schema = another.schema#(cr)#(lf)            one.difference = ''#(cr)#(lf)        else:#(cr)#(lf)            one.incompatible_fields = True#(cr)#(lf)            diff = pandas.concat( [ one.cleaned, another.cleaned ] ).drop_duplicates( keep = False )#(cr)#(lf)            one.difference = diff[['Name', 'TypeName']]#(cr)#(lf)    elif ( another.exists ):#(cr)#(lf)        one.schema = another.schema#(cr)#(lf)        one.exists = True#(cr)#(lf)        one.should_init_db = True#(cr)#(lf)#(cr)#(lf)#(cr)#(lf)def prepare_db(table_name, df, key_columns, #(cr)#(lf)             schema_name, schema, raise_error):#(cr)#(lf)    #(cr)#(lf)    existing_schema = read_df( schema_name ) if is_table_exists( schema_name ) else pandas.DataFrame([])#(cr)#(lf)    existing_schema = Schema(existing_schema)#(cr)#(lf)    pretending_schema = Schema(schema)#(cr)#(lf)    update_schema( existing_schema, pretending_schema)#(cr)#(lf)#(cr)#(lf)    if not( existing_schema.exists ):#(cr)#(lf)        raise Exception(f'Данные для загрузки отсутствуют. Таблица {table_name} не существует и не может быть создана из-за отсутствия данных. Укажите другую таблицу или передайте данные для загрузки.')#(cr)#(lf)  #(cr)#(lf)    if ( existing_schema.incompatible_fields ):#(cr)#(lf)        if ( raise_error ):#(cr)#(lf)            raise Exception('Таблица ""{}"" существует в БД, её колонки отличаются от новых. Обнаружены отличия названий колонок/типов: ""\n{}"". Укажите другую таблицу или отключите проверку, чтобы пересоздать таблицу с новыми данными.'.format(#(cr)#(lf)                table_name, #(cr)#(lf)                existing_schema.difference.to_csv(index=False,sep=' ',line_terminator='\n',header=False)#(cr)#(lf)                ))#(cr)#(lf)        else:#(cr)#(lf)            existing_schema = pretending_schema#(cr)#(lf)            existing_schema.should_init_db = True#(cr)#(lf)            #(cr)#(lf)    if ( existing_schema.should_init_db ):#(cr)#(lf)        create_table( table_name, df, key_columns )#(cr)#(lf)        write_df( schema_name, schema )#(cr)#(lf)        #(cr)#(lf)    return existing_schema.schema#(cr)#(lf)    #(cr)#(lf)#%%#(cr)#(lf)  #(cr)#(lf)config = Config(config)  #(cr)#(lf)#(cr)#(lf)if not( config.abspath  ):#(cr)#(lf)    raise Exception( 'Указан путь к несуществующей папке. Файл БД не может быть создан или прочитан.' )#(cr)#(lf)#(cr)#(lf)try:#(cr)#(lf)    con = sqlite3.connect( config.abspath )#(cr)#(lf)except:#(cr)#(lf)    raise Exception(f'{config.abspath=}')#(cr)#(lf)#(cr)#(lf)#raise Exception('schema {}'.format(schema))#(cr)#(lf)#(cr)#(lf)schema = prepare_db( config.table_name, df1, config.key_columns, #(cr)#(lf)             config.schema_name, schema, config.raise_error )#(cr)#(lf)     #(cr)#(lf)#(#)(schema.sort_values('Name').reset_index(drop=True).equals(existing_schema.sort_values('Name').reset_index(drop=True))):#(cr)#(lf)if not( df1.empty ):#(cr)#(lf)    upload(config.table_name, df1, config.key_columns)#(cr)#(lf)#(cr)#(lf)result = read_df( config.table_name ) #pandas.DataFrame([ 'Данные загружены в БД' ])#(cr)#(lf)#(cr)#(lf)con.close()#(cr)#(lf)#(cr)#(lf)config = pandas.DataFrame.from_dict(vars(config),orient='index').reset_index(level=0)",

    // Вспомогательные переменные
    LOCALE = "en-US",
    EMPTY_TABLE = #table(1,{}),
    UNIX = #datetimezone( 1970, 1, 1, 0, 0, 0, 0, 0 ),

    // Функция преобразования объекта PQ в текст
    Value.ToText = each Text.FromBinary( Json.FromValue( _ ) ),
    
    // Функции преобразования дат в timestamp и обратно
    DateTime2Timestamp = each Duration.TotalSeconds( DateTimeZone.From(_) - UNIX ),
    Timestamp2DateTimeZone = each UNIX + #duration(0,0,0, Int64.From( _, LOCALE ) ),

cache = ( 
        DataBasePath as text,
        TableName as text,
        optional Data as nullable table,
        optional KeyColumns as list,
        optional RaiseError as logical
    ) => let
    
    // Подготовка конфигурации БД
    db_path = List.Transform( Text.Split( DataBasePath, "," ), Text.Trim ),
    
    config = [
        db_path = Value.ToText( db_path ),
        table_name = TableName,
        key_columns = Value.ToText( KeyColumns ),
        raise_error = Text.Proper( Text.From( RaiseError ?? true ) ) 
        ],

    // Подготавливаю таблицу преобразований
    combineColumns = Table.CombineColumnsToRecord( 
        typeConversion,
        "Value",
        List.RemoveItems( Table.ColumnNames(typeConversion), {"Name"} ) 
        ),

    asRecord = Record.FromTable(combineColumns),

    // Генерирую тип колонок
    recordType = Type.ForRecord( 
        Record.RemoveFields( 
            Type.RecordFields( Type.TableRow( Value.Type( typeConversion ) ) ), 
            {"Name"} 
        ), false ),
    
    // строки с ошибками
    errRows = Table.SelectRowsWithErrors( Table.AddIndexColumn( Data, "Indx", 1 ) ),

    // Подготовка схемы таблицы
    Source = Table.Schema( Data ),

    #"Added Custom" = Table.AddColumn(Source, "SQLType", 
        each Record.Field( asRecord, [TypeName] ), recordType ),
    #"Expanded SQLType" = Table.ExpandRecordColumn(#"Added Custom", "SQLType", {"Value", "Transform"}, {"Value", "Transform"}),
    dataTransformations = Table.ToRows( Table.SelectColumns( #"Expanded SQLType", {"Name", "Transform"} ) ),
    // в индексах не должно быть null, заменяю их на 0 - это не всегда корректно. Лучше проверять индексные колонки на null и возбуждать ошибку при их наличии
    //fix_null = Table.ReplaceValue( Data, null, 0, Replacer.ReplaceValue, KeyColumns ),
    data = Table.TransformColumns( Data, dataTransformations ),
    schema = Table.SelectColumns(#"Expanded SQLType",{"Name", "Position", "TypeName", "Value"}),

    PyParams = [df1=if Data = null then EMPTY_TABLE else data, schema=if Data = null then EMPTY_TABLE else schema, config=Record.ToTable(config)],
	
	// Запуск Python
    #"Run Python script" = Python.Execute(PyScript,PyParams),
    
    // Поиск ошибок выполнения
    run = try #"Run Python script",
    result = if run[HasError] then error run[Error] else run[Value],

    // Разбираю схему данных
    loadedSchema = result{[Name="schema"]}[Value],
    #"Sorted Rows" = Table.Sort(loadedSchema,{{"Position", Order.Ascending}}),
    #"Added Custom1" = Table.AddColumn(#"Sorted Rows", "Values", 
        each Record.Field( asRecord, [TypeName] ), recordType ),
    #"Expanded Values" = Table.ExpandRecordColumn(#"Added Custom1", "Values", {"Revert", "Type"}, {"Revert", "Type"}),
    #"Removed Columns" = Table.RemoveColumns(#"Expanded Values",{"Value", "TypeName", "Position"}),
    fix_empty = Table.TransformColumns( #"Removed Columns", { "Revert", each (t) => if ( t = null or t = "" ) then null else _(t) } ),
    transformations = Table.ToRows( fix_empty ),
    
    // Преобразование загруженной таблицы к исходному виду
    loadedTable = result{[Name="result"]}[Value],
    transform = Table.TransformColumns(loadedTable,transformations),
    return = Table.ReorderColumns(transform,#"Sorted Rows"[Name])

    in 	//Source /*
        if Data <> null and KeyColumns = null then error "Укажите ключевые колонки"
        else if Data <> null and not List.ContainsAll( Table.ColumnNames( Data ), KeyColumns ) 
            then error "Названия ключевых колонок должны совпадать с колонками таблицы"
        else if Data <> null and not Table.IsEmpty( errRows ) then error "Устраните ошибки в исходной таблице. Номера строк, содержащих ошибки: " & Text.Combine( List.Transform( errRows[Indx], Text.From ), "," )
        else return meta ( config ) //*/
in
    cache
