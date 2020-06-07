    Record.ToUriQuery = (r as record, optional sep as text ) =>
        let
            sep = if sep = null then "," else sep,
            tabl = Record.ToTable(r),
            vals = Table.TransformColumns(tabl, {"Value", each
                if Value.Is( _, type list ) then 
                    ( v ) => Text.Combine( List.Transform( v, Text.From), sep )
                else ( v ) => Text.From( v )
            }),
            tl = Table.ToRows(vals),
            apply = Record.TransformFields(r,tl)
        in
            apply
