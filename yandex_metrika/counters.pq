let

    // table should be an actual Table.Type, or a List.Type of Records
    Table.ChangeType = (table, tableType as type) as nullable table =>
        // we only operate on table types
        if (not Type.Is(tableType, type table)) then error "type argument should be a table type" else
        // if we have a null value, just return it
        if (table = null) then table else
        let
            columnsForType = Type.RecordFields(Type.TableRow(tableType)),
            columnsAsTable = Record.ToTable(columnsForType),
            schema = Table.ExpandRecordColumn(columnsAsTable, "Value", {"Type"}, {"Type"}),
            previousMeta = Value.Metadata(tableType),

            // make sure we have a table
            parameterType = Value.Type(table),
            _table =
                if (Type.Is(parameterType, type table)) then table
                else if (Type.Is(parameterType, type list)) then
                    let
                        asTable = Table.FromList(table, Splitter.SplitByNothing(), {"Column1"}),
                        firstValueType = Value.Type(Table.FirstValue(asTable, null)),
                        result =
                            // if the member is a record (as expected), then expand it. 
                            if (Type.Is(firstValueType, type record)) then
                                Table.ExpandRecordColumn(asTable, "Column1", schema[Name])
                            else
                                error Error.Record("Error.Parameter", "table argument is a list, but not a list of records", [ ValueType = firstValueType ])
                    in
                        if (List.IsEmpty(table)) then
                            #table({"a"}, {})
                        else result
                else
                    error Error.Record("Error.Parameter", "table argument should be a table or list of records", [ValueType = parameterType]),

            reordered = Table.SelectColumns(_table, schema[Name], MissingField.UseNull),

            // process primitive values - this will call Table.TransformColumnTypes
            map = (t) => if Type.Is(t, type table) or Type.Is(t, type list) or Type.Is(t, type record) or t = type any then null else t,        
            mapped = Table.TransformColumns(schema, {"Type", map}),
            omitted = Table.SelectRows(mapped, each [Type] <> null),
            existingColumns = Table.ColumnNames(reordered),
            removeMissing = Table.SelectRows(omitted, each List.Contains(existingColumns, [Name])),
            primativeTransforms = Table.ToRows(removeMissing),
            changedPrimatives = Table.TransformColumnTypes(reordered, primativeTransforms),
        
            // Get the list of transforms we'll use for Record types
            recordColumns = Table.SelectRows(schema, each Type.Is([Type], type record)),
            recordTypeTransformations = Table.AddColumn(recordColumns, "RecordTransformations", each (r) => Record.ChangeType(r, [Type]), type function),
            recordChanges = Table.ToRows(Table.SelectColumns(recordTypeTransformations, {"Name", "RecordTransformations"})),

            // Get the list of transforms we'll use for List types
            listColumns = Table.SelectRows(schema, each Type.Is([Type], type list)),
            listTransforms = Table.AddColumn(listColumns, "ListTransformations", each (t) => List.ChangeType(t, [Type]), Function.Type),
            listChanges = Table.ToRows(Table.SelectColumns(listTransforms, {"Name", "ListTransformations"})),

            // Get the list of transforms we'll use for Table types
            tableColumns = Table.SelectRows(schema, each Type.Is([Type], type table)),
            tableTransforms = Table.AddColumn(tableColumns, "TableTransformations", each (t) => @Table.ChangeType(t, [Type]), Function.Type),
            tableChanges = Table.ToRows(Table.SelectColumns(tableTransforms, {"Name", "TableTransformations"})),

            // Perform all of our transformations
            allColumnTransforms = recordChanges & listChanges & tableChanges,
            changedRecordTypes = if (List.IsEmpty(allColumnTransforms)) then changedPrimatives else Table.TransformColumns(changedPrimatives, allColumnTransforms, null, MissingField.Ignore),

            // set final type
            withType = Value.ReplaceType(changedRecordTypes, tableType)
        in
            if (List.IsEmpty(Record.FieldNames(columnsForType))) then table else withType meta previousMeta,

    // If given a generic record type (no predefined fields), the original record is returned
    Record.ChangeType = (record as record, recordType as type) =>
        let
            // record field format is [ fieldName = [ Type = type, Optional = logical], ... ]
            fields = try Type.RecordFields(recordType) otherwise error "Record.ChangeType: failed to get record fields. Is this a record type?",
            fieldNames = Record.FieldNames(fields),
            fieldTable = Record.ToTable(fields),
            optionalFields = Table.SelectRows(fieldTable, each [Value][Optional])[Name],
            requiredFields = List.Difference(fieldNames, optionalFields),
            // make sure all required fields exist
            withRequired = Record.SelectFields(record, requiredFields, MissingField.UseNull),
            // append optional fields
            withOptional = withRequired & Record.SelectFields(record, optionalFields, MissingField.Ignore),
            // set types
            transforms = GetTransformsForType(recordType),
            withTypes = Record.TransformFields(withOptional, transforms, MissingField.Ignore),
            // order the same as the record type
            reorder = Record.ReorderFields(withTypes, fieldNames, MissingField.Ignore)
        in
            if (List.IsEmpty(fieldNames)) then record else reorder,

    List.ChangeType = (list as nullable list, listType as type) =>
        if list = null then null else
        if (not Type.Is(listType, type list)) then error "type argument should be a list type" else
        let
            listItemType = Type.ListItem(listType),
            transform = GetTransformByType(listItemType),
            modifiedValues = List.Transform(list, transform),
            typed = Value.ReplaceType(modifiedValues, listType)
        in
            typed,

    // Returns a table type for the provided schema table
    Schema.ToTableType = (schema as table) as type =>
        let
            toList = List.Transform(schema[Type], (t) => [Type=t, Optional=false]),
            toRecord = Record.FromList(toList, schema[Name]),
            toType = Type.ForRecord(toRecord, false),
            previousMeta = Value.Metadata(schema)
        in
            type table (toType) meta previousMeta,

    // Returns a list of transformations that can be passed to Table.TransformColumns, or Record.TransformFields
    // Format: {"Column", (f) => ...) .... ex: {"A", Number.From}
    GetTransformsForType = (_type as type) as list =>
        let
            fieldsOrColumns = if (Type.Is(_type, type record)) then Type.RecordFields(_type)
                            else if (Type.Is(_type, type table)) then Type.RecordFields(Type.TableRow(_type))
                            else error "GetTransformsForType: record or table type expected",
            toTable = Record.ToTable(fieldsOrColumns),
            transformColumn = Table.AddColumn(toTable, "Transform", each GetTransformByType([Value][Type]), Function.Type),
            transformMap = Table.ToRows(Table.SelectColumns(transformColumn, {"Name", "Transform"}))
        in
            transformMap,

    GetTransformByType = (_type as type) as function =>
                if (Type.Is(_type, type number)) then Number.From
        else if (Type.Is(_type, type text)) then Text.From
        else if (Type.Is(_type, type date)) then Date.From
        else if (Type.Is(_type, type datetime)) then DateTime.From
        else if (Type.Is(_type, type duration)) then Duration.From
        else if (Type.Is(_type, type datetimezone)) then DateTimeZone.From
        else if (Type.Is(_type, type logical)) then Logical.From
        else if (Type.Is(_type, type time)) then Time.From
        else if (Type.Is(_type, type record)) then (t) => if (t <> null) then @Record.ChangeType(t, _type) else t
        else if (Type.Is(_type, type table)) then (t) => if (t <> null) then @Table.ChangeType(t, _type) else t
        else if (Type.Is(_type, type list)) then (t) => if (t <> null) then @List.ChangeType(t, _type) else t
        else (t) => t,

	Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            ),

