let
	tokenYandexMetrika = ya_token, // ссылка на параметр с токеном

	///* тестовые значения
	Directory = "Campaigns", // https://yandex.ru/dev/direct/doc/ref-v5/campaigns/campaigns-docpage/
	Ids = {51455525}, // список. работает в camp, adgroup, ads
	FieldNames = { "Id", "Name", "NegativeKeywords" }, //{"NegativeKeywords", "BlockedIps", "ExcludedSites", "Currency", "DailyBudget", "Notification", "EndDate", "Funds", "ClientInfo", "Id", "Name", "NegativeKeywords", "RepresentedBy", "StartDate", "Statistics", "State", "Status", "StatusPayment", "StatusClarification", "SourceId", "TimeTargeting", "TimeZone", "Type"}, // camp, adgroup, ads
	Types = null, // список. работает в camp, adgroup, ads
	Statuses = null, // список. работает в camp, adgroup, ads
	States = null, // список. работает в camp
	Limit = 1000, // число (для тестов использовал такое небольшое)
	Offset = 0, // число
	//*/

	/*	Структура полей запроса из документации
		Преобразовать к нотации Power Query M
		Можно перечислить все поля из документации, а ненужным присвоить null
	*/

	Request = [
		method = "get", // обязательное
		params = [ // обязательное
			SelectionCriteria = [ // обязательное, может быть с пустой записью внутри, чтобы выбрать всё
				Ids = Ids, //
				Types = Types, //
				States = States, //
				Statuses = Statuses, //
				StatusesPayment = null //
			], 
			FieldNames = FieldNames, // обязательное
			TextCampaignFieldNames = null, //
			MobileAppCampaignFieldNames = null, //
			DynamicTextCampaignFieldNames = null, //
			CpmBannerCampaignFieldNames = null, //
			SmartCampaignFieldNames = null/*, //
			Page = [ // можно оставить, чтобы управлять Limit
				Limit = Limit, //
				Offset = Offset //
			]*/
		]
	],

	/*	Создает поле в записи на любом уровне вложенности 
		Иерархия (путь) задается в fields
		Если задать несуществующую иерархию, то она будет создана
	*/
	record_replace_value = ( rec as record, field as list, value as any ) => let
		depth = List.Count(field) - 1, // индексы начинаются с 0, а кол-во полей - с 1
		go_deep = (rec as record, optional level as number) => let this_field = field { level } // название поля на текущем уровне
		in Record.AddField(
			Record.SelectFields( // выбираю значения остальных полей (не тех, в которых будут изменения)
				rec, 
				List.RemoveItems( 
					Record.FieldNames( rec ), // из списка названий всех существующих полей
					{ this_field } // удаляю название того, которое буду менять
				)
			), 
			this_field, 
			if level = depth then value // погрузился на максимальную глубину иерархии, поэтому подставляю новое значение
			else // рекурсивно погружаюсь на следующий уровень
				@go_deep(
					try Record.Field( rec, this_field ) otherwise [], // если поля нет, то оно будет создано
					level + 1
				)
		)
	in go_deep(rec, 0),

	/*	делает "плоскую" иерархию: рекурсивно переносит вложенные записи на один уровень. 
		Название вложенных записей комбинируется через ".": "имя_внешней.имя_вложенной"
	*/
	flat_record = ( rec as record, optional last_name ) => let
		test_types = List.Transform(
			Record.FieldNames( rec ), // названия полей, которые буду перебирать
			each let 
					this_name = Text.Combine({ last_name, _ },"."), // новое название для поля: "имя_внешнего"."имя_вложенного"
					this_value = Record.Field( rec, _ ) // значение текущего поля
				in
					if Value.Is( Record.Field( rec, _ ), type record ) then // если текущее поле - запись
						@flat_record( this_value, this_name ) // погружаюсь дальше
					else { Record.AddField( [], this_name, this_value )} // создаю новую запись новое_название = значение
		),
		ret = List.Combine(test_types) // делаю плоский список всех записей
	in ret,

	// обертка для flat_records
	flat_run = (rec as list) => let
		row_list = List.Transform(
			List.Zip({{ 1..List.Count(rec) }, rec }), // добавляю индекс для pivot
			each { _{0}, Record.ToTable( Record.Combine( flat_record( _{1} )))} // делаю таблицу из "плоских" записей
		),
		tabl = Table.FromRows( row_list, type table [ Index = number, Table = table ]),
		expand = Table.ExpandTableColumn( tabl, "Table", { "Name", "Value" }), // стандартные названия, созданные Record.ToTable
		pivot = Table.Pivot( expand, List.Distinct( expand[ Name ]), "Name", "Value" ), // тут нужен индекс
		drop_index = Table.RemoveColumns( pivot, "Index" ), // индекс больше не нужен
		reorder = Table.ReorderColumns( drop_index, List.Sort( Table.ColumnNames( drop_index ))), // сортирую колонки по алфавиту
		return = reorder
	in return,
	
	// рекурсивно удаляет вложенные поля записи равные null, при этом родительское поле может остаться пустым 
	remove_nulls = ( rec as record ) => Record.Combine(
		List.Transform( 
			Record.FieldNames( rec ), // названия полей, которые буду перебирать
			each let val = Record.Field( rec, _ ) in // сохраняю значение текущего поля
				if Value.Is( val, type record ) then // если текущее поле - запись
					let inner_val = @remove_nulls( val ) in // проверяю вложенную запись
					//if inner_val = [] then [] else // раскомментировать, если вложенная запись пустая, и ее нужно удалить 
					Record.AddField( [], _, inner_val ) // копирую вложенную запись
				else if val = null then [] else Record.AddField( [], _, val )
		)
	),

	/*
	// рекурсивно применяет функцию ко всем полям записи
	apply = ( rec as record, func as function ) => let
		field_names = Record.FieldNames( rec ),
		field_trans = List.Transform( 
			field_names, 
			each  
				if Value.Is( Record.Field( rec, _ ), type record ) then 
					(val) => @apply( val, func )
				else (val) => func( val )
		),
		trans_list = List.Zip({ field_names, field_trans }),
		return = Record.TransformFields( rec, trans_list )
	in return,
	*/

	response = (offset) => Web.Contents( 
		"https://api.direct.yandex.com/json/v5/", [ 
			Content = Json.FromValue(
				record_replace_value( content, { "params", "Page", "Offset" }, offset ) // переключаю страницу, если нужно
			),
			Headers = [
				#"Authorization" = "Bearer " & tokenYandexMetrika,
				#"Accept-Language" = "ru"
			],
			RelativePath = Text.Lower( Directory ) // API не принимает в другом регистре
		]
	),

	content = remove_nulls( Request ), // удаляю незаполненные поля запроса

	Source = Json.Document( response(0) ), // для проверки ошибок
	result = Source[ result ], // используется в паре мест
	Field.Offset = "LimitedBy", // для удобства
	another = List.RemoveItems( Record.FieldNames( result ), { Field.Offset }){0}, // название другого поля ответа, не LimitedBy, его название меняется в зависимости от запрашиваемого справочника
	offs = ( rec as record ) => if Record.HasFields( rec, Field.Offset ) then Record.Field( rec, Field.Offset ) else null, // просто чтобы сократить строку в генераторе
	
	pages = List.Generate(
		()=> [
			resulta = result,
			offset = offs( resulta ),
			delay = 1 // делает задержку в 1 шаг, чтобы получить последнюю страницу пагинации
		],
		each [ delay ] > 0,
		each [
			resulta = Json.Document( response([ offset ]))[ result ],
			delay = if [ offset ] = null then 0 else [ delay ],
			offset = offs( resulta )
		]
		, each Record.Field([ resulta ], another ) // оставляю только то, что нужно
	),

	combine = List.Combine( pages ),
	unpack = flat_run( combine ),
	
	return = if Record.HasFields( Source, "result" ) then unpack else try Source[ error ] otherwise Source
	//return = record_replace_value(content,{"params", "Page", "Offset"},120)[params]
in
    return
