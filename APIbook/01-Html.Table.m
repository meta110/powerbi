let
  // СПИСОК СРЕЗОВ И МЕТРИК ДЛЯ ДОКУМЕНТАЦИИ
  Docs = Web.BrowserContents("https://developers.google.com/analytics/devguides/reporting/mcf/dimsmets/interactions?hl=ru"),
  #"Extracted Table From Html" = Html.Table(Docs, {
    {"group", "h2"},
    {"name", "h3"}, 
    {"description", "div.ind > p"}
  }, [RowSelector="h3[id^=""mcf""]"]),
  #"Added Conditional Column" = Table.AddColumn(#"Extracted Table From Html", "type", each if [group] = null then null else "dimension", type text),
  #"Filled Up" = Table.FillUp(#"Added Conditional Column",{"type"}),
  #"Replaced Value" = Table.ReplaceValue(#"Filled Up",null,"metric",Replacer.ReplaceValue,{"type"}),
  AllowedValues = Table.RemoveColumns(#"Replaced Value",{"group"})
in
  AllowedValues