FuncDocumentation = (Counters as function, Schema as table) =>
let
    /*Counters = ( 
        optional search_string as text, 
        optional field as list 
    //    optional #"type" as text 
    ) => 1,//*/

    func_type = Value.Type(Counters),
    func_param = Type.FunctionParameters(func_type),
    req_parameters = Type.FunctionRequiredParameters(func_type),
    return_type = Type.FunctionReturn(func_type),

    params_list = Record.FieldNames(func_param),
    Source = Schema2,

    func = Table.SelectRows(Source, each List.ContainsAny( params_list, {[Name], [AllowedValues]} )),

    // rows with parameters description
    params_desc = Table.SelectRows( Source, each List.Contains( params_list, [Name]) and [ AllowedValues ] = "" ),

    // get allowed values
    allowed_desc = Table.SelectRows( Source, each List.Contains( params_list, [ AllowedValues ])),
    allowed_vals = Table.Group( allowed_desc, "AllowedValues", {"Name", each _[ Name ]}),
    join_allowed = Table.NestedJoin( params_desc, "Name", allowed_vals, "AllowedValues", "AllowedVals", JoinKind.LeftOuter ),
    
    // make type with metadata
    types = 
        List.Transform(
            Table.ToRecords( join_allowed ),
            each 
                Expression.Evaluate(_[Type], #shared) 
                meta (
                    [
                        Documentation.FieldCaption = _[Caption],
                        Documentation.FieldDescription = _[Description]
                    ] & ( 
                        if _[AllowedVals][Name]{0}? = null then [] 
                        else [ Documentation.AllowedValues = _[AllowedVals][Name]{0} ]
                    )
                )
        ),

    fromList = Record.FromList(types, params_desc[Name]), // all parameters
    sort_old = Record.ReorderFields(fromList, params_list), // sort parameters in original order

    // complete documentation for function
    toFunction = Type.ForFunction([ReturnType = return_type, Parameters = sort_old], req_parameters) meta [
        Documentation.Name = "Список доступных счетчиков",
        Documentation.LongDescription = "Возвращает список существующих счетчиков, доступных пользователю.",
        Documentation.Description = "Func Description",
        Documentation.DisplayName = "Display Name",
        Documentation.Caption = "Caption"/*,
        Documentation.Examples = {[
            Description = "First example description",
            Code = "First example code",
            Result = "First example result"
        ]}*/
    ],
    return = Value.ReplaceType(Counters,toFunction)
in
    return,
///////////////
    Source2 = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("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", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [SortOrder = _t, Name = _t, AllowedValues = _t, Type = _t, Caption = _t, Description = _t]),
    Schema2 = Table.TransformColumnTypes(Source2,{{"SortOrder", Int64.Type}, {"Name", type text}, {"AllowedValues", type text}, {"Type", type text}, {"Caption", type text}, {"Description", type text}}),

TableSchema2 = 
 let
    Source = Schema2,

    Type.FromTable = ( table as table, optional return_type as type, optional environment as record ) =>
        let
            environment = if environment = null then #shared else #shared & environment,
            make_type = Table.TransformColumns( 
                table, {{"Type", (t) => 
                    if t = "" then Text.Type
                    else Expression.Evaluate( t, environment ), 
                    type type }}), 
            toList = List.Transform( make_type[Type], ( t ) => [ Type = t, Optional = false ]),
            toRecord = Record.FromList( toList, table[ Name ]),
            toType = Type.ForRecord( toRecord, false ),
            previousMeta = Value.Metadata( table ),
            return =
                if return_type = null then toType
                else if Type.Is( return_type, type table ) then type table ( toType )
                else toType
        in
            return meta previousMeta,

    get_main_type = ( t as text ) as type =>
        if Text.Contains( t, "Table") then type table 
        else type record,

    recursive_types = (schema as table, optional env as record, optional nesting as number) => 
        let
            env = if env = null then [] else env,
            nesting = if nesting = null then 0 else nesting,
            rfn = Record.FieldNames( #shared & env ),
            check_environment = Table.SelectRows( schema, each List.ContainsAll( rfn, _[ data ][ Type ] )),
            rows = Table.ToRecords( check_environment ),
            root = check_environment{ [ AllowedValues = "" ]}?,
            make_types = List.Transform( 
                rows, 
                each 
                    Record.AddField(
                        [], 
                        _[ AllowedValues ], 
                        Type.FromTable( _[ data ], get_main_type( _[ AllowedValues ] ), env )
                    )
            ),
            new_types = Record.Combine( make_types ),
            no_matches = Table.SelectRows( Table.Combine( schema[ data ]), each not List.Contains( rfn, _[ Type ]) ),
            return = 
                // uncomment next line to debug
                //if nesting = 2 then [ no_matches = no_matches, env = env, new_types = new_types, root = root[data]? ] /*// 
                if nesting > 10 then // prohibit endless loop
                    error Error.Record( 
                        "nesting limit of 10 is reached", 
                        Text.From( nesting ), 
                        "There's no type for field(s): " & Text.Combine( no_matches[ Name ], "," ) 
                    ) //*/
                else if root = null then @recursive_types( schema, new_types, nesting + 1 ) 
                else Type.FromTable( root[ data ], type table, env ) // exit loop
        in
            return,

    TableSchema = Table.SelectRows(
        Source, each 
            Value.Is( Value.FromText([SortOrder]), type number ) // takes part in sorting
            or Text.Length( Text.From([Type]) ) > 0 // assigned type
    ),

    // sort_order = Table.Sort(TableSchema, {"SortOrder"}),

    filter_types = Table.TransformColumns(TableSchema, {{"AllowedValues", each if Text.EndsWith(_, ".Type") then _ else ""}}),

    type_description = Table.SelectColumns(filter_types,{"Name", "AllowedValues", "Type"}),

    schema_grouped = Table.Group(type_description,"AllowedValues",{{"data", each _}}),

    return = recursive_types( schema_grouped )
in
    return,


//////////////////////////	
    base_url = "https://api-metrika.yandex.net/management/v1",
	


	Web.ContentsWrapped = (access_token, rp as list, optional post as logical, optional query as record, optional retry as logical) =>
		let

			Headers = [
				#"Authorization" = "Bearer " & access_token,
				#"Accept-Language" = "ru",
				#"Accept-Encoding" = "gzip"
			],
			options = [
				Headers = Headers,
				RelativePath = Text.Combine( List.Transform( rp, (p) => Text.From(p) ), "/" ),
				ManualStatusHandling = {400},
				//ManualCredentials = true,
				IsRetry = if retry = null then false else retry, 
				Content = if post = null or post = false then null else Json.FromValue([]),
				Query = query
			],
			response = Web.Contents(base_url, options)
		in
			response,

/*

НАЧАЛО ЗДЕСЬ

*/

field_set = ( optional fields as list) => // в этом воплощении рушит порядок сортировки
    let
        fields = //{"goals"} ,/*
            if fields = null then {}
            else if List.Contains(fields, "mirrors") then fields & {"mirrors2"}
            else fields,//*/
        default = {"id", "status", "owner_login", "code_status", "name", "type", "favorite", "hide_address", "permission", "webvisor", "code_options", "create_time", "time_zone_name", "time_zone_offset", "connect_status", "partner_id", "site", "site2", "gdpr_agreement_accepted", "source"},
        field_set = default & fields
    in
        field_set,

Schema4Columns2 = ( columns as list ) as type =>
    let
        Source = TableSchema2,
        tableRow = Type.TableRow(Source), // type record
        columnsForType = Type.RecordFields( tableRow ), // record
        toRecord = Record.SelectFields( columnsForType, columns ),
        toType = Type.ForRecord( toRecord, false ),
        return = type table (toType)
    in
        return,

Renames = ( fields as list) => 
    let
        rows = Table.SelectRows( Schema2, each Value.Is( Value.FromText([SortOrder]), type number )), // takes part in sorting,
        cols = Table.SelectColumns( rows, {"Name", "Caption"}),
        return = Table.ToRows( cols )
    in
        return,

    // https://yandex.ru/dev/metrika/doc/api2/management/counters/counters-docpage/
	Counters = ( access_token as text, optional search_string as text, optional field as list ) =>
		let 
		    // check params and make closure
			limit = 100,
			query = [
				search_string = if search_string = null then "" else search_string,
				per_page = Text.From(limit)
			] & ( if field{0}? = null then [] else [ field = Text.Combine(field, ",")] ),

            getCounterPage = (offset) =>
                let
                    test = Web.ContentsWrapped(access_token, {"counters"}, false, query & [ offset = Text.From(offset) ]),
                    json = Json.Document(test)
                in
                    json,

            fields = field_set(field),

            // test connection and save metadata
            test = getCounterPage(1),
            max_rows = test[rows],
            table = Table.GenerateByPage( 
                ( previous ) =>
                let
                    // check params
                    offset = if previous = null then limit + 1 else Value.Metadata(previous)[NextPage]?,

                    // do the job
                    json = getCounterPage(offset),
                    table = Table.FromList(json[counters], Splitter.SplitByNothing(), {"Column1"}, null, ExtraValues.Error),

                    // handle errors
                    return = 
                        if offset > max_rows then null // there is no more data
                        else 
                            table meta [ NextPage = offset + limit ]
                in
                    return
            ),
            combine_table = 
                if table{0}? = null then test[ counters ] 
                else test[ counters ] & table[ Column1 ],
            change_type = //return,/*
                Table.ChangeType(
                    combine_table,
                    Schema4Columns2(fields)
                ),
            return = //change_type /*
                Table.RenameColumns(
                    change_type, 
                    Renames(fields), 
                    MissingField.Ignore
                ) meta [ TotalRows = max_rows, Query = query ] //*/
		in 
            if test[errors]? <> null then // this has error
				error Error.Record(test[errors]{0}[error_type], test[errors]{0}[message], test[errors]{0}[location])
            else return,
/*
View = ( state as record ) =>
    Table.View(
        null, [
            GetType = () => Table.Schema,
            GetRows = () =>
            OnTake = (count as number) => 
        ]
    )
*/
    Source = FuncDocumentation(Counters, Schema2)//Value.ReplaceType(Counters, Counters.Type)
in
    Source
