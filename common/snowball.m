// стеммер http://snowball.tartarus.org/algorithms/russian/stemmer.html
// прошел тест https://github.com/mazko/jssnowball/tree/master/js_snowball/tests/js

(word as text) => // если слово состоит из символов, отличных от а-я, то оно вернется в неизменном виде
let
    //words = "уставший",

    letters = {"а".."я"},

    matches = ( word, endings ) => let
        porter = Record.Field( PORTER, endings ), // получаю нужный список суффиксов и окончаний
        has_groups = Value.Is( porter, type list ), // проверяю группы в списке
        l = 
            if has_groups then // если есть группы, то 
                List.Combine(List.Transform(Text.Split(porter{0},","), each {"а" & _, "я" & _})) // комбинирую первую с "а" и "я"
                & Text.Split(porter{1},",") // вторую просто разрезаю по запятым
            else Text.Split(porter,","), // просто нарезаю по запятым
        s = List.Sort( l, (x, y) => Value.Compare( Text.Length( y ), Text.Length( x ))), // сортирую в порядке убывания длины. Возможно, есть смысл заранее это сделать, но сейчас не хочется )
        m = List.Transform( s, each Text.EndsWith( word, _ )), // проверяю каждое окончание, по идее можно было бы прерваться после первого совпадения. Вероятно, без генератора списка не обойтись
        pretend = s{List.PositionOf( m, true )}, // кандидат на выбывание (самое длинное найденное совпадение)
        start = Text.Start( pretend, 1 ), // первая буква в этом слове
        f = if has_groups and pretend <> "ят" and ( start = "а" or start = "я" ) then // если список комбинировал
                Text.TrimStart( pretend, start ) // то отрезаю первую букву "а" или "я", за исключением окончания "ят"
            else pretend, 
        r = Text.Start( word, Text.Length( word ) - Text.Length( f ) ), // вырезаю начало слова
        return = 
            if List.AnyTrue( m ) then r meta [ part = endings ]
            else word meta [ part = null ]
    in return,
    

    vovels = Text.ToList(PORTER[VOVEL]),
    first_vovel = Text.PositionOfAny(Source,vovels),
    RV = Text.Range(Source,first_vovel+1),

    R2 = (RV) => let RV_map = Text.Combine(List.Transform(Text.ToList(RV), each if List.Contains(vovels,_) then "a" else "b")) in Text.Range(RV, try Text.PositionOf(RV_map,"ba",2){1} + 1 otherwise Text.Length(RV)),
    
    Source = Text.Replace(Text.Lower(word), "ё", "е"),

    PORTER = [
        VOVEL = "аеиоуыэюя", // список гласных
        PERFECTIVEGERUND = {"в,вши,вшись", "ив,ивши,ившись,ыв,ывши,ывшись"},
        ADJECTIVE = "ее,ие,ые,ое,ими,ыми,ей,ий,ый,ой,ем,им,ым,ом,его,ого,ему,ому,их,ых,ую,юю,ая,яя,ою,ею", // прилагательное
        PARTICIPLE = {"ем,нн,вш,ющ,щ", "ивш,ывш,ующ"}, // причастие?
        REFLEXIVE = "ся,сь", // возвратный глагол 
        VERB = {"ла,на,ете,йте,ли,й,л,ем,н,ло,но,ет,ют,ны,ть,ешь,нно", "ила,ыла,ена,ейте,уйте,ите,или,ыли,ей,уй,ил,ыл,им,ым,ен,ило,ыло,ено,ят,ует,уют,ит,ыт,ены,ить,ыть,ишь,ую,ю"}, // глагол
        NOUN = "а,ев,ов,ие,ье,е,иями,ями,ами,еи,ии,и,ией,ей,ой,ий,й,иям,ям,ием,ем,ам,ом,о,у,ах,иях,ях,ы,ь,ию,ью,ю,ия,ья,я", // существительное
        SUPERLATIVE = "ейш,ейше", // превосходная степень?
        DERIVATIONAL = "ост,ость" // отглагольное существительное
    ],

    step1 = matches(RV, "PERFECTIVEGERUND"),
    m1 = Value.Metadata(step1b2),
    step1a = matches(RV,"REFLEXIVE"),

    step1b1 = matches(step1a,"ADJECTIVE"),
    step1b2 = if step1b1 <> step1a then matches(step1b1,"PARTICIPLE") else step1a,
    step1c = matches(step1a,"VERB"),
    step1d = matches(step1a,"NOUN"),
    
    step1result =
        if step1 <> RV then step1
        else List.Sort({step1b2, step1c, step1d}, (x, y) => Value.Compare(Text.Length(x), Text.Length(y))){0},
        
    step2 = Text.TrimEnd(step1result,"и"),

    step2R2 = R2(step2),
    step3 = if matches(step2R2,"DERIVATIONAL") <> step2R2 then matches(step2,"DERIVATIONAL") else step2,

    step4super = matches(step3,"SUPERLATIVE"),
    step4 = 
        if Text.EndsWith(step3, "ь") or Text.EndsWith(step3, "нн") then Text.Start(step3,Text.Length(step3)-1)
        else if step4super <> step3 then if Text.EndsWith(step4super, "нн") then Text.Start(step4super,Text.Length(step4super)-1) else step4super
        else step3,

    return = 
        if List.ContainsAll(letters, Text.ToList(Source)) and first_vovel >= 0
        then Text.Start(Source, first_vovel+1) & step4
        else word
in
    return
